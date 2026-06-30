///| Simplified View type - just a rendering primitive

///|
/// Components produce Views, Views are rendered to screen

// Global counter for view IDs
let view_id_counter : Ref[Int] = Ref::new(1000)

///|
pub struct View {
  // Layout properties
  mut width : Size?
  mut height : Size?
  mut min_width_value : Double?
  mut min_height_value : Double?
  mut max_width_value : Double?
  mut max_height_value : Double?
  mut flex_value : Double?
  mut flex_shrink_value : Double?
  mut layout_direction : Direction?
  mut spacing : Double?
  mut padding_value : Double?
  mut padding_top_value : Double?
  mut padding_right_value : Double?
  mut padding_bottom_value : Double?
  mut padding_left_value : Double?
  mut margin_value : Double?
  mut margin_top_value : Double?
  mut margin_right_value : Double?
  mut margin_bottom_value : Double?
  mut margin_left_value : Double?
  mut align_items_value : @types.Align?
  mut justify_content_value : @types.Justify?
  mut align_self_value : @types.Align?
  mut flex_basis_value : Double?

  // Style properties  
  mut bg_color : @core.Color?
  mut fg_color : @core.Color?
  mut border_style : BorderStyle?
  mut border_color : @core.Color?
  mut focused_border_color : @core.Color?
  mut title_text : String?
  mut title_align : TitleAlign?
  // Optional caret column for text views (used when focused)
  mut caret_col : Int?

  // Position
  mut position_type : Position?
  mut top_offset : Double?
  mut left_offset : Double?

  // Content
  content : ViewContent

  // Children
  children : Array[View]

  // Event handling (simplified)
  mut key_handler : ((@ffi.KeyEvent) -> Bool)?
  mut event_handler : ((@events.Event) -> Bool)?
  mut key_mod_handler : ((@ffi.KeyEvent, @ffi.KeyModifiers) -> Bool)?
  mut click_handler : ((Int, Int) -> Unit)?

  // Focus
  mut is_focusable : Bool
  mut is_focused : Bool
  mut view_id : Int?

  // Overflow
  mut overflow_y : Overflow?
}

///|
pub(all) enum Size {
  Fixed(Double)
  Percent(Double)
  Auto
}

///|
pub(all) enum Direction {
  Row
  Column
}

///|
pub(all) enum Position {
  Relative
  Absolute
}

///|
pub(all) enum BorderStyle {
  None
  Single
  Double
  Rounded
}

///|
pub(all) enum ViewContent {
  Empty
  Text(String)
}

///|
pub(all) enum Overflow {
  Visible
  Hidden
  Scroll
}

///|
pub(all) enum TitleAlign {
  Left
  Center
  Right
}

///|
/// Create an empty view
pub fn View::empty() -> View {
  {
    width: None,
    height: None,
    min_width_value: None,
    min_height_value: None,
    max_width_value: None,
    max_height_value: None,
    flex_value: None,
    flex_shrink_value: None,
    layout_direction: None,
    spacing: None,
    padding_value: None,
    padding_top_value: None,
    padding_right_value: None,
    padding_bottom_value: None,
    padding_left_value: None,
    margin_value: None,
    margin_top_value: None,
    margin_right_value: None,
    margin_bottom_value: None,
    margin_left_value: None,
    align_items_value: None,
    justify_content_value: None,
    align_self_value: None,
    flex_basis_value: None,
    bg_color: None,
    fg_color: None,
    border_style: None,
    border_color: None,
    focused_border_color: None,
    title_text: None,
    title_align: None,
    caret_col: None,
    position_type: None,
    top_offset: None,
    left_offset: None,
    content: ViewContent::Empty,
    children: [],
    key_handler: None,
    event_handler: None,
    key_mod_handler: None,
    click_handler: None,
    is_focusable: false,
    is_focused: false,
    view_id: None,
    overflow_y: None,
  }
}

///|
/// Create a text view
pub fn View::text(
  text : String,
  color? : @core.Color = @core.Color::White,
) -> View {
  {
    width: None,
    height: None,
    min_width_value: None,
    min_height_value: None,
    max_width_value: None,
    max_height_value: None,
    flex_value: None,
    flex_shrink_value: None,
    layout_direction: None,
    spacing: None,
    padding_value: None,
    padding_top_value: None,
    padding_right_value: None,
    padding_bottom_value: None,
    padding_left_value: None,
    margin_value: None,
    margin_top_value: None,
    margin_right_value: None,
    margin_bottom_value: None,
    margin_left_value: None,
    align_items_value: None,
    justify_content_value: None,
    align_self_value: None,
    flex_basis_value: None,
    bg_color: None,
    fg_color: Some(color),
    border_style: None,
    border_color: None,
    focused_border_color: None,
    title_text: None,
    title_align: None,
    caret_col: None,
    position_type: None,
    top_offset: None,
    left_offset: None,
    content: ViewContent::Text(text),
    children: [],
    key_handler: None,
    event_handler: None,
    key_mod_handler: None,
    click_handler: None,
    is_focusable: false,
    is_focused: false,
    view_id: None,
    overflow_y: None,
  }
}

///|
/// Create a container view from View array (low-level)
pub fn View::container_views(children : Array[View]) -> View {
  {
    width: None,
    height: None,
    min_width_value: None,
    min_height_value: None,
    max_width_value: None,
    max_height_value: None,
    flex_value: None,
    flex_shrink_value: None,
    layout_direction: None,
    spacing: None,
    padding_value: None,
    padding_top_value: None,
    padding_right_value: None,
    padding_bottom_value: None,
    padding_left_value: None,
    margin_value: None,
    margin_top_value: None,
    margin_right_value: None,
    margin_bottom_value: None,
    margin_left_value: None,
    align_items_value: None,
    justify_content_value: None,
    align_self_value: None,
    flex_basis_value: None,
    bg_color: None,
    fg_color: None,
    border_style: None,
    border_color: None,
    focused_border_color: None,
    title_text: None,
    title_align: None,
    caret_col: None,
    position_type: None,
    top_offset: None,
    left_offset: None,
    content: ViewContent::Empty,
    children,
    key_handler: None,
    event_handler: None,
    key_mod_handler: None,
    click_handler: None,
    is_focusable: false,
    is_focused: false,
    view_id: None,
    overflow_y: None,
  }
}

// Builder methods for chaining

///|
pub fn View::width(self : View, w : Double) -> View {
  self.width = Some(Size::Fixed(w))
  self
}

///|
pub fn View::height(self : View, h : Double) -> View {
  self.height = Some(Size::Fixed(h))
  self
}

///|
pub fn View::width_percent(self : View, p : Double) -> View {
  self.width = Some(Size::Percent(p))
  self
}

///|
pub fn View::height_percent(self : View, p : Double) -> View {
  self.height = Some(Size::Percent(p))
  self
}

///|
pub fn View::min_width(self : View, w : Double) -> View {
  self.min_width_value = Some(w)
  self
}

///|
pub fn View::min_height(self : View, h : Double) -> View {
  self.min_height_value = Some(h)
  self
}

///|
pub fn View::max_width(self : View, w : Double) -> View {
  self.max_width_value = Some(w)
  self
}

///|
pub fn View::max_height(self : View, h : Double) -> View {
  self.max_height_value = Some(h)
  self
}

///|
pub fn View::flex(self : View, f : Double) -> View {
  self.flex_value = Some(f)
  self
}

///|
/// Set flex-shrink (default upstream is 1)
pub fn View::shrink(self : View, s : Double) -> View {
  self.flex_shrink_value = Some(s)
  self
}

///|
pub fn View::flex_basis(self : View, basis : Double) -> View {
  self.flex_basis_value = Some(basis)
  self
}

///|
pub fn View::padding(self : View, p : Double) -> View {
  self.padding_value = Some(p)
  self
}

///|
pub fn View::padding_top(self : View, p : Double) -> View {
  self.padding_top_value = Some(p)
  self
}

///|
pub fn View::padding_right(self : View, p : Double) -> View {
  self.padding_right_value = Some(p)
  self
}

///|
pub fn View::padding_bottom(self : View, p : Double) -> View {
  self.padding_bottom_value = Some(p)
  self
}

///|
pub fn View::padding_left(self : View, p : Double) -> View {
  self.padding_left_value = Some(p)
  self
}

///|
pub fn View::margin(self : View, m : Double) -> View {
  self.margin_value = Some(m)
  self
}

///|
pub fn View::margin_top(self : View, m : Double) -> View {
  self.margin_top_value = Some(m)
  self
}

///|
pub fn View::margin_right(self : View, m : Double) -> View {
  self.margin_right_value = Some(m)
  self
}

///|
pub fn View::margin_bottom(self : View, m : Double) -> View {
  self.margin_bottom_value = Some(m)
  self
}

///|
pub fn View::margin_left(self : View, m : Double) -> View {
  self.margin_left_value = Some(m)
  self
}

///|
pub fn View::background(self : View, color : @core.Color) -> View {
  self.bg_color = Some(color)
  self
}

///|
pub fn View::foreground(self : View, color : @core.Color) -> View {
  self.fg_color = Some(color)
  self
}

///|
pub fn View::border(
  self : View,
  style : BorderStyle,
  color? : @core.Color = @core.Color::Gray,
) -> View {
  self.border_style = Some(style)
  self.border_color = Some(color)
  self
}

///|
pub fn View::focused_border_color(self : View, color : @core.Color) -> View {
  self.focused_border_color = Some(color)
  self
}

///|
/// Set an optional title for bordered containers
pub fn View::title(self : View, text : String) -> View {
  self.title_text = Some(text)
  self
}

///|
pub fn View::title_align(self : View, align : TitleAlign) -> View {
  self.title_align = Some(align)
  self
}

///|
/// Set caret column for text inputs (drawn when focused)
pub fn View::caret_col(self : View, col : Int) -> View {
  self.caret_col = Some(col)
  self
}

///|
pub fn View::direction(self : View, dir : Direction) -> View {
  self.layout_direction = Some(dir)
  self
}

///|
pub fn View::spacing(self : View, s : Double) -> View {
  self.spacing = Some(s)
  self
}

///|
pub fn View::focusable(self : View, f? : Bool = true) -> View {
  self.is_focusable = f
  // Auto-assign ID if focusable and doesn't have one
  if f {
    match self.view_id {
      None => {
        self.view_id = Some(view_id_counter.val)
        view_id_counter.val = view_id_counter.val + 1
      }
      Some(_) => ()
    }
  }
  self
}

///|
pub fn View::on_key(self : View, handler : (@ffi.KeyEvent) -> Bool) -> View {
  self.key_handler = Some(handler)
  self.is_focusable = true
  // Auto-assign ID if doesn't have one
  match self.view_id {
    None => {
      self.view_id = Some(view_id_counter.val)
      view_id_counter.val = view_id_counter.val + 1
    }
    Some(_) => ()
  }
  self
}

///|
pub fn View::on_key_mod(
  self : View,
  handler : (@ffi.KeyEvent, @ffi.KeyModifiers) -> Bool,
) -> View {
  self.key_mod_handler = Some(handler)
  self.is_focusable = true
  // Auto-assign ID if doesn't have one
  match self.view_id {
    None => {
      self.view_id = Some(view_id_counter.val)
      view_id_counter.val = view_id_counter.val + 1
    }
    Some(_) => ()
  }
  self
}

///|
pub fn View::on_click(self : View, handler : ((Int, Int) -> Unit)?) -> View {
  self.click_handler = handler
  // Ensure an ID exists for hit-testing and dispatch
  match self.view_id {
    None => {
      self.view_id = Some(view_id_counter.val)
      view_id_counter.val = view_id_counter.val + 1
    }
    Some(_) => ()
  }
  self
}

///|
/// Unified event handler; receives Key/KeyMod/Mouse/Paste via runtime dispatch
pub fn View::on_event(self : View, handler : (@events.Event) -> Bool) -> View {
  self.event_handler = Some(handler)
  // Ensure an ID exists for hit-testing and dispatch
  match self.view_id {
    None => {
      self.view_id = Some(view_id_counter.val)
      view_id_counter.val = view_id_counter.val + 1
    }
    Some(_) => ()
  }
  self
}

///|
/// Assign a stable view ID (useful across rebuilds for focus/dispatch)
pub fn View::id(self : View, id : Int) -> View {
  self.view_id = Some(id)
  self
}

///|
pub fn View::align_items(self : View, align : @types.Align) -> View {
  self.align_items_value = Some(align)
  self
}

///|
pub fn View::justify_content(self : View, justify : @types.Justify) -> View {
  self.justify_content_value = Some(justify)
  self
}

///|
pub fn View::align_self(self : View, align : @types.Align) -> View {
  self.align_self_value = Some(align)
  self
}

///|
pub fn View::overflow_y(self : View, overflow : Overflow) -> View {
  self.overflow_y = Some(overflow)
  self
}

///|
/// Set position type (relative or absolute)
pub fn View::position(self : View, pos : Position) -> View {
  self.position_type = Some(pos)
  self
}

///|
/// Set top offset for positioned elements
pub fn View::top(self : View, offset : Double) -> View {
  self.top_offset = Some(offset)
  self
}

///|
/// Set left offset for positioned elements
pub fn View::left(self : View, offset : Double) -> View {
  self.left_offset = Some(offset)
  self
}

///|
/// Helper for margin-top (using Yoga's margin edge)
// margin_top provided above

///|
/// Set focus state - used by event dispatcher
pub fn View::set_focused(self : View, focused : Bool) -> Unit {
  self.is_focused = focused
}

///|
/// Component trait - all UI elements implement this
/// Using pub(open) so types in other modules can implement it
pub(open) trait Component {
  /// Render this component to a View tree
  render(Self) -> View

  /// Handle any event (return true if handled)
  handle_event(Self, @events.Event) -> Bool

  /// Whether this component can receive focus
  is_focusable(Self) -> Bool
}

///|
/// Create a container from components - this is the primary container API
pub fn View::container(components : Array[&Component]) -> View {
  let views : Array[View] = []
  for i = 0; i < components.length(); i = i + 1 {
    views.push(components[i].render())
  }
  View::container_views(views)
}
