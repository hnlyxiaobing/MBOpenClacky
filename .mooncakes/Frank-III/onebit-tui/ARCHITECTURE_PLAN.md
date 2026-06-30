# OneBit-TUI Architecture Redesign

## Current Problems

1. **Too many files** - Duplicate functionality spread across multiple files
2. **No clear interfaces** - Components don't share common traits
3. **Event handling is scattered** - on_key, on_click mixed everywhere
4. **Huge components folder** - Everything dumped in one place
5. **No clear separation** - Core, components, widgets all mixed

## Proposed Architecture

### Core Package Structure

```
onebit-tui/
├── core/           # Core types only
│   ├── app.mbt     # App initialization
│   ├── color.mbt   # Color type
│   ├── style.mbt   # Style types (borders, alignment, etc)
│   └── moon.pkg.json
│
├── view/           # View system (the foundation)
│   ├── view.mbt    # Base View type
│   ├── render.mbt  # Rendering logic
│   ├── layout.mbt  # Yoga layout integration
│   └── moon.pkg.json
│
├── events/         # Event system
│   ├── types.mbt   # Event types (KeyEvent, MouseEvent, etc)
│   ├── handler.mbt # Event handler trait
│   └── moon.pkg.json
│
├── widgets/        # Basic widgets (implement Component trait)
│   ├── text.mbt    # Text widget
│   ├── button.mbt  # Button widget
│   ├── input.mbt   # Text input
│   ├── list.mbt    # List/Select
│   ├── slider.mbt  # Slider
│   └── moon.pkg.json
│
├── containers/     # Layout containers
│   ├── box.mbt     # Simple box container
│   ├── stack.mbt   # Stack (column/row)
│   ├── grid.mbt    # Grid layout
│   ├── scroll.mbt  # Scrollable container
│   └── moon.pkg.json
│
├── app/            # Application runner
│   ├── runner.mbt  # Main event loop
│   └── moon.pkg.json
│
└── ffi/            # FFI bindings (keep as is)
```

## Core Concepts

### 1. Component Trait

Every widget implements a common trait:

```moonbit
pub trait Component {
  // Render to a View
  render(Self) -> View

  // Handle events (returns true if handled)
  handle_event(Self, Event) -> Bool

  // Get focusable state
  is_focusable(Self) -> Bool
}
```

### 2. Event System

Clean event types with a trait for handlers:

```moonbit
pub enum Event {
  Key(KeyEvent)
  Mouse(MouseEvent)
  Focus(Bool)  // Gained/lost focus
}

pub trait EventHandler {
  handle(Self, Event) -> Bool
}
```

### 3. View as Primitive

View becomes a simple rendering primitive, not a component:

```moonbit
pub struct View {
  // Layout properties (position, size, flex, etc)
  layout : Layout

  // Visual properties (color, border, etc)
  style : Style

  // Content (text, children, or custom render)
  content : ViewContent

  // Optional event handler
  handler : EventHandler?

  // Focus properties
  focusable : Bool
  tab_index : Int?
}
```

### 4. Widgets as Components

Widgets are high-level components with state:

```moonbit
// Button example
pub struct Button {
  label : String
  action : () -> Unit
  style : ButtonStyle
}

pub impl Component for Button with render(self) {
  View::text(self.label)
    .with_style(self.style.to_view_style())
    .set_focusable(true)
    .on_click(fn(_x, _y) { self.action() })
}

pub impl Component for Button with handle_event(self, event) {
  match event {
    Key(KeyEnter) | Key(KeySpace) => {
      self.action()
      true
    }
    _ => false
  }
}

pub impl Component for Button with is_focusable(self) {
  true
}
```

### 5. Composable Containers

Containers manage layout of multiple components:

```moonbit
pub struct Stack {
  direction : Direction  // Horizontal or Vertical
  spacing : Double
  children : Array[Component]
}

pub impl Component for Stack with render(self) {
  View::empty()
    .with_direction(match self.direction {
      Horizontal => Direction::Row
      Vertical => Direction::Column
    })
    .with_spacing(self.spacing)
    .with_children(self.children.map(fn(c) { c.render() }))
}

pub impl Component for Stack with handle_event(self, event) {
  // Delegate to children - TODO: implement child event propagation
  false
}

pub impl Component for Stack with is_focusable(self) {
  false
}
```

## Benefits

1. **Clear separation** - Each package has a single responsibility
2. **Trait-based** - Common interface for all components
3. **Composable** - Build complex UIs from simple parts
4. **Type-safe** - Events and styles are strongly typed
5. **Minimal** - Only essential features, no bloat
6. **MoonBit native** - Uses traits, pattern matching, and functional style

## Migration Plan

### Phase 1: Core Refactor

1. Define Component and EventHandler traits
2. Create clean View type (just rendering)
3. Move event types to events package

### Phase 2: Widget Implementation

1. Implement basic widgets (Text, Button, Input)
2. Each widget in its own file
3. All implement Component trait

### Phase 3: Container System

1. Implement Stack, Grid, Scroll containers
2. Clean layout system with Yoga

### Phase 4: Cleanup

1. Remove old files
2. Update demos to use new API
3. Document the clean architecture

## Example Usage

```moonbit
fn main() {
  let counter = Ref::new(0)

  let app = App::init()
  app.run(fn() {
    Stack::vertical()
      .spacing(2.0)
      .children([
        Text::new("Counter: " + counter.val.to_string()),
        Stack::horizontal()
          .spacing(1.0)
          .children([
            Button::new("-", fn() { counter.val -= 1 }),
            Button::new("Reset", fn() { counter.val = 0 }),
            Button::new("+", fn() { counter.val += 1 })
          ])
      ])
      .render()
  })
}
```

## What Gets Removed

1. **Duplicate event handling** - One system, not three
2. **Complex view builders** - Views are simple
3. **Reactive system** - Already removed, stay simple
4. **Unnecessary helpers** - Use MoonBit built-ins
5. **Scattered component code** - Everything organized

## Key Principles

1. **Simple over clever** - No magic, just functions
2. **Traits over inheritance** - Composition, not hierarchy
3. **Data over behavior** - Components are data with render
4. **Explicit over implicit** - Clear event flow
5. **MoonBit idiomatic** - Use language features properly
