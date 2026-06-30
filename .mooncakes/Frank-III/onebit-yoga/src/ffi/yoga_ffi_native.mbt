///| Native FFI bindings for Yoga Layout Engine

///|
/// This file contains extern function declarations for the C API

// Only compile this for native targets
// @target(native)

// Type aliases for FFI - using Int as opaque pointers
struct YGNodeRef(Int)

///|
struct YGConfigRef(Int)

///|
struct YGMeasureFunc(Int)

// Yoga Config functions

///|
extern "C" fn yg_config_new() -> YGConfigRef = "YGConfigNew_wrap"

///|
extern "C" fn yg_config_free(config : YGConfigRef) = "YGConfigFree_wrap"

///|
extern "C" fn yg_config_set_use_web_defaults(
  config : YGConfigRef,
  enabled : Bool,
) = "YGConfigSetUseWebDefaults_wrap"

// Yoga Node functions

///|
extern "C" fn yg_node_new() -> YGNodeRef = "YGNodeNew_wrap"

///|
extern "C" fn yg_node_new_with_config(config : YGConfigRef) -> YGNodeRef = "YGNodeNewWithConfig_wrap"

///|
extern "C" fn yg_node_free(node : YGNodeRef) = "YGNodeFree_wrap"

///|
extern "C" fn yg_node_free_recursive(node : YGNodeRef) = "YGNodeFreeRecursive_wrap"

// Layout calculation

///|
extern "C" fn yg_node_calculate_layout(
  node : YGNodeRef,
  available_width : Float,
  available_height : Float,
  direction : Int,
) = "YGNodeCalculateLayout_wrap"

// Get layout results

///|
extern "C" fn yg_node_layout_get_left(node : YGNodeRef) -> Float = "YGNodeLayoutGetLeft_wrap"

///|
extern "C" fn yg_node_layout_get_top(node : YGNodeRef) -> Float = "YGNodeLayoutGetTop_wrap"

///|
extern "C" fn yg_node_layout_get_width(node : YGNodeRef) -> Float = "YGNodeLayoutGetWidth_wrap"

///|
extern "C" fn yg_node_layout_get_height(node : YGNodeRef) -> Float = "YGNodeLayoutGetHeight_wrap"

// Style setters - Display

///|
extern "C" fn yg_node_style_SetDisplay(node : YGNodeRef, display : Int) = "YGNodeStyleSetDisplay_wrap"

// Style setters - Flex

///|
extern "C" fn yg_node_style_SetFlexDirection(node : YGNodeRef, direction : Int) = "YGNodeStyleSetFlexDirection_wrap"

///|
extern "C" fn yg_node_style_SetFlexWrap(node : YGNodeRef, wrap : Int) = "YGNodeStyleSetFlexWrap_wrap"

///|
extern "C" fn yg_node_style_SetFlex(node : YGNodeRef, flex : Float) = "YGNodeStyleSetFlex_wrap"

///|
extern "C" fn yg_node_style_SetFlexGrow(node : YGNodeRef, grow : Float) = "YGNodeStyleSetFlexGrow_wrap"

///|
extern "C" fn yg_node_style_SetFlexShrink(node : YGNodeRef, shrink : Float) = "YGNodeStyleSetFlexShrink_wrap"

///|
extern "C" fn yg_node_style_SetFlexBasis(node : YGNodeRef, basis : Float) = "YGNodeStyleSetFlexBasis_wrap"

///|
extern "C" fn yg_node_style_SetFlexBasisPercent(
  node : YGNodeRef,
  basis : Float,
) = "YGNodeStyleSetFlexBasisPercent_wrap"

// Style setters - Justify & Align

///|
extern "C" fn yg_node_style_SetJustifyContent(node : YGNodeRef, justify : Int) = "YGNodeStyleSetJustifyContent_wrap"

///|
extern "C" fn yg_node_style_SetAlignContent(node : YGNodeRef, align : Int) = "YGNodeStyleSetAlignContent_wrap"

///|
extern "C" fn yg_node_style_SetAlignItems(node : YGNodeRef, align : Int) = "YGNodeStyleSetAlignItems_wrap"

///|
extern "C" fn yg_node_style_SetAlignSelf(node : YGNodeRef, align : Int) = "YGNodeStyleSetAlignSelf_wrap"

// Style setters - Position

///|
extern "C" fn yg_node_style_SetPositionType(node : YGNodeRef, position : Int) = "YGNodeStyleSetPositionType_wrap"

///|
extern "C" fn yg_node_style_SetPosition(
  node : YGNodeRef,
  edge : Int,
  position : Float,
) = "YGNodeStyleSetPosition_wrap"

///|
extern "C" fn yg_node_style_SetPositionPercent(
  node : YGNodeRef,
  edge : Int,
  position : Float,
) = "YGNodeStyleSetPositionPercent_wrap"

// Style setters - Size

///|
extern "C" fn yg_node_style_SetWidth(node : YGNodeRef, width : Float) = "YGNodeStyleSetWidth_wrap"

///|
extern "C" fn yg_node_style_SetWidthPercent(node : YGNodeRef, width : Float) = "YGNodeStyleSetWidthPercent_wrap"

///|
extern "C" fn yg_node_style_SetWidthAuto(node : YGNodeRef) = "YGNodeStyleSetWidthAuto_wrap"

///|
extern "C" fn yg_node_style_SetHeight(node : YGNodeRef, height : Float) = "YGNodeStyleSetHeight_wrap"

///|
extern "C" fn yg_node_style_SetHeightPercent(node : YGNodeRef, height : Float) = "YGNodeStyleSetHeightPercent_wrap"

///|
extern "C" fn yg_node_style_SetHeightAuto(node : YGNodeRef) = "YGNodeStyleSetHeightAuto_wrap"

// Style setters - Min/Max Size

///|
extern "C" fn yg_node_style_SetMinWidth(node : YGNodeRef, width : Float) = "YGNodeStyleSetMinWidth_wrap"

///|
extern "C" fn yg_node_style_SetMinWidthPercent(node : YGNodeRef, width : Float) = "YGNodeStyleSetMinWidthPercent_wrap"

///|
extern "C" fn yg_node_style_SetMinHeight(node : YGNodeRef, height : Float) = "YGNodeStyleSetMinHeight_wrap"

///|
extern "C" fn yg_node_style_SetMinHeightPercent(
  node : YGNodeRef,
  height : Float,
) = "YGNodeStyleSetMinHeightPercent_wrap"

///|
extern "C" fn yg_node_style_SetMaxWidth(node : YGNodeRef, width : Float) = "YGNodeStyleSetMaxWidth_wrap"

///|
extern "C" fn yg_node_style_SetMaxWidthPercent(node : YGNodeRef, width : Float) = "YGNodeStyleSetMaxWidthPercent_wrap"

///|
extern "C" fn yg_node_style_SetMaxHeight(node : YGNodeRef, height : Float) = "YGNodeStyleSetMaxHeight_wrap"

///|
extern "C" fn yg_node_style_SetMaxHeightPercent(
  node : YGNodeRef,
  height : Float,
) = "YGNodeStyleSetMaxHeightPercent_wrap"

// Style setters - Margin

///|
extern "C" fn yg_node_style_SetMargin(
  node : YGNodeRef,
  edge : Int,
  margin : Float,
) = "YGNodeStyleSetMargin_wrap"

///|
extern "C" fn yg_node_style_SetMarginPercent(
  node : YGNodeRef,
  edge : Int,
  margin : Float,
) = "YGNodeStyleSetMarginPercent_wrap"

///|
extern "C" fn yg_node_style_SetMarginAuto(node : YGNodeRef, edge : Int) = "YGNodeStyleSetMarginAuto_wrap"

// Style setters - Padding

///|
extern "C" fn yg_node_style_SetPadding(
  node : YGNodeRef,
  edge : Int,
  padding : Float,
) = "YGNodeStyleSetPadding_wrap"

///|
extern "C" fn yg_node_style_SetPaddingPercent(
  node : YGNodeRef,
  edge : Int,
  padding : Float,
) = "YGNodeStyleSetPaddingPercent_wrap"

// Style setters - Border

///|
extern "C" fn yg_node_style_SetBorder(
  node : YGNodeRef,
  edge : Int,
  border : Float,
) = "YGNodeStyleSetBorder_wrap"

///|
extern "C" fn yg_node_style_SetGap(node : YGNodeRef, gutter : Int, gap : Float) = "YGNodeStyleSetGap_wrap"

// Tree management

///|
extern "C" fn yg_node_insert_child(
  parent : YGNodeRef,
  child : YGNodeRef,
  index : Int,
) = "YGNodeInsertChild_wrap"

///|
extern "C" fn yg_node_remove_child(parent : YGNodeRef, child : YGNodeRef) = "YGNodeRemoveChild_wrap"

///|
extern "C" fn yg_node_get_child_count(parent : YGNodeRef) -> Int = "YGNodeGetChildCount_wrap"

///|
extern "C" fn yg_node_get_child(parent : YGNodeRef, index : Int) -> YGNodeRef = "YGNodeGetChild_wrap"

///|
extern "C" fn yg_node_set_measure_fixed(
  node : YGNodeRef,
  width : Float,
  height : Float,
) = "YGNodeSetMeasureFuncFixed_wrap"

///|
extern "C" fn yg_node_clear_measure(node : YGNodeRef) = "YGNodeClearMeasureFunc_wrap"

// Now create wrapper functions that convert our types to Yoga's integer constants

///|
pub fn yoga_config_new_native() -> YogaConfigRef {
  let YGConfigRef(id) = yg_config_new()
  YogaConfigRef(id)
}

///|
pub fn yoga_config_free_native(config : YogaConfigRef) -> Unit {
  match config {
    YogaConfigRef(ref) => yg_config_free(YGConfigRef(ref))
  }
}

///|
pub fn yoga_node_new_native() -> YogaNodeRef {
  let YGNodeRef(id) = yg_node_new()
  YogaNodeRef(id)
}

///|
pub fn yoga_node_new_with_config_native(config : YogaConfigRef) -> YogaNodeRef {
  match config {
    YogaConfigRef(ref) => {
      let YGNodeRef(id) = yg_node_new_with_config(YGConfigRef(ref))
      YogaNodeRef(id)
    }
  }
}

///|
pub fn yoga_node_free_native(node : YogaNodeRef) -> Unit {
  match node {
    YogaNodeRef(ref) => yg_node_free(YGNodeRef(ref))
  }
}

///|
/// Free a Yoga node and all of its descendants (recursive)
pub fn yoga_node_free_recursive_native(node : YogaNodeRef) -> Unit {
  match node {
    YogaNodeRef(ref) => yg_node_free_recursive(YGNodeRef(ref))
  }
}

// Convert Direction enum to Yoga constants

///|
fn direction_to_yoga(dir : @types.Direction) -> Int {
  match dir {
    @types.Direction::Inherit => 0
    @types.Direction::LTR => 1
    @types.Direction::RTL => 2
  }
}

// Convert Display enum to Yoga constants

///|
fn display_to_yoga(display : @types.Display) -> Int {
  match display {
    @types.Display::Flex => 0
    @types.Display::None => 1
    @types.Display::Contents => 2
  }
}

// Convert FlexDirection enum to Yoga constants

///|
fn flex_direction_to_yoga(dir : @types.FlexDirection) -> Int {
  match dir {
    @types.FlexDirection::Column => 0
    @types.FlexDirection::ColumnReverse => 1
    @types.FlexDirection::Row => 2
    @types.FlexDirection::RowReverse => 3
  }
}

// Convert Wrap enum to Yoga constants

///|
fn wrap_to_yoga(wrap : @types.Wrap) -> Int {
  match wrap {
    @types.Wrap::NoWrap => 0
    @types.Wrap::Wrap => 1
    @types.Wrap::WrapReverse => 2
  }
}

// Convert Justify enum to Yoga constants

///|
fn justify_to_yoga(justify : @types.Justify) -> Int {
  match justify {
    @types.Justify::FlexStart => 0
    @types.Justify::Center => 1
    @types.Justify::FlexEnd => 2
    @types.Justify::SpaceBetween => 3
    @types.Justify::SpaceAround => 4
    @types.Justify::SpaceEvenly => 5
  }
}

// Convert Align enum to Yoga constants

///|
fn align_to_yoga(align : @types.Align) -> Int {
  match align {
    @types.Align::Auto => 0
    @types.Align::FlexStart => 1
    @types.Align::Center => 2
    @types.Align::FlexEnd => 3
    @types.Align::Stretch => 4
    @types.Align::Baseline => 5
    @types.Align::SpaceBetween => 6
    @types.Align::SpaceAround => 7
    @types.Align::SpaceEvenly => 8
  }
}

// Convert Gutter enum to Yoga constants

///|
fn gutter_to_yoga(gutter : @types.Gutter) -> Int {
  match gutter {
    @types.Gutter::Column => 0
    @types.Gutter::Row => 1
    @types.Gutter::All => 2
  }
}

// Convert PositionType enum to Yoga constants

///|
fn position_type_to_yoga(pos : @types.PositionType) -> Int {
  match pos {
    @types.PositionType::Static => 0
    @types.PositionType::Relative => 1
    @types.PositionType::Absolute => 2
  }
}

// Convert Edge enum to Yoga constants

///|
fn edge_to_yoga(edge : @types.Edge) -> Int {
  match edge {
    @types.Edge::Left => 0
    @types.Edge::Top => 1
    @types.Edge::Right => 2
    @types.Edge::Bottom => 3
    @types.Edge::Start => 4
    @types.Edge::End => 5
    @types.Edge::Horizontal => 6
    @types.Edge::Vertical => 7
    @types.Edge::All => 8
  }
}

///|
pub fn yoga_node_calculate_layout_native(
  node : YogaNodeRef,
  available_width : Float,
  available_height : Float,
  direction : @types.Direction,
) -> Unit {
  match node {
    YogaNodeRef(ref) =>
      yg_node_calculate_layout(
        YGNodeRef(ref),
        available_width,
        available_height,
        direction_to_yoga(direction),
      )
  }
}

///|
pub fn yoga_node_get_layout_native(node : YogaNodeRef) -> Layout {
  match node {
    YogaNodeRef(ref) =>
      {
        left: yg_node_layout_get_left(YGNodeRef(ref)),
        top: yg_node_layout_get_top(YGNodeRef(ref)),
        width: yg_node_layout_get_width(YGNodeRef(ref)),
        height: yg_node_layout_get_height(YGNodeRef(ref)),
      }
  }
}

// Style setters

///|
pub fn yoga_node_set_display_native(
  node : YogaNodeRef,
  display : @types.Display,
) -> Unit {
  match node {
    YogaNodeRef(ref) =>
      yg_node_style_SetDisplay(YGNodeRef(ref), display_to_yoga(display))
  }
}

///|
pub fn yoga_node_set_flex_direction_native(
  node : YogaNodeRef,
  direction : @types.FlexDirection,
) -> Unit {
  match node {
    YogaNodeRef(ref) =>
      yg_node_style_SetFlexDirection(
        YGNodeRef(ref),
        flex_direction_to_yoga(direction),
      )
  }
}

///|
pub fn yoga_node_set_justify_content_native(
  node : YogaNodeRef,
  justify : @types.Justify,
) -> Unit {
  match node {
    YogaNodeRef(ref) =>
      yg_node_style_SetJustifyContent(YGNodeRef(ref), justify_to_yoga(justify))
  }
}

///|
pub fn yoga_node_set_align_items_native(
  node : YogaNodeRef,
  align : @types.Align,
) -> Unit {
  match node {
    YogaNodeRef(ref) =>
      yg_node_style_SetAlignItems(YGNodeRef(ref), align_to_yoga(align))
  }
}

///|
pub fn yoga_node_set_align_self_native(
  node : YogaNodeRef,
  align : @types.Align,
) -> Unit {
  match node {
    YogaNodeRef(ref) =>
      yg_node_style_SetAlignSelf(YGNodeRef(ref), align_to_yoga(align))
  }
}

///|
pub fn yoga_node_set_align_content_native(
  node : YogaNodeRef,
  align : @types.Align,
) -> Unit {
  match node {
    YogaNodeRef(ref) =>
      yg_node_style_SetAlignContent(YGNodeRef(ref), align_to_yoga(align))
  }
}

///|
pub fn yoga_node_set_flex_wrap_native(
  node : YogaNodeRef,
  wrap : @types.Wrap,
) -> Unit {
  match node {
    YogaNodeRef(ref) =>
      yg_node_style_SetFlexWrap(YGNodeRef(ref), wrap_to_yoga(wrap))
  }
}

///|
pub fn yoga_node_set_position_type_native(
  node : YogaNodeRef,
  position : @types.PositionType,
) -> Unit {
  match node {
    YogaNodeRef(ref) =>
      yg_node_style_SetPositionType(
        YGNodeRef(ref),
        position_type_to_yoga(position),
      )
  }
}

///|
pub fn yoga_node_set_width_native(node : YogaNodeRef, width : Float) -> Unit {
  match node {
    YogaNodeRef(ref) => yg_node_style_SetWidth(YGNodeRef(ref), width)
  }
}

///|
pub fn yoga_node_set_height_native(node : YogaNodeRef, height : Float) -> Unit {
  match node {
    YogaNodeRef(ref) => yg_node_style_SetHeight(YGNodeRef(ref), height)
  }
}

///|
pub fn yoga_node_set_width_percent_native(
  node : YogaNodeRef,
  width : Float,
) -> Unit {
  match node {
    YogaNodeRef(ref) => yg_node_style_SetWidthPercent(YGNodeRef(ref), width)
  }
}

///|
pub fn yoga_node_set_height_percent_native(
  node : YogaNodeRef,
  height : Float,
) -> Unit {
  match node {
    YogaNodeRef(ref) => yg_node_style_SetHeightPercent(YGNodeRef(ref), height)
  }
}

///|
pub fn yoga_node_set_width_auto_native(node : YogaNodeRef) -> Unit {
  match node {
    YogaNodeRef(ref) => yg_node_style_SetWidthAuto(YGNodeRef(ref))
  }
}

///|
pub fn yoga_node_set_height_auto_native(node : YogaNodeRef) -> Unit {
  match node {
    YogaNodeRef(ref) => yg_node_style_SetHeightAuto(YGNodeRef(ref))
  }
}

///|
pub fn yoga_node_set_flex_native(node : YogaNodeRef, flex : Float) -> Unit {
  match node {
    YogaNodeRef(ref) => yg_node_style_SetFlex(YGNodeRef(ref), flex)
  }
}

///|
pub fn yoga_node_set_flex_grow_native(node : YogaNodeRef, grow : Float) -> Unit {
  match node {
    YogaNodeRef(ref) => yg_node_style_SetFlexGrow(YGNodeRef(ref), grow)
  }
}

///|
pub fn yoga_node_set_flex_shrink_native(
  node : YogaNodeRef,
  shrink : Float,
) -> Unit {
  match node {
    YogaNodeRef(ref) => yg_node_style_SetFlexShrink(YGNodeRef(ref), shrink)
  }
}

///|
pub fn yoga_node_set_flex_basis_native(
  node : YogaNodeRef,
  basis : Float,
) -> Unit {
  match node {
    YogaNodeRef(ref) => yg_node_style_SetFlexBasis(YGNodeRef(ref), basis)
  }
}

///|
pub fn yoga_node_set_min_width_native(node : YogaNodeRef, width : Float) -> Unit {
  match node {
    YogaNodeRef(ref) => yg_node_style_SetMinWidth(YGNodeRef(ref), width)
  }
}

///|
pub fn yoga_node_set_min_height_native(node : YogaNodeRef, height : Float) -> Unit {
  match node {
    YogaNodeRef(ref) => yg_node_style_SetMinHeight(YGNodeRef(ref), height)
  }
}

///|
pub fn yoga_node_set_max_width_native(node : YogaNodeRef, width : Float) -> Unit {
  match node {
    YogaNodeRef(ref) => yg_node_style_SetMaxWidth(YGNodeRef(ref), width)
  }
}

///|
pub fn yoga_node_set_max_height_native(node : YogaNodeRef, height : Float) -> Unit {
  match node {
    YogaNodeRef(ref) => yg_node_style_SetMaxHeight(YGNodeRef(ref), height)
  }
}

///|
pub fn yoga_node_set_margin_native(
  node : YogaNodeRef,
  edge : @types.Edge,
  margin : Float,
) -> Unit {
  match node {
    YogaNodeRef(ref) =>
      yg_node_style_SetMargin(YGNodeRef(ref), edge_to_yoga(edge), margin)
  }
}

///|
pub fn yoga_node_set_margin_percent_native(
  node : YogaNodeRef,
  edge : @types.Edge,
  margin : Float,
) -> Unit {
  match node {
    YogaNodeRef(ref) =>
      yg_node_style_SetMarginPercent(YGNodeRef(ref), edge_to_yoga(edge), margin)
  }
}

///|
pub fn yoga_node_set_margin_auto_native(
  node : YogaNodeRef,
  edge : @types.Edge,
) -> Unit {
  match node {
    YogaNodeRef(ref) =>
      yg_node_style_SetMarginAuto(YGNodeRef(ref), edge_to_yoga(edge))
  }
}

///|
pub fn yoga_node_set_padding_native(
  node : YogaNodeRef,
  edge : @types.Edge,
  padding : Float,
) -> Unit {
  match node {
    YogaNodeRef(ref) =>
      yg_node_style_SetPadding(YGNodeRef(ref), edge_to_yoga(edge), padding)
  }
}

///|
pub fn yoga_node_set_padding_percent_native(
  node : YogaNodeRef,
  edge : @types.Edge,
  padding : Float,
) -> Unit {
  match node {
    YogaNodeRef(ref) =>
      yg_node_style_SetPaddingPercent(
        YGNodeRef(ref),
        edge_to_yoga(edge),
        padding,
      )
  }
}

///|
pub fn yoga_node_set_gap_native(
  node : YogaNodeRef,
  gutter : @types.Gutter,
  gap : Float,
) -> Unit {
  match node {
    YogaNodeRef(ref) =>
      yg_node_style_SetGap(YGNodeRef(ref), gutter_to_yoga(gutter), gap)
  }
}

///|
pub fn yoga_node_set_position_native(
  node : YogaNodeRef,
  edge : @types.Edge,
  position : Float,
) -> Unit {
  match node {
    YogaNodeRef(ref) =>
      yg_node_style_SetPosition(YGNodeRef(ref), edge_to_yoga(edge), position)
  }
}

///|
pub fn yoga_node_set_position_percent_native(
  node : YogaNodeRef,
  edge : @types.Edge,
  position : Float,
) -> Unit {
  match node {
    YogaNodeRef(ref) =>
      yg_node_style_SetPositionPercent(
        YGNodeRef(ref),
        edge_to_yoga(edge),
        position,
      )
  }
}

///|
pub fn yoga_node_insert_child_native(
  parent : YogaNodeRef,
  child : YogaNodeRef,
  index : Int,
) -> Unit {
  match (parent, child) {
    (YogaNodeRef(p), YogaNodeRef(c)) =>
      yg_node_insert_child(YGNodeRef(p), YGNodeRef(c), index)
  }
}

///|
pub fn yoga_node_remove_child_native(
  parent : YogaNodeRef,
  child : YogaNodeRef,
) -> Unit {
  match (parent, child) {
    (YogaNodeRef(p), YogaNodeRef(c)) =>
      yg_node_remove_child(YGNodeRef(p), YGNodeRef(c))
  }
}

///|
pub fn yoga_node_get_child_count_native(parent : YogaNodeRef) -> Int {
  match parent {
    YogaNodeRef(ref) => yg_node_get_child_count(YGNodeRef(ref))
  }
}

///|
pub fn yoga_node_get_child_native(
  parent : YogaNodeRef,
  index : Int,
) -> YogaNodeRef? {
  match parent {
    YogaNodeRef(ref) => {
      let YGNodeRef(child) = yg_node_get_child(YGNodeRef(ref), index)
      if child == 0 {
        None
      } else {
        Some(YogaNodeRef(child))
      }
    }
  }
}

///|
pub fn yoga_node_set_measure_fixed_native(
  node : YogaNodeRef,
  width : Float,
  height : Float,
) -> Unit {
  match node {
    YogaNodeRef(ref) => yg_node_set_measure_fixed(YGNodeRef(ref), width, height)
  }
}

///|
pub fn yoga_node_clear_measure_native(node : YogaNodeRef) -> Unit {
  match node {
    YogaNodeRef(ref) => yg_node_clear_measure(YGNodeRef(ref))
  }
}
