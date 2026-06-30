# MoonBit Yoga Layout Bindings

MoonBit bindings for Facebook's Yoga layout engine.

## Prerequisites

- MoonBit toolchain (`moon`)
- C/C++ compiler (clang recommended)
- CMake (for building Yoga during pre-build)

## Install (as a dependency)

```bash
moon add Frank-III/onebit-yoga
```

Then in your package’s `moon.pkg.json`:

```json
{
  "import": [
    { "path": "Frank-III/onebit-yoga/yoga", "alias": "yoga" },
    { "path": "Frank-III/onebit-yoga/types", "alias": "types" }
  ],
  "link": {
    "native": {
      "cc": "clang",
      "cc-link-flags": "-L.mooncakes/Frank-III/onebit-yoga/src/ffi -lyoga_wrap -L.mooncakes/Frank-III/onebit-yoga/src/ffi/yoga-install/lib -lyogacore -lc++"
    }
  }
}
```

Notes:
- MoonBit does not currently propagate link flags from dependencies; apps must add the `link.native` section above.
- The pre-build step compiles Yoga automatically; no separate setup is required.

## Usage

```moonbit
// Build a simple layout
let root = @yoga.Node::new()
root.set_flex_direction(@types.FlexDirection::Row)
root.set_width_points(300.0)
root.set_height_points(100.0)

let child = @yoga.Node::new()
child.set_flex_grow(1.0)
root.add_child(child)

root.calculate_layout(300.0, 100.0, @types.Direction::LTR)
let l = root.get_layout()
println("left=\{l.left}, top=\{l.top}, w=\{l.width}, h=\{l.height}")
```

## Project Structure

```
onebit-yoga/
├── moon.mod.json          # Module config
├── src/
│   ├── ffi/               # FFI (pre-build compiles Yoga + wrapper lib)
│   │   ├── scripts/       # build_yoga.sh (pre-build)
│   │   └── vendor/yoga    # Trimmed CMake + C++ sources (published)
│   ├── types/             # Enums and value types
│   ├── yoga/              # Public API (Node, NodeBuilder, re-exported enums)
│   └── examples/          # Examples (optional)
└── scripts/               # Vendor management (prepare_vendor_yoga.sh, etc.)
```

## Maintainers

- Prepare minimal vendor before publishing:

```bash
bash scripts/prepare_vendor_yoga.sh
```

- Build and publish:

```bash
moon clean
moon build --target native
moon package --list
moon publish
```

## License

MIT — see LICENSE.
