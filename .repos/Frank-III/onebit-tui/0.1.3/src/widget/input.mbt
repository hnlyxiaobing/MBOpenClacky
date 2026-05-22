///|
/// TextInput widget - for text entry
pub struct TextInput {
  value : Ref[String]
  mut placeholder : String
  mut width : Double
  style : InputStyle
  mut id : Int?
  // caret position in character units (0..=len)
  mut cursor : Int
}

///|
pub struct InputStyle {
  border : @view.BorderStyle
  border_color : @core.Color
  text_color : @core.Color
  placeholder_color : @core.Color
}

///|
/// Create a new text input
pub fn TextInput::new(value : Ref[String]) -> TextInput {
  {
    value,
    placeholder: "Type here...",
    width: 30.0,
    style: InputStyle::default(),
    id: None,
    cursor: 0,
  }
}

///|
/// Create an empty input (uncontrolled), internal state retained on instance
pub fn TextInput::empty() -> TextInput {
  TextInput::new(Ref::new(""))
}

///|
/// Replace value (Unit-returning; cascade with ..)
pub fn TextInput::set_value(self : TextInput, v : String) -> Unit {
  self.value.val = v
  // Reset cursor to end of new value
  self.cursor = str_char_len(v)
}

///|
/// Set placeholder text
pub fn TextInput::placeholder(self : TextInput, text : String) -> TextInput {
  self.placeholder = text
  self
}

///|
/// Set width
pub fn TextInput::width(self : TextInput, w : Double) -> TextInput {
  self.width = w
  self
}

///|
/// Assign a stable ID for focus/dispatch across rebuilds
pub fn TextInput::with_id(self : TextInput, id : Int) -> TextInput {
  self.id = Some(id)
  self
}

// Input styles

///|
pub fn InputStyle::default() -> InputStyle {
  {
    border: @view.BorderStyle::Single,
    border_color: @core.Color::Gray,
    text_color: @core.Color::White,
    placeholder_color: @core.Color::Gray,
  }
}

// Implement Component trait

///|
pub impl @view.Component for TextInput with render(self) {
  let display_text = if self.value.val == "" { self.placeholder } else { self.value.val }
  let text_color = if self.value.val == "" {
    self.style.placeholder_color
  } else {
    self.style.text_color
  }
  let mut view = @view.View::text(display_text, color=text_color)
    .width(self.width)
    .padding(1.0)
    .height(3.0)
    .border(self.style.border)
    .focused_border_color(@core.Color::Cyan)
    .overflow_y(@view.Overflow::Hidden)
    .focusable()
    .caret_col(self.cursor)
    .on_event(fn(ev) { self.handle_event(ev) })
  // Apply stable id if provided
  match self.id {
    Some(i) => view = view.id(i)
    None => ()
  }
  view
}

///|
pub impl @view.Component for TextInput with handle_event(self, event) {
  match event {
    @events.Event::Key(key) => {
      match key {
        @ffi.KeyEvent::Char(c) => self.handle_char(c)
        @ffi.KeyEvent::Backspace => self.backspace()
        @ffi.KeyEvent::Delete => self.delete_at_cursor()
        @ffi.KeyEvent::ArrowLeft => self.move_left()
        @ffi.KeyEvent::ArrowRight => self.move_right()
        @ffi.KeyEvent::Home => { self.cursor = 0; true }
        @ffi.KeyEvent::End => { self.cursor = str_char_len(self.value.val); true }
        _ => false
      }
    }
    @events.Event::KeyMod(key, mods) => {
      match key {
        @ffi.KeyEvent::ArrowLeft => {
          if mods.ctrl || mods.alt { self.move_word_left() } else { self.move_left() }
        }
        @ffi.KeyEvent::ArrowRight => {
          if mods.ctrl || mods.alt { self.move_word_right() } else { self.move_right() }
        }
        @ffi.KeyEvent::Home => { self.cursor = 0; true }
        @ffi.KeyEvent::End => { self.cursor = str_char_len(self.value.val); true }
        @ffi.KeyEvent::Backspace => self.backspace()
        @ffi.KeyEvent::Delete => self.delete_at_cursor()
        @ffi.KeyEvent::Char(c) => self.handle_char(c)
        _ => false
      }
    }
    @events.Event::Paste(text) => {
      // Insert entire pasted string at cursor position
      // naive char iteration preserves Unicode correctness via get_char
      let total = text.length()
      let mut any = false
      for i = 0; i < total; i = i + 1 {
        match text.get_char(i) {
          Some(ch) => {
            let code = ch.to_int()
            let _ = self.insert_char(code)
            any = true
          }
          None => break
        }
      }
      any
    }
    // Ignore focus/mouse events here; visual focus is handled by View
    _ => false
  }
}

///|
pub impl @view.Component for TextInput with is_focusable(_self) {
  true
}

// ----- helpers: string editing in character units -----

fn str_char_len(s : String) -> Int {
  let mut count = 0
  let total = s.length()
  for i = 0; i < total; i = i + 1 {
    match s.get_char(i) {
      Some(_) => count = count + 1
      None => break
    }
  }
  count
}

fn string_to_chars(s : String) -> Array[Char] {
  let chars : Array[Char] = []
  let total = s.length()
  for i = 0; i < total; i = i + 1 {
    match s.get_char(i) {
      Some(c) => chars.push(c)
      None => break
    }
  }
  chars
}

fn chars_to_string(chars : Array[Char]) -> String {
  String::from_array(chars)
}

fn clamp_cursor(self : TextInput) -> Unit {
  let len = str_char_len(self.value.val)
  if self.cursor < 0 { self.cursor = 0 }
  if self.cursor > len { self.cursor = len }
}

pub fn TextInput::insert_char(self : TextInput, code : Int) -> Bool {
  let ch = code.to_char().unwrap_or(' ')
  let chars = string_to_chars(self.value.val)
  let new_chars : Array[Char] = []
  let len = chars.length()
  let pos = if self.cursor < 0 { 0 } else if self.cursor > len { len } else { self.cursor }
  for i = 0; i < pos; i = i + 1 { new_chars.push(chars[i]) }
  new_chars.push(ch)
  for i = pos; i < len; i = i + 1 { new_chars.push(chars[i]) }
  self.value.val = chars_to_string(new_chars)
  self.cursor = pos + 1
  true
}

pub fn TextInput::backspace(self : TextInput) -> Bool {
  let chars = string_to_chars(self.value.val)
  let len = chars.length()
  if len == 0 { return true }
  if self.cursor <= 0 {
    // delete last char
    if len > 0 {
      let new_chars : Array[Char] = []
      for i = 0; i < len - 1; i = i + 1 { new_chars.push(chars[i]) }
      self.value.val = chars_to_string(new_chars)
      self.cursor = 0
    }
    return true
  }
  let pos = if self.cursor > len { len } else { self.cursor }
  let new_chars : Array[Char] = []
  for i = 0; i < pos - 1; i = i + 1 { new_chars.push(chars[i]) }
  for i = pos; i < len; i = i + 1 { new_chars.push(chars[i]) }
  self.value.val = chars_to_string(new_chars)
  self.cursor = pos - 1
  true
}

pub fn TextInput::delete_at_cursor(self : TextInput) -> Bool {
  let chars = string_to_chars(self.value.val)
  let len = chars.length()
  if len == 0 { return true }
  let pos = if self.cursor < 0 { 0 } else if self.cursor >= len { len } else { self.cursor }
  if pos >= len { return true }
  let new_chars : Array[Char] = []
  for i = 0; i < pos; i = i + 1 { new_chars.push(chars[i]) }
  for i = pos + 1; i < len; i = i + 1 { new_chars.push(chars[i]) }
  self.value.val = chars_to_string(new_chars)
  self.cursor = pos
  true
}

pub fn TextInput::move_left(self : TextInput) -> Bool {
  if self.cursor > 0 { self.cursor = self.cursor - 1 }
  true
}

pub fn TextInput::move_right(self : TextInput) -> Bool {
  let len = str_char_len(self.value.val)
  if self.cursor < len { self.cursor = self.cursor + 1 }
  true
}

// --- extended key behaviors ---

pub fn TextInput::handle_char(self : TextInput, code : Int) -> Bool {
  // Control characters (1..26 typical)
  match code {
    1 => { // Ctrl-A -> Home
      self.cursor = 0
      true
    }
    5 => { // Ctrl-E -> End
      self.cursor = str_char_len(self.value.val)
      true
    }
    2 => self.move_left() // Ctrl-B
    6 => self.move_right() // Ctrl-F
    4 => self.delete_at_cursor() // Ctrl-D
    8 => self.backspace() // Ctrl-H (often Backspace)
    11 => { // Ctrl-K -> delete to end
      self.delete_to_end()
      true
    }
    21 => { // Ctrl-U -> delete to start
      self.delete_to_start()
      true
    }
    23 => { // Ctrl-W -> delete previous word
      self.delete_prev_word()
      true
    }
    _ => {
      // Printable ASCII range; ignore other control bytes
      if code >= 32 && code != 127 {
        self.insert_char(code)
      } else {
        false
      }
    }
  }
}

fn is_space(c : Char) -> Bool { c == ' ' || c == '\t' }

pub fn TextInput::delete_to_start(self : TextInput) -> Unit {
  let chars = string_to_chars(self.value.val)
  let pos = if self.cursor < 0 { 0 } else if self.cursor > chars.length() { chars.length() } else { self.cursor }
  let new_chars : Array[Char] = []
  for i = pos; i < chars.length(); i = i + 1 { new_chars.push(chars[i]) }
  self.value.val = chars_to_string(new_chars)
  self.cursor = 0
}

pub fn TextInput::delete_to_end(self : TextInput) -> Unit {
  let chars = string_to_chars(self.value.val)
  let pos = if self.cursor < 0 { 0 } else if self.cursor > chars.length() { chars.length() } else { self.cursor }
  let new_chars : Array[Char] = []
  for i = 0; i < pos; i = i + 1 { new_chars.push(chars[i]) }
  self.value.val = chars_to_string(new_chars)
}

pub fn TextInput::delete_prev_word(self : TextInput) -> Unit {
  let chars = string_to_chars(self.value.val)
  let len = chars.length()
  let mut pos = if self.cursor < 0 { 0 } else if self.cursor > len { len } else { self.cursor }
  // skip any spaces left of cursor
  while pos > 0 && is_space(chars[pos - 1]) { pos = pos - 1 }
  // skip the word characters
  while pos > 0 && !is_space(chars[pos - 1]) { pos = pos - 1 }
  // delete [pos, cursor)
  let new_chars : Array[Char] = []
  for i = 0; i < pos; i = i + 1 { new_chars.push(chars[i]) }
  let old_cursor = if self.cursor > len { len } else { self.cursor }
  for i = old_cursor; i < len; i = i + 1 { new_chars.push(chars[i]) }
  self.value.val = chars_to_string(new_chars)
  self.cursor = pos
}

pub fn TextInput::move_word_left(self : TextInput) -> Bool {
  let chars = string_to_chars(self.value.val)
  let len = chars.length()
  let mut pos = if self.cursor < 0 { 0 } else if self.cursor > len { len } else { self.cursor }
  if pos == 0 { return true }
  while pos > 0 && is_space(chars[pos - 1]) { pos = pos - 1 }
  while pos > 0 && !is_space(chars[pos - 1]) { pos = pos - 1 }
  self.cursor = pos
  true
}

pub fn TextInput::move_word_right(self : TextInput) -> Bool {
  let chars = string_to_chars(self.value.val)
  let len = chars.length()
  let mut pos = if self.cursor < 0 { 0 } else if self.cursor > len { len } else { self.cursor }
  if pos >= len { return true }
  while pos < len && is_space(chars[pos]) { pos = pos + 1 }
  while pos < len && !is_space(chars[pos]) { pos = pos + 1 }
  self.cursor = pos
  true
}
