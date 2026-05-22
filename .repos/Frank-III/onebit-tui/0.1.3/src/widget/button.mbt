///|
/// Button widget - a clickable component with keyboard support
pub struct Button {
  label : String
  action : () -> Unit
  style : ButtonStyle
  mut id : Int?
}

///|
pub struct ButtonStyle {
  background : @core.Color?
  foreground : @core.Color
  border : @view.BorderStyle?
  padding : Double
}

///|
/// Create a new button
pub fn Button::new(label : String, action : () -> Unit) -> Button {
  { label, action, style: ButtonStyle::default(), id: None }
}

///|
/// Create a primary button (default style)
pub fn Button::primary(label : String, action : () -> Unit) -> Button {
  { label, action, style: ButtonStyle::primary(), id: None }
}

///|
/// Create a secondary button
pub fn Button::secondary(label : String, action : () -> Unit) -> Button {
  { label, action, style: ButtonStyle::secondary(), id: None }
}

///|
/// Create a danger button (red)
pub fn Button::danger(label : String, action : () -> Unit) -> Button {
  { label, action, style: ButtonStyle::danger(), id: None }
}

///|
/// Assign a stable ID for focus/dispatch across rebuilds
pub fn Button::with_id(self : Button, id : Int) -> Button {
  self.id = Some(id)
  self
}

// Button styles

///|
pub fn ButtonStyle::default() -> ButtonStyle {
  {
    background: None,
    foreground: @core.Color::Cyan,
    border: Some(@view.BorderStyle::Single),
    padding: 1.0,
  }
}

///|
pub fn ButtonStyle::primary() -> ButtonStyle {
  {
    background: Some(@core.Color::Blue),
    foreground: @core.Color::White,
    border: None,
    padding: 1.0,
  }
}

///|
pub fn ButtonStyle::secondary() -> ButtonStyle {
  {
    background: None,
    foreground: @core.Color::Gray,
    border: Some(@view.BorderStyle::Single),
    padding: 1.0,
  }
}

///|
pub fn ButtonStyle::danger() -> ButtonStyle {
  {
    background: Some(@core.Color::Red),
    foreground: @core.Color::White,
    border: None,
    padding: 1.0,
  }
}

// Implement Component trait for Button

///|
pub impl @view.Component for Button with render(self) {
  let mut view = @view.View::text(self.label, color=self.style.foreground)
    .padding(self.style.padding)
    .focusable()
    .on_event(fn(ev) { self.handle_event(ev) })
    .on_click(Some(fn(_, _) { (self.action)() }))

  // Apply border if present
  let _ = match self.style.border {
    Some(b) => view.border(b).focused_border_color(@core.Color::Cyan) // Add focus border color
    None => view
  }

  // Apply background if present
  let _ = match self.style.background {
    Some(bg) => view.background(bg)
    None => view
  }

  // Apply stable id if provided
  let _ = match self.id {
    Some(i) => view = view.id(i)
    None => ()
  }
  view
}

///|
pub impl @view.Component for Button with handle_event(self, event) {
  match event {
    @events.Event::Key(key) =>
      match key {
        @ffi.KeyEvent::Enter => {
          (self.action)()
          true
        }
        @ffi.KeyEvent::Char(32) => { // Space character
          (self.action)()
          true
        }
        _ => false
      }
    @events.Event::KeyMod(key, _mods) =>
      match key {
        @ffi.KeyEvent::Enter => { (self.action)(); true }
        @ffi.KeyEvent::Char(32) => { (self.action)(); true }
        _ => false
      }
    @events.Event::Mouse(mouse) =>
      match mouse.action {
        @events.MouseAction::Click => {
          (self.action)()
          true
        }
        _ => false
      }
    _ => false
  }
}

///|
pub impl @view.Component for Button with is_focusable(_self) {
  true
}
