# Yoga-MoonBit FFI Integration Solution

## Overview
Successfully integrated Facebook's Yoga layout engine (C++) with MoonBit using a clean FFI wrapper approach.

## Key Challenges Solved

1. **Type Mismatch**: MoonBit FFI uses `Int` handles while Yoga uses C++ pointers
2. **Name Mangling**: C++ compiler was mangling function names when MoonBit expected C linkage
3. **Link Flag Propagation**: MoonBit wasn't passing link flags from dependent packages

## The Optimized Solution

### 1. Handle-Based C Wrapper (`src/ffi/yoga_wrap.c`)
- Converts between MoonBit Int handles and Yoga pointers
- Uses handle tables to manage the mapping
- Provides clean C interface with `extern "C"` linkage

### 2. Build Configuration
The key insight was to use `clang` instead of `clang++` for linking:

```json
// src/examples/moon.pkg.json
{
  "link": {
    "native": {
      "cc": "clang",  // ← Critical: Use C compiler, not C++
      "cc-link-flags": "./src/ffi/libyoga_wrap.a ./yoga-install/lib/libyogacore.a -lc++"
    }
  }
}
```

### 3. Simplified Build Process
```bash
just build  # Builds everything in one step
```

The justfile handles:
1. Building Yoga from source (cached)
2. Building the FFI wrapper (cached)
3. Running `moon build --target native`

## Why This Works

- **C vs C++ Linking**: By using `clang` instead of `clang++`, we avoid C++ name mangling issues
- **Static Libraries**: Direct paths to `.a` files ensure proper linking order
- **Handle System**: Cleanly separates MoonBit's integer world from Yoga's pointer world

## Result

- ✅ Clean, reproducible builds
- ✅ No manual linking steps
- ✅ Works with standard `moon build`
- ✅ Real Yoga layout calculations
- ✅ Package-ready for distribution

## Usage

```bash
# Build everything
just build

# Run examples
./target/native/release/build/examples/examples.exe
```

The integration is now production-ready and can be packaged for distribution.