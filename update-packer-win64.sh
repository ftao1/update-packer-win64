#!/bin/bash

set -euo pipefail

# Configuration
readonly SCRIPT_NAME="$(basename "$0")"
readonly BASE_URL="https://releases.hashicorp.com/packer"
readonly HASHICORP_API_URL="https://api.releases.hashicorp.com/v1/releases/packer"
readonly TEMP_DIR="/tmp/packer-update-$$"
readonly LOG_FILE="/tmp/packer-update.log"
readonly MAX_RETRIES=3
readonly RETRY_DELAY=2

# Color variables
readonly RED=$'\033[0;31m'
readonly GREEN=$'\033[0;32m'
readonly YELLOW=$'\033[1;33m'
readonly BLUE=$'\033[0;34m'
readonly NOCOL=$'\033[0m'

# Global variables
REQUESTED_VERSION=""
CURRENT_VERSION=""
BACKUP_FILE=""

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

# Print colored messages
print_red() {
    echo -e "${RED}$1${NOCOL}"
    log "ERROR" "$1"
}

print_green() {
    echo -e "${GREEN}$1${NOCOL}"
    log "INFO" "$1"
}

print_yellow() {
    echo -e "${YELLOW}$1${NOCOL}"
    log "WARN" "$1"
}

print_blue() {
    echo -e "${BLUE}$1${NOCOL}"
    log "INFO" "$1"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Validate version format (semantic versioning)
validate_version() {
    local version="$1"
    if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9]+)?$ ]]; then
        print_red "Invalid version format: $version"
        print_red "Expected format: X.Y.Z or X.Y.Z-suffix (e.g., 1.9.4 or 1.9.4-beta1)"
        return 1
    fi
    return 0
}

# Sanitize input to prevent command injection
sanitize_input() {
    local input="$1"
    # Remove any characters that could be used for command injection
    input=$(echo "$input" | sed 's/[;&|`$(){}[\]\\]//g')
    echo "$input"
}

# Download with retry logic
download_with_retry() {
    local url="$1"
    local output="$2"
    local attempt=1
    
    while [ $attempt -le $MAX_RETRIES ]; do
        log "INFO" "Download attempt $attempt/$MAX_RETRIES: $url"
        
        if curl -fsSL --connect-timeout 30 --max-time 300 --retry 3 "$url" -o "$output"; then
            log "INFO" "Successfully downloaded: $output"
            return 0
        else
            local exit_code=$?
            log "WARN" "Download attempt $attempt failed (exit code: $exit_code)"
            
            if [ $attempt -lt $MAX_RETRIES ]; then
                local delay=$((RETRY_DELAY * attempt))
                log "INFO" "Retrying in $delay seconds..."
                sleep $delay
            fi
        fi
        
        ((attempt++))
    done
    
    print_red "Failed to download after $MAX_RETRIES attempts: $url"
    return 1
}

# Verify SHA256 checksum
verify_checksum() {
    local file="$1"
    local shasums_file="$2"
    
    log "INFO" "Verifying SHA256 checksum for $file"
    
    # Extract only the checksum line for the specific file
    local expected_checksum=$(grep "$(basename "$file")" "$shasums_file" | cut -d' ' -f1)
    
    if [[ -z "$expected_checksum" ]]; then
        print_red "No checksum found for $(basename "$file") in $shasums_file"
        return 1
    fi
    
    local actual_checksum=$(sha256sum "$file" | cut -d' ' -f1)
    
    if [[ "$actual_checksum" = "$expected_checksum" ]]; then
        print_green "SHA256 checksum verification passed"
        return 0
    else
        print_red "SHA256 checksum verification failed for $file"
        log "ERROR" "Expected: $expected_checksum"
        log "ERROR" "Actual:   $actual_checksum"
        return 1
    fi
}

# Get current packer version
get_current_version() {
    if command_exists packer; then
        CURRENT_VERSION=$(packer --version 2>/dev/null | head -n1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo "unknown")
    else
        CURRENT_VERSION="not installed"
    fi
}

# Get available versions from HashiCorp API
get_available_versions() {
    log "INFO" "Fetching available versions from HashiCorp API"
    
    local api_response
    if ! api_response=$(curl -fsSL --connect-timeout 10 "$HASHICORP_API_URL" 2>/dev/null); then
        print_yellow "Failed to fetch from API, falling back to releases page"
        curl -fsSL "$BASE_URL/" | grep -oE 'packer_[0-9]+\.[0-9]+\.[0-9]+' | sed 's/packer_//' | sort -V | tail -10
        return
    fi
    
    echo "$api_response" | grep -oE '"version":"[0-9]+\.[0-9]+\.[0-9]+[^"]*"' | cut -d'"' -f4 | sort -V | tail -10
}

# Check if version exists
version_exists() {
    local version="$1"
    local url="${BASE_URL}/${version}/packer_${version}_windows_amd64.zip"
    
    log "INFO" "Checking if version $version exists"
    
    if curl -fsSL --head --connect-timeout 10 "$url" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Create backup of existing packer.exe
create_backup() {
    if [ -f "packer.exe" ]; then
        local timestamp=$(date '+%Y%m%d_%H%M%S')
        BACKUP_FILE="packer.exe.backup.$timestamp"
        
        log "INFO" "Creating backup: $BACKUP_FILE"
        
        if cp "packer.exe" "$BACKUP_FILE"; then
            print_green "Backup created: $BACKUP_FILE"
            return 0
        else
            print_red "Failed to create backup"
            return 1
        fi
    fi
    return 0
}

# Restore from backup
restore_backup() {
    if [ -n "$BACKUP_FILE" ] && [ -f "$BACKUP_FILE" ]; then
        log "INFO" "Restoring from backup: $BACKUP_FILE"
        
        if cp "$BACKUP_FILE" "packer.exe"; then
            print_green "Restored from backup successfully"
            return 0
        else
            print_red "Failed to restore from backup"
            return 1
        fi
    fi
    return 1
}

# Cleanup function
cleanup() {
    log "INFO" "Cleaning up temporary files"
    
    if [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
    fi
    
    # Remove backup file if installation was successful
    if [ -n "$BACKUP_FILE" ] && [ -f "$BACKUP_FILE" ] && [ "$1" = "success" ]; then
        rm -f "$BACKUP_FILE"
        log "INFO" "Removed backup file after successful installation"
    fi
}

# Signal handler for cleanup
signal_handler() {
    local signal="$1"
    print_yellow "Received signal $signal, cleaning up..."
    
    # Restore backup if available
    if [ -n "$BACKUP_FILE" ] && [ -f "$BACKUP_FILE" ]; then
        restore_backup
    fi
    
    cleanup "interrupted"
    # Always reset colors before exiting
    echo -e "${NOCOL}"
    exit 130
}

# Function to reset colors on exit
reset_colors() {
    echo -e "${NOCOL}"
}

# Set up signal handlers
trap 'signal_handler SIGINT' INT
trap 'signal_handler SIGTERM' TERM
trap 'reset_colors' EXIT

# Main download and install function
download_and_install() {
    local version="$1"
    local zip_file="packer_${version}_windows_amd64.zip"
    local shasums_file="packer_${version}_SHA256SUMS"
    local zip_url="${BASE_URL}/${version}/${zip_file}"
    local shasums_url="${BASE_URL}/${version}/${shasums_file}"
    
    # Create temporary directory
    if ! mkdir -p "$TEMP_DIR"; then
        print_red "Failed to create temporary directory: $TEMP_DIR"
        return 1
    fi
    
    print_blue "==> Downloading Packer $version..."
    
    # Download files
    if ! download_with_retry "$zip_url" "$TEMP_DIR/$zip_file"; then
        return 1
    fi
    
    if ! download_with_retry "$shasums_url" "$TEMP_DIR/$shasums_file"; then
        return 1
    fi
    
    # Verify checksum
    print_blue "==> Verifying SHA256 checksum..."
    if ! (cd "$TEMP_DIR" && verify_checksum "$zip_file" "$shasums_file"); then
        return 1
    fi
    
    # Create backup
    if ! create_backup; then
        return 1
    fi
    
    # Extract
    print_blue "==> Extracting Packer..."
    if ! (cd "$TEMP_DIR" && unzip -q "$zip_file"); then
        print_red "Failed to extract $zip_file"
        restore_backup
        return 1
    fi
    
    # Verify extracted file
    if [ ! -f "$TEMP_DIR/packer.exe" ]; then
        print_red "packer.exe not found in extracted files"
        restore_backup
        return 1
    fi
    
    # Install
    print_blue "==> Installing Packer..."
    if ! cp "$TEMP_DIR/packer.exe" "packer.exe"; then
        print_red "Failed to install packer.exe"
        restore_backup
        return 1
    fi
    
    # Set permissions
    chmod 755 "packer.exe"
    
    # Verify installation
    if ! ./packer.exe --version >/dev/null 2>&1; then
        print_red "Installed packer.exe is not working correctly"
        restore_backup
        return 1
    fi
    
    print_green "==> Installation successful!"
    return 0
}

# Show usage information
show_usage() {
    cat << EOF
${GREEN}USAGE:${NOCOL} ./$SCRIPT_NAME <version>

${GREEN}DESCRIPTION:${NOCOL}
    Downloads and installs a specific version of HashiCorp Packer for Windows.

${GREEN}EXAMPLES:${NOCOL}
    ./$SCRIPT_NAME 1.9.4
    ./$SCRIPT_NAME 1.9.4-beta1

${GREEN}OPTIONS:${NOCOL}
    -h, --help    Show this help message

${GREEN}NOTES:${NOCOL}
    - Requires curl, unzip, and sha256sum to be installed
    - Creates automatic backups of existing packer.exe
    - Verifies downloads using SHA256 checksums
    - Supports automatic retry on network failures
EOF
}

# Main function
main() {
    # Initialize logging
    log "INFO" "Starting $SCRIPT_NAME"
    
    # Parse arguments
    case "${1:-}" in
        -h|--help)
            show_usage
            exit 0
            ;;
        "")
            get_current_version
            echo -e "Current version: ${GREEN}$CURRENT_VERSION${NOCOL}"
            echo
            print_blue "Available versions (latest 10):"
            get_available_versions
            exit 0
            ;;
        *)
            REQUESTED_VERSION=$(sanitize_input "$1")
            ;;
    esac
    
    # Validate version format
    if ! validate_version "$REQUESTED_VERSION"; then
        exit 1
    fi
    
    # Check required commands
    for cmd in curl unzip sha256sum; do
        if ! command_exists "$cmd"; then
            print_red "Required command not found: $cmd"
            print_red "Please install $cmd and try again."
            exit 1
        fi
    done
    
    # Get current version
    get_current_version
    
    # Check if same version is already installed
    if [ "$CURRENT_VERSION" = "$REQUESTED_VERSION" ]; then
        print_green "Packer $REQUESTED_VERSION is already installed."
        exit 0
    fi
    
    # Check if requested version exists
    if ! version_exists "$REQUESTED_VERSION"; then
        print_red "Version $REQUESTED_VERSION does not exist or is not available."
        echo
        print_blue "Available versions (latest 10):"
        get_available_versions
        exit 1
    fi
    
    # Show installation info
    echo
    print_blue "Current version: $CURRENT_VERSION"
    print_blue "Requested version: $REQUESTED_VERSION"
    echo
    
    # Download and install
    if download_and_install "$REQUESTED_VERSION"; then
        cleanup "success"
        echo
        print_green "✓ Successfully updated Packer to version $REQUESTED_VERSION"
        print_green "✓ Verify with: ./packer.exe --version"
        log "INFO" "Installation completed successfully"
    else
        cleanup "failed"
        print_red "✗ Installation failed"
        log "ERROR" "Installation failed"
        exit 1
    fi
}

# Run main function
main "$@"