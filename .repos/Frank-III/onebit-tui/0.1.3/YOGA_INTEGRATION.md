# OneBit-TUI Yoga Integration

## Overview

OneBit-TUI uses Yoga (Facebook's flexbox layout engine) for all layout calculations. The integration works through a clean pipeline:

```
Components → Views → Yoga Nodes → Layout → Rendering
```

## Architecture Flow

### 1. Components Render to Views

```moonbit
// Widget implements Component trait
let button = @widget.Button::primary("Click me", action)
let view = button.render()  // Returns a View
```

### 2. Views Have Yoga Properties

```moonbit
pub struct View {
  // Size properties
  mut width : Size?        // Fixed(Double) | Percent(Double) | Auto
  mut height : Size?

  // Flexbox properties
  mut flex_value : Double?
  mut layout_direction : Direction?  // Row | Column
  mut spacing : Double?               // Gap between children

  // Spacing
  mut padding_value : Double?
  mut margin_value : Double?

  // Alignment
  mut align_items_value : @types.Align?
  mut justify_content_value : @types.Justify?

  // Position
  position_type : Position?  // Relative | Absolute
  top_offset : Double?
  left_offset : Double?

  // ... other properties
}
```

### 3. Layout Engine Converts Views to Yoga Nodes

```moonbit
// In layout/layout_engine.mbt
pub fn calculate_layout(
  view : View,
  available_width : Float,
  available_height : Float
) -> @yoga.Node {
  // Creates Yoga nodes from Views
  // Maps View properties to Yoga properties
  // Calculates final layout
}
```

### 4. Yoga Calculates Layout

```moonbit
// The layout engine:
// 1. Creates Yoga nodes matching View tree
// 2. Sets Yoga properties from View properties
// 3. Calls yoga_node.calculate_layout()
// 4. Returns root Yoga node with calculated positions
```

### 5. Rendering Uses Calculated Layout

```moonbit
// In layout_engine.mbt
pub fn render_with_layout(
  app : @core.App,
  view : View,
  yoga_node : @yoga.Node,
  offset_x : Int,
  offset_y : Int
) -> Unit {
  // Uses yoga_node.layout_left(), layout_top()
  // Uses yoga_node.layout_width(), layout_height()
  // Renders view content at calculated position
}
```

## Yoga Properties Supported

### Size & Dimensions

- **Width/Height**: Fixed, Percentage, or Auto
- **Min/Max dimensions**: Via Yoga node methods

### Flexbox

- **Flex**: Grow factor (e.g., `flex: 1.0` takes remaining space)
- **FlexDirection**: Row or Column
- **FlexWrap**: (TODO: Add to View)
- **FlexShrink/FlexBasis**: (TODO: Add to View)

### Alignment

- **AlignItems**: Start, Center, End, Stretch
- **JustifyContent**: Start, Center, End, SpaceBetween, SpaceAround, SpaceEvenly
- **AlignSelf**: Per-item alignment override

### Spacing

- **Padding**: Internal spacing (all sides or per-edge)
- **Margin**: External spacing (all sides or per-edge)
- **Gap/Spacing**: Space between flex children

### Position

- **PositionType**: Relative (default) or Absolute
- **Top/Left/Bottom/Right**: For absolute positioning

## Example Usage

### Simple Row Layout

```moonbit
let row = @view.View::container([button1, button2])
  .direction(@view.Direction::Row)
  .spacing(2.0)  // 2 unit gap between buttons
```

### Sidebar + Main Content

```moonbit
// Sidebar with fixed width
let sidebar = @view.View::container([...])
  .width(25.0)  // Fixed 25 units

// Main content takes remaining space
let main = @view.View::container([...])
  .flex(1.0)  // Takes remaining width

// Root container
let root = @view.View::container([sidebar, main])
  .direction(@view.Direction::Row)
  .width(80.0)
  .height(24.0)
```

### Centered Content

```moonbit
let centered = @view.View::container([content])
  .align_items(@types.Align::Center)
  .justify_content(@types.Justify::Center)
```

## Layout Calculation Example

Given a 80x24 terminal window with sidebar layout:

```
Input:
- Root: Row, 80x24
  - Sidebar: width=25
  - Main: flex=1

Yoga Calculates:
- Root: position=(0,0), size=80x24
- Sidebar: position=(0,0), size=25x24
- Main: position=(25,0), size=55x24
```

## Integration Benefits

1. **Declarative Layout**: Define layout properties on Views
2. **Automatic Calculation**: Yoga handles all the math
3. **Flexbox Power**: Full flexbox model support
4. **Cross-platform**: Same layout algorithm as React Native, CSS Flexbox
5. **Performance**: Yoga is highly optimized C++ code

## Current Status

### ✅ Working

- Basic flexbox layout (row/column)
- Fixed and percentage sizes
- Flex grow
- Padding and margin
- Spacing/gap
- Alignment and justification
- Absolute positioning

### 🔄 TODO

- Flex shrink and basis
- Flex wrap
- Aspect ratio
- Min/max constraints
- Border (for layout calculation)
- ScrollView integration

## Files

- `onebit-yoga/`: Yoga FFI bindings and wrapper
- `layout/layout_engine.mbt`: View → Yoga conversion
- `view/view.mbt`: View type with layout properties
- `demo/yoga_layout_demo.mbt`: Example usage

## Best Practices

1. **Use Flex for Responsive Layout**: Instead of fixed sizes, use `flex: 1.0` for components that should grow
2. **Combine Fixed and Flex**: Mix fixed-width sidebars with flexible main content
3. **Use Spacing for Gaps**: Use the `spacing` property instead of margins on children
4. **Test Different Screen Sizes**: Yoga layouts adapt to container size

## Debugging Layout

To debug layout issues:

1. Check the calculated positions:

```moonbit
let layout = @layout.calculate_layout(view, width, height)
println("Position: (\{layout.layout_left()}, \{layout.layout_top()})")
println("Size: \{layout.layout_width()} x \{layout.layout_height()}")
```

2. Verify View properties are set correctly
3. Ensure parent containers have defined sizes
4. Check flex direction matches intended layout

## Conclusion

OneBit-TUI's Yoga integration provides a powerful, familiar layout system that matches modern UI frameworks. Widgets focus on their content and appearance, while Yoga handles all layout calculations automatically.
