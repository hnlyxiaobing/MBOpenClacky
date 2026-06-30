///|
/// TabSelect Widget - Horizontal tab selector like browser tabs
pub struct TabSelect[T] {
  tabs : Array[T]
  selected_index : Ref[Int]
  display_fn : (T) -> String
  mut on_change : (Int, T) -> Unit
  mut style : TabSelectStyle
  mut id : Int?
}

///|
pub struct TabSelectStyle {
  active_fg : @core.Color
  active_bg : @core.Color
  inactive_fg : @core.Color
  inactive_bg : @core.Color?
  border : @view.BorderStyle?
  separator : String // Character(s) between tabs
}

///|
/// Create a new tab select widget
pub fn[T] TabSelect::new(
  tabs : Array[T],
  display_fn : (T) -> String,
  selected? : Ref[Int] = Ref::new(0),
) -> TabSelect[T] {
  {
    tabs,
    selected_index: selected,
    display_fn,
    on_change: fn(_index, _tab) {  },
    style: TabSelectStyle::default(),
    id: None,
  }
}

///|
/// Set change handler
pub fn[T] TabSelect::on_change(
  self : TabSelect[T],
  handler : (Int, T) -> Unit,
) -> TabSelect[T] {
  self.on_change = handler
  self
}

///|
/// Set style
pub fn[T] TabSelect::with_style(
  self : TabSelect[T],
  style : TabSelectStyle,
) -> TabSelect[T] {
  self.style = style
  self
}

///|
/// Assign a stable ID for focus management
pub fn[T] TabSelect::with_id(self : TabSelect[T], id : Int) -> TabSelect[T] {
  self.id = Some(id)
  self
}

///|
/// Default tab select style
pub fn TabSelectStyle::default() -> TabSelectStyle {
  {
    active_fg: @core.Color::Black,
    active_bg: @core.Color::Cyan,
    inactive_fg: @core.Color::White,
    inactive_bg: None,
    border: Some(@view.BorderStyle::Single),
    separator: "│", // Vertical bar
  }
}

///|
/// Navigate to previous tab
fn[T] TabSelect::select_previous(self : TabSelect[T]) -> Bool {
  if self.selected_index.val > 0 {
    self.selected_index.val = self.selected_index.val - 1
    let tab = self.tabs[self.selected_index.val]
    let handler = self.on_change
    handler(self.selected_index.val, tab)
    true
  } else {
    false
  }
}

///|
/// Navigate to next tab
fn[T] TabSelect::select_next(self : TabSelect[T]) -> Bool {
  if self.selected_index.val < self.tabs.length() - 1 {
    self.selected_index.val = self.selected_index.val + 1
    let tab = self.tabs[self.selected_index.val]
    let handler = self.on_change
    handler(self.selected_index.val, tab)
    true
  } else {
    false
  }
}

///|
/// Select tab by index
pub fn[T] TabSelect::select_index(self : TabSelect[T], index : Int) -> Bool {
  if index >= 0 && index < self.tabs.length() {
    self.selected_index.val = index
    let tab = self.tabs[index]
    let handler = self.on_change
    handler(index, tab)
    true
  } else {
    false
  }
}

///|
/// Implement Component trait for TabSelect
pub impl[T] @view.Component for TabSelect[T] with render(self) {
  if self.tabs.length() == 0 {
    return @view.View::empty()
  }

  // Build tab views
  let tab_views : Array[@view.View] = []
  for i = 0; i < self.tabs.length(); i = i + 1 {
    let fn_val = self.display_fn
    let tab_text = fn_val(self.tabs[i])
    let is_selected = i == self.selected_index.val

    // Create tab with appropriate styling
    let mut tab_view = if is_selected {
      @view.View::text(" \{tab_text} ", color=self.style.active_fg)
        .background(self.style.active_bg)
        .padding(1.0)
    } else {
      let mut v = @view.View::text(
        " \{tab_text} ",
        color=self.style.inactive_fg,
      ).padding(1.0)
      match self.style.inactive_bg {
        Some(bg) => v = v.background(bg)
        None => ()
      }
      v
    }
    // Handle per-tab mouse/key events: click selects the tab; Up/Down/Left/Right navigate
    // Capture index per-iteration to avoid closure capturing the loop variable by reference
    let idx = i
    tab_view = tab_view.on_event(fn(ev) { self.handle_tab_event(idx, ev) })
    tab_views.push(tab_view)

    // Add separator between tabs (except after last)
    if i < self.tabs.length() - 1 && self.style.separator != "" {
      tab_views.push(
        @view.View::text(self.style.separator, color=@core.Color::Gray),
      )
    }
  }

  // Create container with tabs
  let mut container = @view.View::container_views(tab_views)
    .direction(@view.Direction::Row)
    .align_self(@types.Align::FlexStart)
    .focusable()
    .on_event(fn(ev) { self.handle_event(ev) })

  // Apply border if specified
  match self.style.border {
    Some(border_style) =>
      container = container.border(border_style, color=@core.Color::White)
    None => ()
  }

  // Apply ID if provided
  match self.id {
    Some(id) => container.id(id)
    None => container
  }
}

///|
pub impl[T] @view.Component for TabSelect[T] with handle_event(self, event) {
  match event {
    @events.Event::Key(key) =>
      match key {
        @ffi.KeyEvent::ArrowLeft => self.select_previous()
        @ffi.KeyEvent::ArrowRight => self.select_next()
        @ffi.KeyEvent::ArrowUp => self.select_previous()
        @ffi.KeyEvent::ArrowDown => self.select_next()
        @ffi.KeyEvent::Home => self.select_index(0)
        @ffi.KeyEvent::End => self.select_index(self.tabs.length() - 1)
        _ => false
      }
    @events.Event::KeyMod(key, _mods) =>
      match key {
        @ffi.KeyEvent::ArrowLeft => self.select_previous()
        @ffi.KeyEvent::ArrowRight => self.select_next()
        @ffi.KeyEvent::ArrowUp => self.select_previous()
        @ffi.KeyEvent::ArrowDown => self.select_next()
        @ffi.KeyEvent::Home => self.select_index(0)
        @ffi.KeyEvent::End => self.select_index(self.tabs.length() - 1)
        _ => false
      }
    @events.Event::Mouse(mouse_event) =>
      match mouse_event.action {
        @events.MouseAction::Click =>
          // TODO: Calculate which tab was clicked based on position
          // For now, just cycle through tabs
          if self.selected_index.val < self.tabs.length() - 1 {
            self.select_next()
          } else {
            self.select_index(0)
          }
        _ => false
      }
    _ => false
  }
}

///|
/// Handle per-tab events for direct dispatch
fn[T] TabSelect::handle_tab_event(self : TabSelect[T], index : Int, event : @events.Event) -> Bool {
  match event {
    @events.Event::Mouse(mouse_event) =>
      match mouse_event.action {
        @events.MouseAction::Click => self.select_index(index)
        _ => false
      }
    @events.Event::Key(key) =>
      match key {
        @ffi.KeyEvent::ArrowLeft => self.select_previous()
        @ffi.KeyEvent::ArrowRight => self.select_next()
        @ffi.KeyEvent::ArrowUp => self.select_previous()
        @ffi.KeyEvent::ArrowDown => self.select_next()
        @ffi.KeyEvent::Home => self.select_index(0)
        @ffi.KeyEvent::End => self.select_index(self.tabs.length() - 1)
        _ => false
      }
    @events.Event::KeyMod(key, _mods) =>
      match key {
        @ffi.KeyEvent::ArrowLeft => self.select_previous()
        @ffi.KeyEvent::ArrowRight => self.select_next()
        @ffi.KeyEvent::ArrowUp => self.select_previous()
        @ffi.KeyEvent::ArrowDown => self.select_next()
        @ffi.KeyEvent::Home => self.select_index(0)
        @ffi.KeyEvent::End => self.select_index(self.tabs.length() - 1)
        _ => false
      }
    _ => false
  }
}

///|
pub impl[T] @view.Component for TabSelect[T] with is_focusable(_self) {
  true
}
