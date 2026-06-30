///| FFI bindings for Yoga Layout Engine

///| These are the low-level bindings to the C API

///|
/// Opaque handle to a Yoga node
pub(all) struct YogaNodeRef(Int) derive(Show, Eq)

///|
/// Opaque handle to a Yoga config
pub(all) struct YogaConfigRef(Int) derive(Show, Eq)

///|
/// Size structure for measurements
pub struct Size {
  width : Float
  height : Float
} derive(Eq, Show)

///|
/// Layout information computed by Yoga
pub struct Layout {
  left : Float
  top : Float
  width : Float
  height : Float
} derive(Eq, Show)

///|
/// Measure function type
pub struct MeasureFunc(
  (Float, @types.MeasureMode, Float, @types.MeasureMode) -> Size
) derive(Show)

///|
/// Create a new Yoga config
pub fn yoga_config_new() -> YogaConfigRef {
  yoga_config_new_native()
}

///|
/// Free a Yoga config
pub fn yoga_config_free(config : YogaConfigRef) -> Unit {
  yoga_config_free_native(config)
}

///|
/// Create a new Yoga node
pub fn yoga_node_new() -> YogaNodeRef {
  yoga_node_new_native()
}

///|
/// Create a new Yoga node with config
pub fn yoga_node_new_with_config(config : YogaConfigRef) -> YogaNodeRef {
  yoga_node_new_with_config_native(config)
}

///|
/// Free a Yoga node
pub fn yoga_node_free(node : YogaNodeRef) -> Unit {
  yoga_node_free_native(node)
}

///|
/// Free a Yoga node and all descendants (recursive)
pub fn yoga_node_free_recursive(node : YogaNodeRef) -> Unit {
  yoga_node_free_recursive_native(node)
}

///|
/// Calculate layout
pub fn yoga_node_calculate_layout(
  node : YogaNodeRef,
  available_width : Float,
  available_height : Float,
  direction : @types.Direction,
) -> Unit {
  yoga_node_calculate_layout_native(
    node, available_width, available_height, direction,
  )
}

///|
/// Get computed layout
pub fn yoga_node_get_layout(node : YogaNodeRef) -> Layout {
  yoga_node_get_layout_native(node)
}

///|
/// Set style properties
pub fn yoga_node_set_display(
  node : YogaNodeRef,
  display : @types.Display,
) -> Unit {
  yoga_node_set_display_native(node, display)
}

///|
pub fn yoga_node_set_flex_direction(
  node : YogaNodeRef,
  direction : @types.FlexDirection,
) -> Unit {
  yoga_node_set_flex_direction_native(node, direction)
}

///|
pub fn yoga_node_set_justify_content(
  node : YogaNodeRef,
  justify : @types.Justify,
) -> Unit {
  yoga_node_set_justify_content_native(node, justify)
}

///|
pub fn yoga_node_set_align_items(
  node : YogaNodeRef,
  align : @types.Align,
) -> Unit {
  yoga_node_set_align_items_native(node, align)
}

///|
pub fn yoga_node_set_align_self(
  node : YogaNodeRef,
  align : @types.Align,
) -> Unit {
  yoga_node_set_align_self_native(node, align)
}

///|
pub fn yoga_node_set_align_content(
  node : YogaNodeRef,
  align : @types.Align,
) -> Unit {
  yoga_node_set_align_content_native(node, align)
}

///|
pub fn yoga_node_set_flex_wrap(node : YogaNodeRef, wrap : @types.Wrap) -> Unit {
  yoga_node_set_flex_wrap_native(node, wrap)
}

///|
pub fn yoga_node_set_position_type(
  node : YogaNodeRef,
  position : @types.PositionType,
) -> Unit {
  yoga_node_set_position_type_native(node, position)
}

///|
/// Set dimensions
pub fn yoga_node_set_width(node : YogaNodeRef, width : Float) -> Unit {
  yoga_node_set_width_native(node, width)
}

///|
pub fn yoga_node_set_height(node : YogaNodeRef, height : Float) -> Unit {
  yoga_node_set_height_native(node, height)
}

///|
pub fn yoga_node_set_width_percent(node : YogaNodeRef, width : Float) -> Unit {
  yoga_node_set_width_percent_native(node, width)
}

///|
pub fn yoga_node_set_height_percent(node : YogaNodeRef, height : Float) -> Unit {
  yoga_node_set_height_percent_native(node, height)
}

///|
pub fn yoga_node_set_width_auto(node : YogaNodeRef) -> Unit {
  yoga_node_set_width_auto_native(node)
}

///|
pub fn yoga_node_set_height_auto(node : YogaNodeRef) -> Unit {
  yoga_node_set_height_auto_native(node)
}

///|
/// Set flex properties
pub fn yoga_node_set_flex(node : YogaNodeRef, flex : Float) -> Unit {
  yoga_node_set_flex_native(node, flex)
}

///|
pub fn yoga_node_set_flex_grow(node : YogaNodeRef, grow : Float) -> Unit {
  yoga_node_set_flex_grow_native(node, grow)
}

///|
pub fn yoga_node_set_flex_shrink(node : YogaNodeRef, shrink : Float) -> Unit {
  yoga_node_set_flex_shrink_native(node, shrink)
}

///|
pub fn yoga_node_set_flex_basis(node : YogaNodeRef, basis : Float) -> Unit {
  yoga_node_set_flex_basis_native(node, basis)
}

///|
/// Set min/max dimensions
pub fn yoga_node_set_min_width(node : YogaNodeRef, width : Float) -> Unit {
  yoga_node_set_min_width_native(node, width)
}

///|
pub fn yoga_node_set_min_height(node : YogaNodeRef, height : Float) -> Unit {
  yoga_node_set_min_height_native(node, height)
}

///|
pub fn yoga_node_set_max_width(node : YogaNodeRef, width : Float) -> Unit {
  yoga_node_set_max_width_native(node, width)
}

///|
pub fn yoga_node_set_max_height(node : YogaNodeRef, height : Float) -> Unit {
  yoga_node_set_max_height_native(node, height)
}

///|
/// Set margin
pub fn yoga_node_set_margin(
  node : YogaNodeRef,
  edge : @types.Edge,
  margin : Float,
) -> Unit {
  yoga_node_set_margin_native(node, edge, margin)
}

///|
pub fn yoga_node_set_margin_percent(
  node : YogaNodeRef,
  edge : @types.Edge,
  margin : Float,
) -> Unit {
  yoga_node_set_margin_percent_native(node, edge, margin)
}

///|
pub fn yoga_node_set_margin_auto(
  node : YogaNodeRef,
  edge : @types.Edge,
) -> Unit {
  yoga_node_set_margin_auto_native(node, edge)
}

///|
/// Set padding
pub fn yoga_node_set_padding(
  node : YogaNodeRef,
  edge : @types.Edge,
  padding : Float,
) -> Unit {
  yoga_node_set_padding_native(node, edge, padding)
}

///|
pub fn yoga_node_set_padding_percent(
  node : YogaNodeRef,
  edge : @types.Edge,
  padding : Float,
) -> Unit {
  yoga_node_set_padding_percent_native(node, edge, padding)
}

///|
/// Set position
pub fn yoga_node_set_position(
  node : YogaNodeRef,
  edge : @types.Edge,
  position : Float,
) -> Unit {
  yoga_node_set_position_native(node, edge, position)
}

///|
pub fn yoga_node_set_position_percent(
  node : YogaNodeRef,
  edge : @types.Edge,
  position : Float,
) -> Unit {
  yoga_node_set_position_percent_native(node, edge, position)
}

///|
/// Set gap between items
pub fn yoga_node_set_gap(
  node : YogaNodeRef,
  gutter : @types.Gutter,
  gap : Float,
) -> Unit {
  yoga_node_set_gap_native(node, gutter, gap)
}

///|
/// Node tree operations
pub fn yoga_node_insert_child(
  parent : YogaNodeRef,
  child : YogaNodeRef,
  index : Int,
) -> Unit {
  yoga_node_insert_child_native(parent, child, index)
}

///|
pub fn yoga_node_remove_child(
  parent : YogaNodeRef,
  child : YogaNodeRef,
) -> Unit {
  yoga_node_remove_child_native(parent, child)
}

///|
pub fn yoga_node_get_child_count(parent : YogaNodeRef) -> Int {
  yoga_node_get_child_count_native(parent)
}

///|
pub fn yoga_node_get_child(parent : YogaNodeRef, index : Int) -> YogaNodeRef? {
  yoga_node_get_child_native(parent, index)
}

///|
/// Set a fixed measure function for this node (width/height in points)
pub fn yoga_node_set_measure_fixed(
  node : YogaNodeRef,
  width : Float,
  height : Float,
) -> Unit {
  yoga_node_set_measure_fixed_native(node, width, height)
}

///|
/// Clear any measure function on this node
pub fn yoga_node_clear_measure(node : YogaNodeRef) -> Unit {
  yoga_node_clear_measure_native(node)
}
