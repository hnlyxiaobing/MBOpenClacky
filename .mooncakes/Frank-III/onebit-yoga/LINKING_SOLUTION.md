# MoonBit FFI Linking Solution

## Problem
MoonBit does not automatically propagate link flags from dependencies to packages that use them. This means when a package uses FFI functions from another package, it needs its own link configuration to resolve the symbols during compilation and testing.

## Solution
Each package that directly or indirectly uses FFI functions must include the link configuration in its `moon.pkg.json` file.

## Implementation

### 1. FFI Package Configuration
The package that declares the `extern "C"` functions needs link configuration:

```json
// src/ffi/moon.pkg.json
{
  "import": ["moonbit-community/onebit-yoga/types"],
  "warn-list": "-1-3-4-6-9-19-35",
  "link": {
    "native": {
      "cc": "clang",
      "cc-link-flags": "-Lsrc/ffi -lyoga_wrap -Lyoga-install/lib -lyogacore -lc++"
    }
  }
}
```

### 2. Dependent Package Configuration
Any package that uses the FFI functions (even indirectly) also needs the same link configuration:

```json
// src/yoga/moon.pkg.json
{
  "import": ["Frank-III/onebit-yoga/types", "Frank-III/onebit-yoga/ffi"],
  "link": false
}
```

### 3. Main Package Configuration
Main packages (with `"is-main": true`) also need the link configuration:

```json
// src/examples/moon.pkg.json
{
  "import": [
    { "path": "Frank-III/onebit-yoga/yoga", "alias": "yoga" },
    { "path": "Frank-III/onebit-yoga/types", "alias": "types" }
  ],
  "is-main": true,
  "link": {
    "native": {
      "cc": "clang",
      "cc-link-flags": "-Lsrc/ffi -lyoga_wrap -Lsrc/ffi/yoga-install/lib -lyogacore -lc++"
    }
  }
}
```

## Key Points

### Link Flag Format
Use the standard C compiler flag format:
- `-L<path>`: Add library search path
- `-l<name>`: Link library (without lib prefix or file extension)
- `-lc++`: Link C++ standard library (required for C++ libraries)

### Paths
- Paths are relative to the project root (where `moon.mod.json` is located)
- Use forward slashes even on Windows for portability

### Compiler Selection
- Use `"cc": "clang"` to specify the C compiler
- This ensures consistent behavior across platforms

## Testing

With proper link configuration in all relevant packages:
- `moon build --target native` - Builds successfully
- `moon test --target native` - All tests pass
- `moon run --target native src/examples/main.mbt` - Runs examples

## Common Issues and Solutions

### Issue: Undefined symbols during test
**Cause**: Package uses FFI functions but lacks link configuration
**Solution**: Add the same `link` configuration to that package's `moon.pkg.json`

### Issue: "no such file or directory" for libraries
**Cause**: Paths are incorrect or relative to wrong directory
**Solution**: Ensure paths are relative to project root

### Issue: Different compilers for different packages
**Cause**: Inconsistent `cc` specification
**Solution**: Use the same compiler (e.g., `clang`) in all packages

## Future Improvements

Ideally, MoonBit would:
1. Automatically propagate link flags from dependencies
2. Support centralized link configuration in the FFI package only
3. Provide better error messages for missing link configurations

Until then, this duplication approach ensures reliable builds and tests.
