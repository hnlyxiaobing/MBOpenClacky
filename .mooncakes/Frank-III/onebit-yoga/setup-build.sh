#!/bin/bash
# Setup script that creates symlinks in expected locations

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
YOGA_INSTALL="${SCRIPT_DIR}/yoga-install"

# Ensure yoga is built
if [ ! -f "${YOGA_INSTALL}/lib/libyogacore.a" ]; then
    echo "Yoga library not found. Building..."
    "${SCRIPT_DIR}/build_yoga.sh"
fi

# Create build directories
mkdir -p "${SCRIPT_DIR}/target/native/release/build/ffi"

# Create symlinks in the build directory that will resolve the relative paths
cd "${SCRIPT_DIR}/target/native/release/build/ffi"

# Remove existing symlinks if they exist
rm -f yoga-install

# Create symlink back to the yoga-install directory
# The relative path ../../yoga-install from moon.pkg.json will now work
ln -s "${YOGA_INSTALL}" "${SCRIPT_DIR}/target/native/release/build/yoga-install"

echo "Build environment set up successfully"