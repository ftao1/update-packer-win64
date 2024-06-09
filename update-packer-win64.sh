#!/bin/bash

set -e

# Define color variables
RED="\033[0;31m"
GREEN="\033[0;32m"
NOCOL="\033[0m"

# Define URL templates
BASE_URL="https://releases.hashicorp.com/packer"
URL="${BASE_URL}/$1/packer_$1_windows_amd64.zip"
SHASUMS_URL="${BASE_URL}/$1/packer_$1_SHA256SUMS"
PACKER_ZIP="packer_$1_windows_amd64.zip"
SHASUMS_FILE="packer_$1_SHA256SUMS"
VERSION=$(packer --version)

# Function to print colored messages
print_red() {
    echo -e "${RED}$1${NOCOL}"
}

print_green() {
    echo -e "${GREEN}$1${NOCOL}"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Ensure necessary commands are available
for cmd in wget unzip sha256sum; do
    if ! command_exists "$cmd"; then
        print_red "Error: $cmd is not installed."
        exit 1
    fi
done

# Clear the terminal
clear

# Check for version argument
if [ -z "$1" ]; then
    print_red "No argument supplied."
    echo
    print_green "USAGE: ./update-packer-win64.sh ${RED}<version>${NOCOL}"
    echo
    echo "Please supply the version of packer you wish to download as an argument, e.g., 1.7.9"
    echo
    echo "The latest few versions are here:"
    echo
    curl -s "${BASE_URL}/" | head -n 75 | grep packer | awk -F ">" '{print $2}' | sed 's/<\/a//'
    echo
    echo -e "Your current version is ${GREEN}${VERSION}${NOCOL}"
    exit 0
fi

echo
print_green "==> Downloading version ${PACKER_ZIP}..."
echo

# Download packer and shasums
wget --no-check-certificate "${URL}" -O "${PACKER_ZIP}"
wget --no-check-certificate "${SHASUMS_URL}" -O "${SHASUMS_FILE}"
echo

# Check the SHA256SUM
print_green "==> Checking the SHA256SUM... Look for green OK"
echo
sha256sum -c "${SHASUMS_FILE}" 2>/dev/null | grep "${PACKER_ZIP}: OK"

if [ $? -eq 0 ]; then
    echo
    print_green "==> SHA256SUM checks out OK"
    echo
    print_green "==> Unzipping..."
    echo
    unzip -o "${PACKER_ZIP}"
    echo
    chmod 750 packer.exe
else
    echo
    print_red "THERE IS A PROBLEM WITH THE SHA256SUM - DOES NOT MATCH!"
    print_red "PLEASE CHECK SHA256SUM AND RE-DOWNLOAD. EXITING"
    echo
    exit 1
fi

# Clean up
rm -f "${PACKER_ZIP}" "${SHASUMS_FILE}"

echo
print_green "****** Done ******"
echo "Please validate Packer version with 'packer --version'"


