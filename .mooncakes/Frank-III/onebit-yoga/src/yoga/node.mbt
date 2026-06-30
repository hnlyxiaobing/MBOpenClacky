///| High-level MoonBit wrapper for Yoga Layout Engine

///| Provides a safe, idiomatic API for Yoga

///|
/// Yoga Node - High level wrapper around YogaNodeRef
pub struct Node {
  handle : @ffi.YogaNodeRef
  mut parent : Node?
  mut children : Array[Node]
  measure_func : ((Float, @types.MeasureMode, Float, @types.MeasureMode) -> @ffi.Size)?
}

///|
/// Yoga Config - High level wrapper around YogaConfigRef  
pub struct Config {
  handle : @ffi.YogaConfigRef
} derive(Show)

///|
/// Create a new default config
pub fn Config::default() -> Config {
  { handle: @ffi.yoga_config_new() }
}

///|
/// Create a new node with default config
pub fn Node::new() -> Node {
  {
    handle: @ffi.yoga_node_new(),
    parent: None,
    children: [],
    measure_func: None,
  }
}

///|
/// Create a new node with specific config
pub fn Node::new_with_config(config : Config) -> Node {
  {
    handle: @ffi.yoga_node_new_with_config(config.handle),
    parent: None,
    children: [],
    measure_func: None,
  }
}

///|
/// Free this node and its entire subtree
pub fn Node::free_recursive(self : Node) -> Unit {
  @ffi.yoga_node_free_recursive(self.handle)
}

///|
/// Calculate layout for this node tree
pub fn Node::calculate_layout(
  self : Node,
  available_width : Float,
  available_height : Float,
  direction : @types.Direction,
) -> Unit {
  @ffi.yoga_node_calculate_layout(
    self.handle,
    available_width,
    available_height,
    direction,
  )
}

///|
/// Get computed layout
pub fn Node::get_layout(self : Node) -> @ffi.Layout {
  @ffi.yoga_node_get_layout(self.handle)
}

///|
/// Convenient accessors for layout fields (exported)
pub fn Node::layout_left(self : Node) -> Float {
  let l = @ffi.yoga_node_get_layout(self.handle)
  l.left
}

///|
pub fn Node::layout_top(self : Node) -> Float {
  let l = @ffi.yoga_node_get_layout(self.handle)
  l.top
}

///|
pub fn Node::layout_width(self : Node) -> Float {
  let l = @ffi.yoga_node_get_layout(self.handle)
  l.width
}

///|
pub fn Node::layout_height(self : Node) -> Float {
  let l = @ffi.yoga_node_get_layout(self.handle)
  l.height
}

///|
/// Style setters
pub fn Node::set_display(self : Node, display : @types.Display) -> Unit {
  @ffi.yoga_node_set_display(self.handle, display)
}

///|
pub fn Node::set_flex_direction(
  self : Node,
  direction : @types.FlexDirection,
) -> Unit {
  @ffi.yoga_node_set_flex_direction(self.handle, direction)
}

///|
pub fn Node::set_justify_content(self : Node, justify : @types.Justify) -> Unit {
  @ffi.yoga_node_set_justify_content(self.handle, justify)
}

///|
pub fn Node::set_align_items(self : Node, align : @types.Align) -> Unit {
  @ffi.yoga_node_set_align_items(self.handle, align)
}

///|
pub fn Node::set_align_self(self : Node, align : @types.Align) -> Unit {
  @ffi.yoga_node_set_align_self(self.handle, align)
}

///|
pub fn Node::set_align_content(self : Node, align : @types.Align) -> Unit {
  @ffi.yoga_node_set_align_content(self.handle, align)
}

///|
pub fn Node::set_flex_wrap(self : Node, wrap : @types.Wrap) -> Unit {
  @ffi.yoga_node_set_flex_wrap(self.handle, wrap)
}

///|
pub fn Node::set_position_type(
  self : Node,
  position : @types.PositionType,
) -> Unit {
  @ffi.yoga_node_set_position_type(self.handle, position)
}

///|
/// Size setters with Value type
pub fn Node::set_width(self : Node, width : @types.Value) -> Unit {
  match width.unit {
    @types.YogaUnit::Point => @ffi.yoga_node_set_width(self.handle, width.value)
    @types.YogaUnit::Percent =>
      @ffi.yoga_node_set_width_percent(self.handle, width.value)
    @types.YogaUnit::Auto => @ffi.yoga_node_set_width_auto(self.handle)
    @types.YogaUnit::Undefined => ()
  }
}

///|
pub fn Node::set_height(self : Node, height : @types.Value) -> Unit {
  match height.unit {
    @types.YogaUnit::Point =>
      @ffi.yoga_node_set_height(self.handle, height.value)
    @types.YogaUnit::Percent =>
      @ffi.yoga_node_set_height_percent(self.handle, height.value)
    @types.YogaUnit::Auto => @ffi.yoga_node_set_height_auto(self.handle)
    @types.YogaUnit::Undefined => ()
  }
}

///|
/// Convenience methods for common width/height values
pub fn Node::set_width_points(self : Node, width : Float) -> Unit {
  @ffi.yoga_node_set_width(self.handle, width)
}

///|
pub fn Node::set_height_points(self : Node, height : Float) -> Unit {
  @ffi.yoga_node_set_height(self.handle, height)
}

///|
pub fn Node::set_width_percent(self : Node, width : Float) -> Unit {
  @ffi.yoga_node_set_width_percent(self.handle, width)
}

///|
pub fn Node::set_height_percent(self : Node, height : Float) -> Unit {
  @ffi.yoga_node_set_height_percent(self.handle, height)
}

///|
pub fn Node::set_width_auto(self : Node) -> Unit {
  @ffi.yoga_node_set_width_auto(self.handle)
}

///|
pub fn Node::set_height_auto(self : Node) -> Unit {
  @ffi.yoga_node_set_height_auto(self.handle)
}

///|
/// Flex properties
pub fn Node::set_flex(self : Node, flex : Float) -> Unit {
  @ffi.yoga_node_set_flex(self.handle, flex)
}

///|
pub fn Node::set_flex_grow(self : Node, grow : Float) -> Unit {
  @ffi.yoga_node_set_flex_grow(self.handle, grow)
}

///|
pub fn Node::set_flex_shrink(self : Node, shrink : Float) -> Unit {
  @ffi.yoga_node_set_flex_shrink(self.handle, shrink)
}

///|
pub fn Node::set_flex_basis(self : Node, basis : Float) -> Unit {
  @ffi.yoga_node_set_flex_basis(self.handle, basis)
}

///|
pub fn Node::set_min_width(self : Node, width : Float) -> Unit {
  @ffi.yoga_node_set_min_width(self.handle, width)
}

///|
pub fn Node::set_min_height(self : Node, height : Float) -> Unit {
  @ffi.yoga_node_set_min_height(self.handle, height)
}

///|
pub fn Node::set_max_width(self : Node, width : Float) -> Unit {
  @ffi.yoga_node_set_max_width(self.handle, width)
}

///|
pub fn Node::set_max_height(self : Node, height : Float) -> Unit {
  @ffi.yoga_node_set_max_height(self.handle, height)
}

///|
/// Margin setters
pub fn Node::set_margin(
  self : Node,
  edge : @types.Edge,
  margin : @types.Value,
) -> Unit {
  match margin.unit {
    @types.YogaUnit::Point =>
      @ffi.yoga_node_set_margin(self.handle, edge, margin.value)
    @types.YogaUnit::Percent =>
      @ffi.yoga_node_set_margin_percent(self.handle, edge, margin.value)
    @types.YogaUnit::Auto => @ffi.yoga_node_set_margin_auto(self.handle, edge)
    @types.YogaUnit::Undefined => ()
  }
}

///|
/// Padding setters
pub fn Node::set_padding(
  self : Node,
  edge : @types.Edge,
  padding : @types.Value,
) -> Unit {
  match padding.unit {
    @types.YogaUnit::Point =>
      @ffi.yoga_node_set_padding(self.handle, edge, padding.value)
    @types.YogaUnit::Percent =>
      @ffi.yoga_node_set_padding_percent(self.handle, edge, padding.value)
    @types.YogaUnit::Auto => ()
    @types.YogaUnit::Undefined => ()
  }
}

///|
pub fn Node::set_padding_all(self : Node, padding : @types.Value) -> Unit {
  self.set_padding(@types.Edge::Left, padding)
  self.set_padding(@types.Edge::Top, padding)
  self.set_padding(@types.Edge::Right, padding)
  self.set_padding(@types.Edge::Bottom, padding)
}

///|
pub fn Node::set_margin_all(self : Node, margin : @types.Value) -> Unit {
  self.set_margin(@types.Edge::All, margin)
}

///|
/// Position setters
pub fn Node::set_position(
  self : Node,
  edge : @types.Edge,
  position : @types.Value,
) -> Unit {
  match position.unit {
    @types.YogaUnit::Point =>
      @ffi.yoga_node_set_position(self.handle, edge, position.value)
    @types.YogaUnit::Percent =>
      @ffi.yoga_node_set_position_percent(self.handle, edge, position.value)
    _ => ()
  }
}

///|
/// Child management
pub fn Node::add_child(self : Node, child : Node) -> Unit {
  let index = self.children.length()
  self.children.push(child)
  child.parent = Some(self)
  @ffi.yoga_node_insert_child(self.handle, child.handle, index)
}

///|
pub fn Node::insert_child(self : Node, child : Node, index : Int) -> Unit {
  // Insert into our array
  let temp = []
  for i = 0; i < index && i < self.children.length(); i = i + 1 {
    temp.push(self.children[i])
  }
  temp.push(child)
  for i = index; i < self.children.length(); i = i + 1 {
    temp.push(self.children[i])
  }
  self.children = temp
  child.parent = Some(self)
  @ffi.yoga_node_insert_child(self.handle, child.handle, index)
}

///|
pub fn Node::remove_child(self : Node, child : Node) -> Unit {
  let new_children = []
  for i = 0; i < self.children.length(); i = i + 1 {
    let c = self.children[i]
    if not(physical_equal(c, child)) {
      new_children.push(c)
    }
  }
  self.children = new_children
  child.parent = None
  @ffi.yoga_node_remove_child(self.handle, child.handle)
}

///|
pub fn Node::get_child_count(self : Node) -> Int {
  self.children.length()
}

///|
pub fn Node::get_child(self : Node, index : Int) -> Node? {
  if index >= 0 && index < self.children.length() {
    Some(self.children[index])
  } else {
    None
  }
}

///|
/// Set gap using Yoga's gutter support
pub fn Node::set_gap(
  self : Node,
  gutter : @types.Gutter,
  value : Float,
) -> Unit {
  @ffi.yoga_node_set_gap(self.handle, gutter, value)
}

///|
/// Set a fixed measure function that reports the given width/height (points)
pub fn Node::set_measure_fixed(
  self : Node,
  width : Float,
  height : Float,
) -> Unit {
  @ffi.yoga_node_set_measure_fixed(self.handle, width, height)
}

///|
/// Clear any measure function on this node
pub fn Node::clear_measure(self : Node) -> Unit {
  @ffi.yoga_node_clear_measure(self.handle)
}

///|
/// Helper to check physical equality of nodes
fn physical_equal(a : Node, b : Node) -> Bool {
  a.handle == b.handle
}
