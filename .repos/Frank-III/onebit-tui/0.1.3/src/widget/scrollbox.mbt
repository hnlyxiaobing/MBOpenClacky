///|
/// ScrollBox widget - renders a vertical window over a list of components
pub struct ScrollBox {
  mut items : Array[&@view.Component]
  visible_rows : Int
  offset : Ref[Int]
  mut title : String?
  mut border : @view.BorderStyle
  mut padding : Double
}

///|
pub fn ScrollBox::new(
  items : Array[&@view.Component],
  visible_rows? : Int = 10,
  offset? : Ref[Int] = Ref::new(0),
) -> ScrollBox {
  {
    items,
    visible_rows,
    offset,
    title: None,
    border: @view.BorderStyle::Single,
    padding: 0.0,
  }
}

///|
/// Create an empty ScrollBox with internal state (uncontrolled)
pub fn ScrollBox::empty(visible_rows? : Int = 10) -> ScrollBox {
  {
    items: [],
    visible_rows,
    offset: Ref::new(0),
    title: None,
    border: @view.BorderStyle::Single,
    padding: 0.0,
  }
}

///|
/// Replace items (Unit-returning; chain with cascade operator ..)
pub fn ScrollBox::set_items(self : ScrollBox, items : Array[&@view.Component]) -> Unit {
  self.items = items
}

///|
/// Get current offset (for display/debug)
pub fn ScrollBox::get_offset(self : ScrollBox) -> Int {
  self.offset.val
}

///|
/// Scroll by delta (positive down, negative up)
pub fn ScrollBox::scroll_by(self : ScrollBox, delta : Int) -> Unit {
  let total = self.items.length()
  let max_offset = if total > self.visible_rows { total - self.visible_rows } else { 0 }
  let mut next = self.offset.val + delta
  if next < 0 { next = 0 }
  if next > max_offset { next = max_offset }
  self.offset.val = next
}

///|
/// Scroll to absolute position
pub fn ScrollBox::scroll_to(self : ScrollBox, pos : Int) -> Unit {
  let total = self.items.length()
  let max_offset = if total > self.visible_rows { total - self.visible_rows } else { 0 }
  let mut next = pos
  if next < 0 { next = 0 }
  if next > max_offset { next = max_offset }
  self.offset.val = next
}

///|
pub fn ScrollBox::title(self : ScrollBox, text : String) -> ScrollBox {
  self.title = Some(text)
  self
}

///|
pub fn ScrollBox::border(
  self : ScrollBox,
  style : @view.BorderStyle,
) -> ScrollBox {
  self.border = style
  self
}

///|
pub fn ScrollBox::padding(self : ScrollBox, p : Double) -> ScrollBox {
  self.padding = p
  self
}

///|
pub impl @view.Component for ScrollBox with render(self) {
  // Clamp offset
  let total = self.items.length()
  if total == 0 {
    let t = match self.title {
      Some(t) => t
      None => ""
    }
    return @view.View::empty().border(self.border).title(t)
  }
  let max_offset = if total > self.visible_rows {
    total - self.visible_rows
  } else {
    0
  }
  if self.offset.val < 0 {
    self.offset.val = 0
  }
  if self.offset.val > max_offset {
    self.offset.val = max_offset
  }
  let start = self.offset.val
  let end = if start + self.visible_rows > total {
    total
  } else {
    start + self.visible_rows
  }
  let views = []
  for i = start; i < end; i = i + 1 {
    views.push(self.items[i].render())
  }
  let mut container = @view.View::container_views(views)
    .direction(@view.Direction::Column)
    .padding(self.padding)
    .border(self.border)
    .focused_border_color(@core.Color::Cyan)
    .height(self.visible_rows.to_double() + 2.0) // approx height incl. border
    .overflow_y(@view.Overflow::Scroll)
    .focusable()
    .on_event(fn(ev) { self.handle_event(ev) })
  match self.title {
    Some(t) => {
      container = container.title(t)
      ()
    }
    None => ()
  }
  container
}

///|
// Key handling is attached via .on_key on the view; no duplicate handle_event needed.

///|
pub impl @view.Component for ScrollBox with is_focusable(_self) {
  true
}

///|
pub impl @view.Component for ScrollBox with handle_event(self, event) {
  match event {
    @events.Event::Key(key) =>
      self.handle_key(key, self.items.length())
    @events.Event::KeyMod(key, _mods) =>
      self.handle_key(key, self.items.length())
    _ => false
  }
}

///|
/// Shared key handling (view + trait)
fn ScrollBox::handle_key(self : ScrollBox, key : @ffi.KeyEvent, total : Int) -> Bool {
  match key {
    @ffi.KeyEvent::ArrowUp => { self.scroll_by(-1); true }
    @ffi.KeyEvent::ArrowDown => { self.scroll_by(1); true }
    @ffi.KeyEvent::PageUp => { self.scroll_by(-self.visible_rows); true }
    @ffi.KeyEvent::PageDown => { self.scroll_by(self.visible_rows); true }
    @ffi.KeyEvent::Home => { self.scroll_to(0); true }
    @ffi.KeyEvent::End => {
      let mo = if total > self.visible_rows { total - self.visible_rows } else { 0 }
      self.scroll_to(mo)
      true
    }
    _ => false
  }
}
