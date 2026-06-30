///|
/// List Widget - Scrollable list with item selection
pub struct List[T] {
  mut items : Array[T]
  mut selected_index : Int
  mut scroll_offset : Int
  mut visible_items : Int
  item_renderer : (T, Bool) -> String // (item, is_selected) -> display_string
  mut on_select : (T, Int) -> Unit // (item, index) -> Unit
  mut style : ListStyle
}

///|
pub struct ListStyle {
  selected_fg : @core.Color
  selected_bg : @core.Color?
  normal_fg : @core.Color
  border : @view.BorderStyle?
  max_height : Double? // Optional max height for scrolling
}

///|
/// Create a new list
pub fn[T] List::new(
  items : Array[T],
  item_renderer : (T, Bool) -> String,
) -> List[T] {
  {
    items,
    selected_index: 0,
    scroll_offset: 0,
    visible_items: 10,
    item_renderer,
    on_select: fn( // Default visible items
      _item,
      _index,
    ) {

    },
    style: ListStyle::default(),
  }
}

///|
/// Create an empty list (stateful instance), set items later
pub fn[T] List::empty(item_renderer : (T, Bool) -> String) -> List[T] {
  List::new([], item_renderer)
}

///|
/// Replace items (Unit-returning; use cascade ..)
pub fn[T] List::set_items(self : List[T], items : Array[T]) -> Unit {
  self.items = items
  // Clamp selection and scroll
  if self.selected_index >= self.items.length() {
    self.selected_index = maximum(0, self.items.length() - 1)
  }
  let max_offset = maximum(0, self.items.length() - self.visible_items)
  if self.scroll_offset > max_offset {
    self.scroll_offset = max_offset
  }
}

///|
/// Set the selection handler
pub fn[T] List::on_select(
  self : List[T],
  handler : (T, Int) -> Unit,
) -> List[T] {
  self.on_select = handler
  self
}

///|
/// Set visible items count
pub fn[T] List::visible_items(self : List[T], count : Int) -> List[T] {
  self.visible_items = count
  self
}

///|
/// Set the selected index
pub fn[T] List::selected(self : List[T], index : Int) -> List[T] {
  self.selected_index = index
  // Adjust scroll offset if needed
  if index < self.scroll_offset {
    self.scroll_offset = index
  } else if index >= self.scroll_offset + self.visible_items {
    self.scroll_offset = index - self.visible_items + 1
  }
  self
}

///|
/// Set the style
pub fn[T] List::with_style(self : List[T], style : ListStyle) -> List[T] {
  self.style = style
  self
}

///|
/// Default list style
pub fn ListStyle::default() -> ListStyle {
  {
    selected_fg: @core.Color::Black,
    selected_bg: Some(@core.Color::Cyan),
    normal_fg: @core.Color::White,
    border: Some(@view.BorderStyle::Single),
    max_height: Some(15.0), // Optional max height
  }
}

///|
/// Move selection up
pub fn[T] List::select_previous(self : List[T]) -> Bool {
  if self.selected_index > 0 {
    self.selected_index = self.selected_index - 1

    // Adjust scroll if needed
    if self.selected_index < self.scroll_offset {
      self.scroll_offset = self.selected_index
    }

    // Trigger selection callback
    if self.selected_index < self.items.length() {
      let item = self.items[self.selected_index]
      (self.on_select)(item, self.selected_index)
    }
    true
  } else {
    false
  }
}

///|
/// Move selection down
pub fn[T] List::select_next(self : List[T]) -> Bool {
  if self.selected_index < self.items.length() - 1 {
    self.selected_index = self.selected_index + 1

    // Adjust scroll if needed
    if self.selected_index >= self.scroll_offset + self.visible_items {
      self.scroll_offset = self.selected_index - self.visible_items + 1
    }

    // Trigger selection callback
    let item = self.items[self.selected_index]
    (self.on_select)(item, self.selected_index)
    true
  } else {
    false
  }
}

///|
/// Get selected item
pub fn[T] List::get_selected(self : List[T]) -> T? {
  if self.selected_index < self.items.length() {
    Some(self.items[self.selected_index])
  } else {
    None
  }
}

///|
/// Implement Component trait
pub impl[T] @view.Component for List[T] with render(self) {
  // Calculate visible range
  let end_index = minimum(
    self.scroll_offset + self.visible_items,
    self.items.length(),
  )

  // Render visible items
  let item_views : Array[@view.View] = []
  for i = self.scroll_offset; i < end_index; i = i + 1 {
    let item = self.items[i]
    let is_selected = i == self.selected_index
    let text = (self.item_renderer)(item, is_selected)
    let item_view = if is_selected {
      @view.View::text(text, color=self.style.selected_fg)
      .background(self.style.selected_bg.unwrap_or(@core.Color::Blue))
      .flex(1.0) // Use flex instead of fixed width
    } else {
      @view.View::text(text, color=self.style.normal_fg).flex(1.0) // Use flex instead of fixed width
    }
    item_views.push(item_view)
  }

  // Add scroll indicators if needed
  if self.scroll_offset > 0 {
    item_views.insert(
      0,
      @view.View::text("↑ More items above", color=@core.Color::Gray),
    )
  }
  if end_index < self.items.length() {
    item_views.push(
      @view.View::text("↓ More items below", color=@core.Color::Gray),
    )
  }

  // Create container and attach key handling here
  let mut container = @view.View::container_views(item_views)
    .direction(@view.Direction::Column)
    .padding(1.0) // Add padding inside the border
    .flex(1.0) // Make it grow to fill available space
    .focusable()
    .on_event(fn(ev) { self.handle_event(ev) })

  // Apply max height if specified
  container = match self.style.max_height {
    Some(max_h) => container.height(max_h)
    None => container
  }

  // Add border if specified with focus color
  match self.style.border {
    Some(border) =>
      container.border(border).focused_border_color(@core.Color::Cyan)
    None => container
  }
}

///|
pub impl[T] @view.Component for List[T] with handle_event(self, event) {
  match event {
    @events.Event::Key(key) =>
      match key {
        @ffi.KeyEvent::ArrowUp => self.select_previous()
        @ffi.KeyEvent::ArrowDown => self.select_next()
        @ffi.KeyEvent::PageUp => {
          if self.visible_items > 0 {
            let new_index = maximum(0, self.selected_index - self.visible_items)
            let _ = self.selected(new_index)
            true
          } else { false }
        }
        @ffi.KeyEvent::PageDown => {
          if self.visible_items > 0 {
            let last = maximum(0, self.items.length() - 1)
            let new_index = minimum(last, self.selected_index + self.visible_items)
            let _ = self.selected(new_index)
            true
          } else { false }
        }
        @ffi.KeyEvent::Home => {
          if self.items.length() > 0 {
            self.selected_index = 0
            self.scroll_offset = 0
            let item = self.items[0]
            (self.on_select)(item, 0)
            true
          } else { false }
        }
        @ffi.KeyEvent::End => {
          let last = self.items.length() - 1
          if last >= 0 {
            self.selected_index = last
            self.scroll_offset = maximum(0, last - self.visible_items + 1)
            let item = self.items[last]
            (self.on_select)(item, last)
            true
          } else { false }
        }
        @ffi.KeyEvent::Enter =>
          match self.get_selected() {
            Some(item) => { (self.on_select)(item, self.selected_index); true }
            None => false
          }
        _ => false
      }
    @events.Event::KeyMod(key, _mods) =>
      match key {
        @ffi.KeyEvent::ArrowUp => self.select_previous()
        @ffi.KeyEvent::ArrowDown => self.select_next()
        @ffi.KeyEvent::PageUp => {
          if self.visible_items > 0 {
            let new_index = maximum(0, self.selected_index - self.visible_items)
            let _ = self.selected(new_index)
            true
          } else { false }
        }
        @ffi.KeyEvent::PageDown => {
          if self.visible_items > 0 {
            let last = maximum(0, self.items.length() - 1)
            let new_index = minimum(last, self.selected_index + self.visible_items)
            let _ = self.selected(new_index)
            true
          } else { false }
        }
        @ffi.KeyEvent::Home => {
          if self.items.length() > 0 {
            self.selected_index = 0
            self.scroll_offset = 0
            let item = self.items[0]
            (self.on_select)(item, 0)
            true
          } else { false }
        }
        @ffi.KeyEvent::End => {
          let last = self.items.length() - 1
          if last >= 0 {
            self.selected_index = last
            self.scroll_offset = maximum(0, last - self.visible_items + 1)
            let item = self.items[last]
            (self.on_select)(item, last)
            true
          } else { false }
        }
        @ffi.KeyEvent::Enter =>
          match self.get_selected() {
            Some(item) => { (self.on_select)(item, self.selected_index); true }
            None => false
          }
        _ => false
      }
    _ => false
  }
}

///|
pub impl[T] @view.Component for List[T] with is_focusable(_self) {
  true
}
