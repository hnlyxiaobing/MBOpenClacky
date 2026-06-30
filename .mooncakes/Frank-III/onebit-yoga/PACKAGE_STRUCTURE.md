# OneB-Yoga Package Structure Documentation

## Overview
The onebit-yoga package is a MoonBit wrapper around Facebook's Yoga layout engine (C++ flexbox implementation). It provides a type-safe, handle-based FFI interface to Yoga's layout capabilities.

## Current Status Summary

### ✅ Working Components:
- **FFI Layer**: Successfully connects to real Yoga C++ library
- **Handle System**: Proper memory management with recycling and compaction
- **Build System**: Clean `moon build` with optimized linking
- **Examples**: Main demo runs and shows layout calculations

### ⚠️ Issues:
- **Tests**: FFI tests fail to link (missing library paths in test config)
- **Absolute Paths**: Library paths are hardcoded (not portable)
- **Platform Support**: Currently macOS/arm64 only

## Package Structure

```
onebit-yoga/
├── moon.mod.json           # Module configuration
├── src/
│   ├── types/              # Type definitions
│   │   ├── moon.pkg.json
│   │   └── enums.mbt       # Yoga enum types
│   ├── ffi/                # Foreign Function Interface
│   │   ├── moon.pkg.json
│   │   ├── yoga_ffi.mbt   # FFI type definitions
│   │   ├── yoga_ffi_native.mbt  # Native FFI bindings
│   │   ├── yoga_ffi_test.mbt    # FFI tests
│   │   ├── yoga_wrap.c    # C wrapper (handle conversion)
│   │   └── libyoga_wrap.a # Compiled wrapper library
│   ├── wrapper/            # High-level MoonBit API
│   │   ├── moon.pkg.json
│   │   ├── node.mbt        # Node class wrapper
│   │   ├── node_test.mbt   # Node tests
│   │   └── builder.mbt     # Fluent builder API
│   └── examples/           # Usage examples
│       ├── moon.pkg.json
│       ├── main.mbt        # Main demo
│       └── ffi_test.mbt    # FFI testing
├── yoga-install/           # Compiled Yoga library
│   └── lib/
│       └── libyogacore.a   # Static Yoga library
└── justfile                # Build automation
```

## Module Details

### 1. `types` Package
**Purpose**: Defines all Yoga enum types used throughout the library.

**Files**:
- `enums.mbt`: Contains enums like `Display`, `FlexDirection`, `Justify`, `Align`, `Edge`, `Direction`, etc.

**Status**: ✅ Working - All enum types are properly defined and exported.

### 2. `ffi` Package  
**Purpose**: Low-level Foreign Function Interface to Yoga C++ library.

**Key Components**:
- `yoga_ffi.mbt`: Type definitions (`YogaNodeRef`, `YogaConfigRef`, `Layout` struct)
- `yoga_ffi_native.mbt`: `extern "C"` function declarations with `_wrap` suffix
- `yoga_wrap.c`: C wrapper that converts between MoonBit Int handles and Yoga pointers
- `libyoga_wrap.a`: Compiled static library of the wrapper

**Implementation Details**:
- Uses handle-based system (Int → C pointer conversion)
- Implements memory recycling and automatic compaction
- Fixed critical memory bugs (recursive free, handle leaks)

**Status**: ✅ Working for builds, ❌ Tests fail due to linking issues

**Known Issues**:
- Tests don't link properly (missing library paths)
- Absolute paths in `moon.pkg.json` make it non-portable

### 3. `wrapper` Package
**Purpose**: High-level, idiomatic MoonBit API over the FFI layer.

**Key Components**:
- `node.mbt`: `Node` class with methods like:
  - Style setters (`set_width`, `set_height`, `set_flex_direction`)
  - Tree management (`add_child`, `remove_child`)
  - Layout calculation (`calculate_layout`, `get_layout`)
- `builder.mbt`: Fluent builder API for creating styled nodes
  - Chainable methods: `.width(100).height(50).padding(10)`
  - Helpers: `NodeBuilder::row()`, `NodeBuilder::column()`, `NodeBuilder::center()`

**Status**: ✅ Working - Clean API wraps FFI properly

### 4. `examples` Package
**Purpose**: Demonstrations and testing of the library.

**Files**:
- `main.mbt`: Working examples showing:
  - Simple row layout
  - Flex column layout
  - Nested layouts
  - Builder API usage
- `ffi_test.mbt`: Direct FFI testing (currently unused)

**Status**: ✅ Main examples work and demonstrate layout calculations

**Link Configuration** (in `moon.pkg.json`):
```json
{
  "is-main": true,
  "link": {
    "native": {
      "cc": "clang",
      "cc-link-flags": "./src/ffi/libyoga_wrap.a ./yoga-install/lib/libyogacore.a -lc++"
    }
  }
}
```

## Build System

### Just Commands:
- `just build`: Full build (Yoga + FFI wrapper + MoonBit)
- `just build-yoga`: Build Yoga from source
- `just build-ffi`: Build C wrapper
- `just clean`: Clean all build artifacts
- `just run`: Build and run examples

### Build Process:
1. CMake builds Yoga C++ library → `libyogacore.a`
2. Clang compiles wrapper → `libyoga_wrap.a`
3. Moon links everything with `clang` (not `clang++`)

## Memory Management

### Handle System Features:
- **Handle Table**: Maps Int handles to C pointers
- **Free List**: Recycles freed handle slots
- **Auto Compaction**: Shrinks table when usage < 25%
- **Recursive Cleanup**: Properly frees node trees
- **Bounds Checking**: Validates all handle operations

## What Needs Fixing

### 1. Test Configuration
Tests fail because they don't have proper link flags. Need to either:
- Add link configuration to test packages
- Or move tests to examples package

### 2. Path Portability
Replace absolute paths with relative ones:
- Use `./` relative paths
- Or use environment variables
- Make it work for package distribution

### 3. Cross-Platform Support
Currently macOS/arm64 only. Need:
- Linux support
- Windows support (if possible)
- Multiple architectures

### 4. API Completeness
Missing many Yoga features:
- Gap/spacing properties
- Aspect ratio
- Percentage values for all properties
- Debug/logging functions

