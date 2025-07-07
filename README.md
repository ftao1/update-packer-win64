# Update HashiCorp Packer on Windows

Production-ready bash script to securely update Win64 packer in WSL with comprehensive error handling, automatic backups, and integrity verification.

## Features

- **Secure Downloads**: Uses proper SSL certificate verification (no more `--no-check-certificate`)
- **Input Validation**: Validates version format and sanitizes inputs to prevent injection attacks
- **Automatic Backups**: Creates timestamped backups before updates with rollback capability
- **Integrity Verification**: SHA256 checksum verification for all downloads
- **Retry Logic**: Automatic retry with exponential backoff for network failures
- **Comprehensive Logging**: Detailed logging with timestamps to `/tmp/packer-update.log`
- **Atomic Operations**: Uses temporary directories to prevent partial installations
- **Signal Handling**: Graceful cleanup on interruption (Ctrl+C) with proper terminal color reset
- **Version Management**: Checks current version and skips if already installed
- **API Integration**: Uses HashiCorp releases API for version discovery

## Requirements

The following software must be installed in your WSL environment:

- [WSL](https://learn.microsoft.com/en-us/windows/wsl/install)
- `curl` - for secure downloads
- `unzip` - for extracting Packer archives
- `sha256sum` - for integrity verification

## Usage

    $ ./update-packer-win64.sh <version>
    $ ./update-packer-win64.sh --help

## Examples

    # Install specific version
    $ ./update-packer-win64.sh 1.9.4
    
    # Install beta version
    $ ./update-packer-win64.sh 1.9.4-beta1
    
    # Show current and available versions
    $ ./update-packer-win64.sh

## License

MIT

## Author

These configurations are maintained by F.Tao.
