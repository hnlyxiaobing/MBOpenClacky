# OneBit-TUI

A modern terminal user interface library for MoonBit, featuring declarative components, Yoga-powered flexbox layout, and high-performance native rendering.

## Features

- 🎨 **Declarative API** - Build UIs with composable View components
- 📐 **Flexbox Layout** - Powered by Yoga layout engine for responsive designs
- ⚡ **Native Performance** - Leverages Zig-based renderer for optimal performance
- 🖼️ **Rich Borders** - Unicode box-drawing with customizable styles
- 📜 **Overflow Handling** - Built-in scrolling and clipping support
- ⌨️ **Input Handling** - Full keyboard and mouse event support
- 🎯 **Focus Management** - Automatic focus traversal and highlighting

## Quick Start

### Installation

```bash
moon add Frank-III/onebit-tui
```

### Requirements

- MoonBit compiler
- Zig 0.14.x (for building native components)
- C/C++ toolchain

### Project Setup

Add the following to your main package's `moon.pkg.json`:

```json
{
  "link": {
    "native": {
      "cc": "clang",
      "cc-link-flags": [
        "-L.mooncakes/Frank-III/onebit-tui/src/ffi/lib",
        "-lopentui",
        "-L.mooncakes/Frank-III/onebit-yoga/src/ffi",
        "-lyoga_wrap",
        "-L.mooncakes/Frank-III/onebit-yoga/src/ffi/yoga-install/lib",
        "-lyogacore",
        "-lc++"
      ]
    }
  }
}
```

Notes:
- Link flags are required due to current MoonBit limitations (deps don’t propagate linker args yet).
- Paths point to installed package contents under `.mooncakes/…` where OneBit‑TUI’s pre-build places `libopentui.a` and OneBit‑Yoga exposes `libyoga_wrap.a` + `libyogacore.a`.
- For mono-repo/local dev, you can instead use relative paths to sibling folders, but the above works for consumers after `moon add`.

### Consumer Integration

Add the imports and link flags to your app’s root `moon.pkg.json`:

```json
{
  "import": [
    "Frank-III/onebit-tui/widget",
    "Frank-III/onebit-tui/view",
    "Frank-III/onebit-tui/core",
    "Frank-III/onebit-tui/layout",
    "Frank-III/onebit-tui/runtime",
    { "path": "Frank-III/onebit-yoga/yoga", "alias": "yoga" },
    { "path": "Frank-III/onebit-yoga/types", "alias": "types" }
  ],
  "is-main": true,
  "link": {
    "native": {
      "cc": "clang",
      "cc-link-flags": [
        "-L.mooncakes/Frank-III/onebit-tui/src/ffi/lib",
        "-lopentui",
        "-L.mooncakes/Frank-III/onebit-yoga/src/ffi",
        "-lyoga_wrap",
        "-L.mooncakes/Frank-III/onebit-yoga/src/ffi/yoga-install/lib",
        "-lyogacore",
        "-lc++"
      ]
    }
  }
}
```

### Hello World Example

```moonbit
///| Simple counter app
fn main {
  let app = @core.App::init()
  match app {
    None => println("Failed to initialize")
    Some(app) => {
      let counter = Ref::new(0)

      fn build_ui() -> @view.View {
        @view.View::container_views([
          @view.View::text("Count: \{counter.val}", color=@core.Color::White),
          @view.View::text("Press +/- to change", color=@core.Color::Gray)
        ])
        .direction(@view.Direction::Column)
        .padding(2.0)
        .border(@view.BorderStyle::Single, color=@core.Color::Cyan)
        .title("Counter")
        .title_align(@view.TitleAlign::Center)
      }

      // Global handler returns false by default; return true to prevent default
      @runtime.run_event_loop(app, build_ui, fn(event) {
        match event {
          @ffi.InputEvent::Key(@ffi.KeyEvent::Char(43)) => { // '+'
            counter.val = counter.val + 1
            true
          }
          @ffi.InputEvent::Key(@ffi.KeyEvent::Char(45)) => { // '-'
            counter.val = counter.val - 1
            true
          }
          _ => false
        }
      }, enable_kitty_keyboard=false)

      app.cleanup()
    }
  }
}
```

## Core Concepts

### Views

Views are the building blocks of OneBit-TUI applications:

```moonbit
// Text view
@view.View::text("Hello, World!", color=@core.Color::Green)

// Container with children
@view.View::container_views([
  child1,
  child2,
])
.direction(@view.Direction::Row)
.spacing(1.0)
```

### Layout (Yoga Flexbox)

OneBit-TUI uses Yoga for powerful flexbox layout:

```moonbit
view
  .width(50.0)                    // Fixed width
  .height_percent(50.0)           // 50% of parent height
  .flex(1.0)                      // Flex grow
  .padding(2.0)                   // Padding on all sides
  .margin_symmetric(1.0, 2.0)    // Vertical, horizontal margins
  .align_items(@types.Align::Center)
  .justify_content(@types.Justify::SpaceBetween)
```

### Styling

```moonbit
view
  .border(@view.BorderStyle::Double, color=@core.Color::Cyan)
  .title("My Box")
  .title_align(@view.TitleAlign::Center)
  .background(@core.rgb(20, 20, 40))
  .foreground(@core.Color::White)
  .focused_border_color(@core.Color::Yellow)
```

## Built-in Widgets

### List Widget

```moonbit
let items = ["Item 1", "Item 2", "Item 3"]
let selected = Ref::new(0)
let list = @widget.List::new(items, selected)
  .item_renderer(fn(item, index, is_selected) {
    let prefix = if is_selected { "> " } else { "  " }
    prefix + item
  })
```

### Text Input

```moonbit
let text_value = Ref::new("")
let input = @widget.TextInput::new(text_value)
  .placeholder("Enter text...")
  .width(30.0)
```

### Button

```moonbit
let button = @widget.Button::new("Click Me", fn() {
  println("Button clicked!")
})
```

### Progress Bar

```moonbit
let progress = @widget.ProgressBar::new(0.5, style=@widget.ProgressStyle::blocks())
  .width(40.0)
```

### ScrollBox

```moonbit
let items = generate_many_items()
let scroll = @widget.ScrollBox::new(items, visible_rows=10)
  .border(@view.BorderStyle::Single)
  .title("Scrollable List")
```

## Event Handling

```moonbit
// Global event handler (return true to prevent default; false by default)
fn on_global_event(event : @ffi.InputEvent) -> Bool {
  match event {
    Key(Escape) => false  // Exit app
    MouseDown(x, y, button) => {
      println("Click at \{x}, \{y}")
      false
    }
    Resize(width, height) => {
      println("Terminal resized to \{width}x\{height}")
      false
    }
    _ => false
  }
}

// Component-level handlers
view.on_key(fn(key) {
  match key {
    Enter => { do_something(); true }
    _ => false
  }
})
.on_click(fn(x, y) {
  println("Clicked at \{x}, \{y}")
})
```

## Focus Management

The focus system automatically handles Tab navigation:

```moonbit
view
  .focusable()  // Make focusable
  .focused_border_color(@core.Color::Yellow)  // Highlight when focused
```

## Examples

Dev examples live under `examples/tui-demo/` in this repo:

- `tab_select_demo.mbt` — Horizontal tab selector
- `select_demo.mbt` — Dropdown selection
- `text_area_demo.mbt` — Wrapped multi-line text with scrolling
- `scrollbox_demo.mbt` — Scrollable list of components
- `input_demo.mbt` — Text input with caret + word navigation

Run any demo:

```bash
cd examples/tui-demo
moon run --target native src/scrollbox_demo.mbt   # or any of the above
```

Tips:

- Tab/Shift+Tab moves focus, arrows navigate, Home/End/PageUp/PageDown supported.
- Mouse wheel scroll works on focused ScrollBox/TextArea.
- TextInput supports Ctrl/Alt+Left/Right (word nav), Ctrl+W/U/K, and paste; caret is visible when focused.
 - Optional: enable kitty keyboard for richer modifier fidelity via `enable_kitty_keyboard=true` in `run_event_loop`.

## Architecture

OneBit-TUI has a layered architecture:

```
┌──────────────────────────────────┐
│         Application Code          │
├──────────────────────────────────┤
│      Widgets (List, Input...)     │
├──────────────────────────────────┤
│    View System + Event Loop       │
├──────────────────────────────────┤
│      Yoga Layout Engine           │
├──────────────────────────────────┤
│    FFI Layer (Terminal I/O)       │
├──────────────────────────────────┤
│   Native Zig/C Renderer           │
└──────────────────────────────────┘
```

## Platform Support

- ✅ **macOS** (x64, ARM64) - Fully supported
- ✅ **Linux** (x64, ARM64) - Fully supported
- 🚧 **Windows** - Experimental (requires WSL for now)

## Building from Source

```bash
# Clone the repository
git clone https://github.com/Frank-III/opentui
cd opentui/onebit-tui

# Install dependencies
moon install

# Build the project
moon build --target native

# Run demos
moon run demo/main
```

Distribution details:
- OneBit‑TUI vendors OpenTUI’s Zig sources under `src/ffi/vendor/opentui` and compiles a static library during `pre-build` to `src/ffi/lib/libopentui.a`.
- OneBit‑Yoga vendors Yoga, builds `yoga-install/lib/libyogacore.a`, and provides `src/ffi/libyoga_wrap.a`.
- No network is required at build-time for consumers if vendor sources are included in the published package; ensure Zig 0.14.x is available.

## Dependencies

- **[onebit-yoga](https://github.com/Frank-III/opentui/tree/main/onebit-yoga)** - Yoga layout engine bindings
- **Native renderer** - Bundled Zig/C renderer (built automatically)

## Current Limitations

- Windows support is experimental
- No support for background tasks/timers (coming soon)
- Limited to terminal capabilities (no images, etc.)

## Troubleshooting

### Build Warnings

You may see ~100 FFI annotation warnings during compilation. These are non-critical and will be addressed in future releases:

```
Warning: FFI parameter of pointer type should be annotated with either `#borrow` or `#owned`
```

These warnings don't affect functionality and can be safely ignored.

### Link Errors

If you encounter link errors, ensure:

1. The link flags are properly set in your `moon.pkg.json` (see Project Setup)
2. Zig 0.14.x is installed (0.15.x has incompatible std.Build APIs with current vendor)
3. OneBit‑TUI’s `libopentui.a` exists at `.mooncakes/Frank-III/onebit-tui/src/ffi/lib/`
4. OneBit‑Yoga’s `libyoga_wrap.a` and `yoga-install/lib/libyogacore.a` exist under `.mooncakes/Frank-III/onebit-yoga/src/ffi/`

### Zig Version

OneBit-TUI requires Zig 0.14.x. Install it using:

```bash
# Using zigup
zigup 0.14.1

# Or using anyzig
anyzig install 0.14.1
```

## Contributing

Contributions are welcome! Please feel free to submit issues and pull requests.

Areas where help is appreciated:

- Windows platform support
- Additional widgets
- Performance optimizations
- Documentation improvements

## Feedback & Support

- **Issues**: [GitHub Issues](https://github.com/Frank-III/opentui/issues)
- **Discussions**: [GitHub Discussions](https://github.com/Frank-III/opentui/discussions)
- **Package**: [mooncakes.io/Frank-III/onebit-tui](https://mooncakes.io/docs/Frank-III/onebit-tui)

## License

Apache-2.0 License - see LICENSE file for details

## Acknowledgments

OneBit-TUI is a MoonBit port of [OpenTUI](https://github.com/stonega/opentui), leveraging its high-performance Zig renderer while providing an idiomatic MoonBit API.

Special thanks to:

- The Yoga Layout team for the flexbox engine
- The OpenTUI team for the renderer foundation
- The MoonBit team for the language and tooling
