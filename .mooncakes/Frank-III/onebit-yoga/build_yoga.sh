#!/bin/bash

# Script to download and build Facebook Yoga library
set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
BUILD_DIR="$SCRIPT_DIR/build"
YOGA_DIR="$BUILD_DIR/yoga"
INSTALL_DIR="$SCRIPT_DIR/yoga-install"

echo "Building Facebook Yoga library..."

# Create build directory
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# Clone Yoga if not already present
if [ ! -d "$YOGA_DIR" ]; then
    echo "Cloning Yoga repository..."
    git clone https://github.com/facebook/yoga.git
    cd yoga
else
    echo "Yoga repository already exists, updating..."
    cd yoga
    git pull
fi

# Create build directory
mkdir -p build
cd build

# Configure with CMake
echo "Configuring with CMake..."
cmake .. \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$INSTALL_DIR" \
    -DBUILD_SHARED_LIBS=OFF

# Build
echo "Building..."
make -j$(sysctl -n hw.ncpu)

# Install
echo "Installing to $INSTALL_DIR..."
make install

echo "Yoga build complete!"
echo "Headers: $INSTALL_DIR/include"
echo "Library: $INSTALL_DIR/lib"

# Create a simple pkg-config file
mkdir -p "$INSTALL_DIR/lib/pkgconfig"
cat > "$INSTALL_DIR/lib/pkgconfig/yoga.pc" << EOF
prefix=$INSTALL_DIR
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: Yoga
Description: Facebook Yoga Layout Engine
Version: 1.0.0
Libs: -L\${libdir} -lyogacore
Cflags: -I\${includedir}
EOF

echo "Created pkg-config file at $INSTALL_DIR/lib/pkgconfig/yoga.pc"