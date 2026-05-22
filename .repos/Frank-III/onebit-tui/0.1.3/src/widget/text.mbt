///|
/// Text widget - displays text with optional styling
pub struct Text {
  content : String
  style : TextStyle
}

///|
pub struct TextStyle {
  mut color : @core.Color
  background : @core.Color?
}

///|
/// Create a text widget
pub fn Text::new(content : String) -> Text {
  { content, style: TextStyle::default() }
}

///|
/// Create a heading text (larger/brighter)
pub fn Text::heading(content : String) -> Text {
  { content, style: TextStyle::heading() }
}

///|
/// Create body text (normal)
pub fn Text::body(content : String) -> Text {
  { content, style: TextStyle::body() }
}

///|
/// Create caption text (smaller/dimmer)
pub fn Text::caption(content : String) -> Text {
  { content, style: TextStyle::caption() }
}

///|
/// Set color
pub fn Text::color(self : Text, color : @core.Color) -> Text {
  self.style.color = color
  self
}

// Text styles

///|
pub fn TextStyle::default() -> TextStyle {
  { color: @core.Color::White, background: None }
}

///|
pub fn TextStyle::heading() -> TextStyle {
  { color: @core.Color::BrightWhite, background: None }
}

///|
pub fn TextStyle::body() -> TextStyle {
  { color: @core.Color::White, background: None }
}

///|
pub fn TextStyle::caption() -> TextStyle {
  { color: @core.Color::Gray, background: None }
}

// Implement Component trait for Text

///|
pub impl @view.Component for Text with render(self) {
  let view = @view.View::text(self.content, color=self.style.color)
  match self.style.background {
    Some(bg) => view.background(bg)
    None => view
  }
}

///|
pub impl @view.Component for Text with handle_event(_self, _event) {
  false // Text doesn't handle input
}

///|
pub impl @view.Component for Text with is_focusable(_self) {
  false
}
