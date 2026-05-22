#!/bin/bash

# Build script for OneBit TUI FFI bridge
# This links with the actual OpenTUI Zig library

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SRC_DIR="$SCRIPT_DIR/src/ffi"
BUILD_DIR="$SCRIPT_DIR/build"
LIB_DIR="$SCRIPT_DIR/lib"
ZIG_LIB="/Users/frankmac/projects/learn_ts/opentui/node_modules/@opentui/core-darwin-arm64/libopentui.dylib"

echo "Building OneBit TUI FFI bridge..."

# Create build directories
mkdir -p "$BUILD_DIR"
mkdir -p "$LIB_DIR"

# Check if the Zig library exists
if [ ! -f "$ZIG_LIB" ]; then
    echo "Error: Zig library not found at $ZIG_LIB"
    echo "Please build OpenTUI first"
    exit 1
fi

# Compile the C wrapper
echo "Compiling C wrapper..."
clang -c -fPIC -O2 -Wall -I. "$SRC_DIR/opentui_wrap.c" -o "$BUILD_DIR/opentui_wrap.o"

if [ $? -ne 0 ]; then
    echo "Failed to compile C wrapper"
    exit 1
fi

# Create a shared library that links with the Zig library
echo "Creating shared library..."
clang -shared -o "$LIB_DIR/libopentui_ffi.dylib" "$BUILD_DIR/opentui_wrap.o" "$ZIG_LIB" \
    -Wl,-rpath,"$(dirname "$ZIG_LIB")"

if [ $? -ne 0 ]; then
    echo "Failed to create shared library"
    exit 1
fi

# Also create a static library (just the wrapper, Zig lib will be linked separately)
echo "Creating static library..."
ar rcs "$LIB_DIR/libopentui_ffi.a" "$BUILD_DIR/opentui_wrap.o"

# Copy the Zig library to our lib directory for easier linking
cp "$ZIG_LIB" "$LIB_DIR/libopentui.dylib"

echo "FFI bridge built successfully!"
echo "Libraries created:"
echo "  - $LIB_DIR/libopentui_ffi.dylib (shared library with embedded Zig lib)"
echo "  - $LIB_DIR/libopentui_ffi.a (static wrapper library)"
echo "  - $LIB_DIR/libopentui.dylib (copied OpenTUI library)"
echo ""
echo "To use with MoonBit, update src/ffi/moon.pkg.json with:"
echo "  \"cc-link-flags\": \"-L$LIB_DIR -lopentui_ffi\""