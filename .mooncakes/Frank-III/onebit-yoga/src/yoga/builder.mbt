///| Fluent builder API for Yoga nodes

///|
/// Builder for creating styled Yoga nodes
pub struct NodeBuilder {
  node : Node
}

///|
/// Create a new node builder
pub fn NodeBuilder::new() -> NodeBuilder {
  { node: Node::new() }
}

///|
/// Create from existing node
pub fn NodeBuilder::from_node(node : Node) -> NodeBuilder {
  { node, }
}

///|
/// Build the node
pub fn NodeBuilder::build(self : NodeBuilder) -> Node {
  self.node
}

///|
/// Display property
pub fn NodeBuilder::display(
  self : NodeBuilder,
  display : @types.Display,
) -> NodeBuilder {
  self.node.set_display(display)
  self
}

///|
/// Layout direction
pub fn NodeBuilder::direction(
  self : NodeBuilder,
  direction : @types.FlexDirection,
) -> NodeBuilder {
  self.node.set_flex_direction(direction)
  self
}

///|
/// Justify content
pub fn NodeBuilder::justify(
  self : NodeBuilder,
  justify : @types.Justify,
) -> NodeBuilder {
  self.node.set_justify_content(justify)
  self
}

///|
/// Align items
pub fn NodeBuilder::align_items(
  self : NodeBuilder,
  align : @types.Align,
) -> NodeBuilder {
  self.node.set_align_items(align)
  self
}

///|
/// Align self
pub fn NodeBuilder::align_self(
  self : NodeBuilder,
  align : @types.Align,
) -> NodeBuilder {
  self.node.set_align_self(align)
  self
}

///|
/// Flex wrap
pub fn NodeBuilder::wrap(self : NodeBuilder, wrap : @types.Wrap) -> NodeBuilder {
  self.node.set_flex_wrap(wrap)
  self
}

///|
/// Position type
pub fn NodeBuilder::position(
  self : NodeBuilder,
  position : @types.PositionType,
) -> NodeBuilder {
  self.node.set_position_type(position)
  self
}

///|
/// Width
pub fn NodeBuilder::width(self : NodeBuilder, width : Float) -> NodeBuilder {
  self.node.set_width_points(width)
  self
}

///|
pub fn NodeBuilder::width_percent(
  self : NodeBuilder,
  width : Float,
) -> NodeBuilder {
  self.node.set_width_percent(width)
  self
}

///|
pub fn NodeBuilder::width_auto(self : NodeBuilder) -> NodeBuilder {
  self.node.set_width_auto()
  self
}

///|
/// Height
pub fn NodeBuilder::height(self : NodeBuilder, height : Float) -> NodeBuilder {
  self.node.set_height_points(height)
  self
}

///|
pub fn NodeBuilder::height_percent(
  self : NodeBuilder,
  height : Float,
) -> NodeBuilder {
  self.node.set_height_percent(height)
  self
}

///|
pub fn NodeBuilder::height_auto(self : NodeBuilder) -> NodeBuilder {
  self.node.set_height_auto()
  self
}

///|
/// Flex properties
pub fn NodeBuilder::flex(self : NodeBuilder, flex : Float) -> NodeBuilder {
  self.node.set_flex(flex)
  self
}

///|
pub fn NodeBuilder::flex_grow(self : NodeBuilder, grow : Float) -> NodeBuilder {
  self.node.set_flex_grow(grow)
  self
}

///|
pub fn NodeBuilder::flex_shrink(
  self : NodeBuilder,
  shrink : Float,
) -> NodeBuilder {
  self.node.set_flex_shrink(shrink)
  self
}

///|
pub fn NodeBuilder::flex_basis(
  self : NodeBuilder,
  basis : Float,
) -> NodeBuilder {
  self.node.set_flex_basis(basis)
  self
}

///|
/// Margin
pub fn NodeBuilder::margin(self : NodeBuilder, margin : Float) -> NodeBuilder {
  self.node.set_margin_all(@types.Value::point(margin))
  self
}

///|
pub fn NodeBuilder::margin_top(
  self : NodeBuilder,
  margin : Float,
) -> NodeBuilder {
  self.node.set_margin(@types.Edge::Top, @types.Value::point(margin))
  self
}

///|
pub fn NodeBuilder::margin_bottom(
  self : NodeBuilder,
  margin : Float,
) -> NodeBuilder {
  self.node.set_margin(@types.Edge::Bottom, @types.Value::point(margin))
  self
}

///|
pub fn NodeBuilder::margin_left(
  self : NodeBuilder,
  margin : Float,
) -> NodeBuilder {
  self.node.set_margin(@types.Edge::Left, @types.Value::point(margin))
  self
}

///|
pub fn NodeBuilder::margin_right(
  self : NodeBuilder,
  margin : Float,
) -> NodeBuilder {
  self.node.set_margin(@types.Edge::Right, @types.Value::point(margin))
  self
}

///|
/// Padding
pub fn NodeBuilder::padding(self : NodeBuilder, padding : Float) -> NodeBuilder {
  self.node.set_padding_all(@types.Value::point(padding))
  self
}

///|
pub fn NodeBuilder::padding_top(
  self : NodeBuilder,
  padding : Float,
) -> NodeBuilder {
  self.node.set_padding(@types.Edge::Top, @types.Value::point(padding))
  self
}

///|
pub fn NodeBuilder::padding_bottom(
  self : NodeBuilder,
  padding : Float,
) -> NodeBuilder {
  self.node.set_padding(@types.Edge::Bottom, @types.Value::point(padding))
  self
}

///|
pub fn NodeBuilder::padding_left(
  self : NodeBuilder,
  padding : Float,
) -> NodeBuilder {
  self.node.set_padding(@types.Edge::Left, @types.Value::point(padding))
  self
}

///|
pub fn NodeBuilder::padding_right(
  self : NodeBuilder,
  padding : Float,
) -> NodeBuilder {
  self.node.set_padding(@types.Edge::Right, @types.Value::point(padding))
  self
}

///|
/// Add children
pub fn NodeBuilder::child(self : NodeBuilder, child : Node) -> NodeBuilder {
  self.node.add_child(child)
  self
}

///|
pub fn NodeBuilder::children(
  self : NodeBuilder,
  children : Array[Node],
) -> NodeBuilder {
  for i = 0; i < children.length(); i = i + 1 {
    self.node.add_child(children[i])
  }
  self
}

///|
/// Create common layout helpers
pub fn NodeBuilder::row() -> NodeBuilder {
  NodeBuilder::new()
  .direction(@types.FlexDirection::Row)
  .display(@types.Display::Flex)
}

///|
pub fn NodeBuilder::column() -> NodeBuilder {
  NodeBuilder::new()
  .direction(@types.FlexDirection::Column)
  .display(@types.Display::Flex)
}

///|
pub fn NodeBuilder::center() -> NodeBuilder {
  NodeBuilder::new()
  .justify(@types.Justify::Center)
  .align_items(@types.Align::Center)
  .display(@types.Display::Flex)
}

///|
pub fn NodeBuilder::spacer() -> NodeBuilder {
  NodeBuilder::new().flex_grow(1.0).display(@types.Display::Flex)
}

