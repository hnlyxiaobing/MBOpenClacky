///|
/// Select Widget - Dropdown selection from options
pub struct Select[T] {
  options : Array[T]
  selected : Ref[Int?] // None = no selection
  display_fn : (T) -> String
  mut placeholder : String
  mut is_open : Bool
  mut hover_index : Int
  mut max_visible : Int // Max items shown when dropdown is open
  mut on_change : (Int?, T?) -> Unit // (index, value) -> Unit
  mut style : SelectStyle
  mut id : Int?
}

///|
pub struct SelectStyle {
  border : @view.BorderStyle
  border_color : @core.Color
  selected_bg : @core.Color
  hover_bg : @core.Color
  text_color : @core.Color
  placeholder_color : @core.Color
  dropdown_border : @view.BorderStyle
}

///|
/// Create a new select widget
pub fn[T] Select::new(
  options : Array[T],
  display_fn : (T) -> String,
  selected? : Ref[Int?] = Ref::new(None),
) -> Select[T] {
  {
    options,
    selected,
    display_fn,
    placeholder: "Select...",
    is_open: false,
    hover_index: match selected.val {
      Some(idx) => idx
      None => 0
    },
    max_visible: 5,
    on_change: fn(_index, _value) {  },
    style: SelectStyle::default(),
    id: None,
  }
}

///|
/// Set placeholder text
pub fn[T] Select::placeholder(self : Select[T], text : String) -> Select[T] {
  self.placeholder = text
  self
}

///|
/// Set maximum visible items when open
pub fn[T] Select::max_visible(self : Select[T], count : Int) -> Select[T] {
  self.max_visible = count
  self
}

///|
/// Set change handler
pub fn[T] Select::on_change(
  self : Select[T],
  handler : (Int?, T?) -> Unit,
) -> Select[T] {
  self.on_change = handler
  self
}

///|
/// Set style
pub fn[T] Select::with_style(
  self : Select[T],
  style : SelectStyle,
) -> Select[T] {
  self.style = style
  self
}

///|
/// Assign a stable ID for focus management
pub fn[T] Select::with_id(self : Select[T], id : Int) -> Select[T] {
  self.id = Some(id)
  self
}

///|
/// Default select style
pub fn SelectStyle::default() -> SelectStyle {
  {
    border: @view.BorderStyle::Single,
    border_color: @core.Color::White,
    selected_bg: @core.rgb(0, 50, 100), // Dark blue
    hover_bg: @core.rgb(50, 50, 50), // Dark gray
    text_color: @core.Color::White,
    placeholder_color: @core.Color::Gray,
    dropdown_border: @view.BorderStyle::Single,
  }
}

///|
/// Navigate up in the dropdown
fn[T] Select::move_up(self : Select[T]) -> Bool {
  if self.is_open && self.hover_index > 0 {
    self.hover_index = self.hover_index - 1
    true
  } else {
    false
  }
}

///|
/// Navigate down in the dropdown
fn[T] Select::move_down(self : Select[T]) -> Bool {
  if self.is_open && self.hover_index < self.options.length() - 1 {
    self.hover_index = self.hover_index + 1
    true
  } else {
    false
  }
}

///|
/// Select the currently hovered item
fn[T] Select::select_current(self : Select[T]) -> Unit {
  if self.is_open && self.hover_index < self.options.length() {
    self.selected.val = Some(self.hover_index)
    let value = self.options[self.hover_index]
    let handler = self.on_change
    handler(Some(self.hover_index), Some(value))
    self.is_open = false
  }
}

///|
/// Handle per-item mouse/key events inside the dropdown
fn[T] Select::handle_item_event(self : Select[T], index : Int, event : @events.Event) -> Bool {
  match event {
    @events.Event::Mouse(mouse) =>
      match mouse.action {
        @events.MouseAction::Move => { self.hover_index = index; true }
        @events.MouseAction::Click => { self.hover_index = index; self.select_current(); true }
        _ => false
      }
    @events.Event::Key(key) =>
      match key {
        @ffi.KeyEvent::ArrowUp => self.move_up()
        @ffi.KeyEvent::ArrowDown => self.move_down()
        @ffi.KeyEvent::Home => { self.hover_index = 0; true }
        @ffi.KeyEvent::End => { self.hover_index = if self.options.length() > 0 { self.options.length() - 1 } else { 0 }; true }
        @ffi.KeyEvent::Enter | @ffi.KeyEvent::Char(32) => { self.select_current(); true }
        _ => false
      }
    @events.Event::KeyMod(key, _mods) =>
      match key {
        @ffi.KeyEvent::ArrowUp => self.move_up()
        @ffi.KeyEvent::ArrowDown => self.move_down()
        @ffi.KeyEvent::Home => { self.hover_index = 0; true }
        @ffi.KeyEvent::End => { self.hover_index = if self.options.length() > 0 { self.options.length() - 1 } else { 0 }; true }
        @ffi.KeyEvent::Enter | @ffi.KeyEvent::Char(32) => { self.select_current(); true }
        _ => false
      }
    _ => false
  }
}

///|
/// Implement Component trait for Select
pub impl[T] @view.Component for Select[T] with render(self) {
  // Get display text
  let display_text = match self.selected.val {
    Some(idx) if idx < self.options.length() => {
      let fn_val = self.display_fn
      fn_val(self.options[idx])
    }
    _ => self.placeholder
  }
  let text_color = match self.selected.val {
    Some(_) => self.style.text_color
    None => self.style.placeholder_color
  }

  // Add dropdown arrow indicator
  let arrow = if self.is_open { " ▲" } else { " ▼" }
  let display_with_arrow = display_text + arrow

  // Calculate minimum width for better appearance
  let min_width = 20.0 // Minimum width for select box
  let text_width = display_with_arrow.length().to_double() + 4.0
  let box_width = if text_width < min_width { min_width } else { text_width }

  // Create the main select box with arrow
  let select_box = @view.View::text(display_with_arrow, color=text_color)
    .padding(1.0)
    .width(box_width)
    .border(self.style.border, color=self.style.border_color)
    .focused_border_color(@core.Color::Cyan)
    .focusable()

  // If open, create dropdown
  if self.is_open {
    let dropdown_items : Array[@view.View] = []

    // Calculate visible range
    let start_idx = if self.hover_index < self.max_visible {
      0
    } else {
      self.hover_index - self.max_visible + 1
    }
    let end_idx = if start_idx + self.max_visible > self.options.length() {
      self.options.length()
    } else {
      start_idx + self.max_visible
    }

    // Build dropdown items
    for i = start_idx; i < end_idx; i = i + 1 {
      let fn_val = self.display_fn
      let item_text = fn_val(self.options[i])
      let is_selected = match self.selected.val {
        Some(idx) => idx == i
        None => false
      }
      let is_hovered = i == self.hover_index

      // Prefix for visual indication
      let prefix = if is_selected {
        "✓ "
      } else if is_hovered {
        "> "
      } else {
        "  "
      }
      let bg_color = if is_hovered {
        Some(self.style.hover_bg)
      } else if is_selected {
        Some(self.style.selected_bg)
      } else {
        None
      }
      let mut item_view = @view.View::text(
        prefix + item_text,
        color=self.style.text_color,
      ).width(box_width - 2.0) // Match dropdown width minus border
      match bg_color {
        Some(bg) => item_view = item_view.background(bg)
        None => ()
      }
      // Attach per-item event handler for hover/click and keyboard navigation
      // Capture index for closure
      let idx = i
      dropdown_items.push(item_view.on_event(fn(ev) { self.handle_item_event(idx, ev) }))
    }

    // Create dropdown container - inline for now until absolute positioning is fixed
    let dropdown = @view.View::container_views(dropdown_items)
      .direction(@view.Direction::Column)
      .border(self.style.dropdown_border, color=self.style.border_color)
      .background(@core.rgb(20, 20, 30)) // Slightly lighter than pure black
      .width(box_width) // Match select box width
      .margin_top(0.0) // No gap between select and dropdown

    // Combine select box with dropdown vertically
    let container = @view.View::container_views([select_box, dropdown])
      .direction(@view.Direction::Column) // Stack vertically
      .spacing(0.0) // No spacing between them

    // Apply ID and event handlers to container
    let mut final_container = container
    match self.id {
      Some(i) => final_container = final_container.id(i)
      None => ()
    }
    final_container.on_event(fn(ev) { self.handle_event(ev) })
  } else {
    // Closed state - just the select box
    let mut final_select_box = select_box
      .on_event(fn(ev) { self.handle_event(ev) })

    // Apply ID if provided
    match self.id {
      Some(i) => final_select_box = final_select_box.id(i)
      None => ()
    }
    final_select_box
  }
}

///|
pub impl[T] @view.Component for Select[T] with handle_event(self, event) {
  match event {
    @events.Event::Key(key) =>
      match key {
        @ffi.KeyEvent::ArrowUp => self.move_up()
        @ffi.KeyEvent::ArrowDown =>
          if not(self.is_open) {
            self.is_open = true
            true
          } else {
            self.move_down()
          }
        @ffi.KeyEvent::Enter | @ffi.KeyEvent::Char(32) => { // 32 = space
          if self.is_open {
            self.select_current()
          } else {
            self.is_open = true
          }
          true
        }
        @ffi.KeyEvent::Escape =>
          if self.is_open {
            self.is_open = false
            true
          } else {
            false
          }
        _ => false
      }
    @events.Event::KeyMod(key, _mods) =>
      match key {
        @ffi.KeyEvent::ArrowUp => self.move_up()
        @ffi.KeyEvent::ArrowDown =>
          if not(self.is_open) {
            self.is_open = true
            true
          } else {
            self.move_down()
          }
        @ffi.KeyEvent::Enter | @ffi.KeyEvent::Char(32) => { // 32 = space
          if self.is_open {
            self.select_current()
          } else {
            self.is_open = true
          }
          true
        }
        @ffi.KeyEvent::Escape =>
          if self.is_open {
            self.is_open = false
            true
          } else {
            false
          }
        _ => false
      }
    @events.Event::Mouse(mouse_event) =>
      match mouse_event.action {
        @events.MouseAction::Click => {
          // Toggle dropdown on click
          self.is_open = not(self.is_open)
          true
        }
        _ => false
      }
    _ => false
  }
}

///|
pub impl[T] @view.Component for Select[T] with is_focusable(_self) {
  true
}
