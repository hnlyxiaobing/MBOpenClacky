#!/bin/bash
# Moon wrapper script that sets up environment variables for FFI

set -euo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
YOGA_ROOT="${SCRIPT_DIR}/yoga-install"

# Export environment variables for the build
export YOGA_INCLUDE="${YOGA_ROOT}/include"
export YOGA_LIB="${YOGA_ROOT}/lib"

# Replace template variables in cc-flags and cc-link-flags
export CC_FLAGS="-DHAS_YOGA_HEADERS -I${YOGA_INCLUDE} -std=c++20"
export CC_LINK_FLAGS="-L${YOGA_LIB} -lyogacore -lc++"

# Call moon with all arguments passed through
exec moon "$@"