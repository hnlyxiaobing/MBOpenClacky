# OnebitYoga Working State

This document describes the current working state of the onebit-yoga MoonBit bindings for Facebook's Yoga layout engine.

## Current Status

✅ **Builds successfully** with `just build`  
✅ **Tests pass** with `just test`  
✅ **Example runs** with `just run`

## Architecture

The project has two FFI implementations:

1. **Mock FFI** (`src/ffi/yoga_ffi.mbt`) - Currently active
   - Pure MoonBit implementation
   - Returns dummy layout values (100x100 for all elements)
   - Allows code to compile and run without Yoga C++ library
   - Used for development and testing the API

2. **Native FFI** (`src/ffi/yoga_ffi_native.mbt`) - Ready but not active
   - Real FFI bindings to Yoga C++ library
   - Would provide actual layout calculations
   - Requires building and linking Yoga C++ library

## Project Structure

```
onebit-yoga/
├── src/
│   ├── types/        # Enums and value types
│   ├── ffi/          # FFI layer (mock and native)
│   ├── yoga/         # High-level API (Node, NodeBuilder)
│   └── examples/     # Example programs
├── justfile          # Build commands
└── moon.mod.json     # MoonBit module config
```

## Usage

```moonbit
// Create a flexbox layout
let root = @yoga.Node::new()
root.set_flex_direction(@types.FlexDirection::Row)
root.set_width_points(300.0)
root.set_height_points(100.0)

// Add children
let child = @yoga.Node::new()
child.set_flex(1.0)
root.add_child(child)

// Calculate layout
root.calculate_layout(300.0, 100.0, @types.Direction::LTR)

// Get results
let layout = root.get_layout()
println("Layout: \{layout}")
```

## Notes

- The mock implementation always returns 100x100 for all layouts
- To use real Yoga calculations, you would need to:
  1. Build Yoga C++ library with `just build-yoga`
  2. Switch from mock to native FFI implementation
  3. Ensure proper C++ linking configuration
