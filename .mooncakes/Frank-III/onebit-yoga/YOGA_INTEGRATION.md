# Yoga FFI Integration Guide

This guide explains how to integrate the real Facebook Yoga library with OneBit-Yoga.

## Current Status

OneBit-Yoga currently uses a **stub implementation** that allows the code to compile and run without the real Yoga library. This is useful for testing the FFI integration.

## How to Use Real Yoga Library

### Option 1: Build from Source

1. Run the provided build script:

```bash
cd onebit-yoga
chmod +x build_yoga.sh
./build_yoga.sh
```

This will:

- Clone Yoga from GitHub
- Build it with CMake
- Install to `onebit-yoga/yoga-install/`

2. Update `src/ffi/moon.pkg.json`:

```json
{
  "link": {
    "native": {
      "cc": "clang",
      "cc-flags": "-DHAS_YOGA_HEADERS -I../../yoga-install/include",
      "cc-link-flags": "-L../../yoga-install/lib -lyogacore"
    }
  }
}
```

### Option 2: Use System Package Manager

#### macOS (Homebrew)

```bash
brew install yoga

# Then update moon.pkg.json:
{
  "cc-flags": "-DHAS_YOGA_HEADERS -I/opt/homebrew/include",
  "cc-link-flags": "-L/opt/homebrew/lib -lyoga"
}
```

#### Ubuntu/Debian

```bash
sudo apt-get install libyoga-dev

# Then update moon.pkg.json:
{
  "cc-flags": "-DHAS_YOGA_HEADERS -I/usr/include",
  "cc-link-flags": "-L/usr/lib -lyoga"
}
```

### Option 3: Use Prebuilt Binaries

Download prebuilt Yoga binaries from the releases page:
https://github.com/facebook/yoga/releases

Extract and update paths in `moon.pkg.json` accordingly.

## How the Integration Works

1. **With Stub (default)**:
   - `yoga_wrap.c` provides mock implementations
   - No external dependencies needed
   - Good for testing MoonBit FFI code
   - Returns dummy values

2. **With Real Yoga**:
   - Compile with `-DHAS_YOGA_HEADERS` flag
   - `yoga_wrap.c` only includes headers
   - Link with actual Yoga library
   - Full layout calculations work

## Testing

```bash
# Test with stub implementation
moon test --target native src/ffi/test_yoga_ffi.mbt

# Build with real Yoga (after updating moon.pkg.json)
moon build --target native
moon test --target native src/ffi/test_yoga_ffi.mbt
```

## Troubleshooting

### "yoga/Yoga.h not found"

- You're missing the `-DHAS_YOGA_HEADERS` flag
- Or the include path is incorrect

### Linking errors

- Check that `-lyogacore` or `-lyoga` is correct
- Verify the library path with `-L`
- Some systems use `libyogacore.a`, others use `libyoga.a`

### Different behavior between stub and real

- This is expected! The stub returns fixed values
- Real Yoga performs actual layout calculations

## Platform Notes

- **macOS**: May need to set `DYLD_LIBRARY_PATH` for dynamic libs
- **Linux**: May need to set `LD_LIBRARY_PATH` or use rpath
- **Windows**: Not tested, may need additional configuration
