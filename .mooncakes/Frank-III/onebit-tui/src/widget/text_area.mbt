///|
/// TextArea Widget - Multi-line text display with word wrapping
pub struct TextArea {
  text : Ref[String]
  mut width : Double
  mut height : Double
  mut wrap_mode : @ffi.WrapMode
  mut style : TextAreaStyle
  mut id : Int?
  mut scrollable : Bool
  scroll_offset : Ref[Int]  // Ref is already mutable, no need for mut
}

///|
pub struct TextAreaStyle {
  text_color : @core.Color
  background : @core.Color?
  border : @view.BorderStyle?
  padding : Double
}

///|
/// Create a new text area
pub fn TextArea::new(text : Ref[String]) -> TextArea {
  {
    text: text,
    width: 40.0,
    height: 10.0,
    wrap_mode: @ffi.WrapMode::Word,
    style: TextAreaStyle::default(),
    id: None,
    scrollable: true,
    scroll_offset: Ref::new(0),
  }
}

///|
/// Set dimensions
pub fn TextArea::size(self : TextArea, width : Double, height : Double) -> TextArea {
  self.width = width
  self.height = height
  self
}

///|
/// Set wrap mode
pub fn TextArea::wrap_mode(self : TextArea, mode : @ffi.WrapMode) -> TextArea {
  self.wrap_mode = mode
  self
}

///|
/// Set whether scrollable
pub fn TextArea::scrollable(self : TextArea, scrollable : Bool) -> TextArea {
  self.scrollable = scrollable
  self
}

///|
/// Set style
pub fn TextArea::with_style(self : TextArea, style : TextAreaStyle) -> TextArea {
  self.style = style
  self
}

///|
/// Assign a stable ID
pub fn TextArea::with_id(self : TextArea, id : Int) -> TextArea {
  self.id = Some(id)
  self
}

///|
/// Default text area style
pub fn TextAreaStyle::default() -> TextAreaStyle {
  {
    text_color: @core.Color::White,
    background: None,
    border: Some(@view.BorderStyle::Single),
    padding: 1.0,
  }
}

///|
/// Scroll up
fn TextArea::scroll_up(self : TextArea) -> Bool {
  if self.scroll_offset.val > 0 {
    self.scroll_offset.val = self.scroll_offset.val - 1
    true
  } else {
    false
  }
}

///|
/// Scroll down
fn TextArea::scroll_down(self : TextArea) -> Bool {
  // TODO: Calculate max scroll based on wrapped lines
  self.scroll_offset.val = self.scroll_offset.val + 1
  true
}

///|
/// Split text into lines considering wrap width
fn wrap_text(text : String, width : Int, mode : @ffi.WrapMode) -> Array[String] {
  if width <= 0 {
    return [text]
  }
  
  let lines : Array[String] = []
  
  // Iterate over lines split by newline
  text.split("\n").each(fn(line_view) {
    let line = line_view.to_string()
    if line.length() <= width {
      lines.push(line)
    } else {
      // Need to wrap this line
      match mode {
        @ffi.WrapMode::Char => {
          // Character wrap - break at exact width
          let mut start = 0
          while start < line.length() {
            let end = if start + width > line.length() {
              line.length()
            } else {
              start + width
            }
            // Use slice notation to extract substring
            let wrapped = try! line[:][start:end].to_string()
            lines.push(wrapped)
            start = end
          }
        }
        @ffi.WrapMode::Word => {
          // Word wrap - break at word boundaries
          let mut current_line = ""
          
          line.split(" ").each(fn(word_view) {
            let word = word_view.to_string()
            let test_line = if current_line == "" {
              word
            } else {
              current_line + " " + word
            }
            
            if test_line.length() <= width {
              current_line = test_line
            } else {
              if current_line != "" {
                lines.push(current_line)
                current_line = word
              } else {
                // Word is too long, break it at width
                let truncated = if word.length() > width {
                  try! word[:][0:width].to_string()
                } else {
                  word
                }
                lines.push(truncated)
                current_line = ""
              }
            }
          })
          
          if current_line != "" {
            lines.push(current_line)
          }
        }
      }
    }
  })
  
  lines
}

///|
/// Implement Component trait for TextArea
pub impl @view.Component for TextArea with render(self) {
  // Calculate inner width for wrapping
  let inner_width = self.width.to_int() - (self.style.padding * 2.0).to_int()
  let inner_height = self.height.to_int() - (self.style.padding * 2.0).to_int()
  
  // Wrap the text
  let wrapped_lines = wrap_text(self.text.val, inner_width - 2, self.wrap_mode)
  
  // Apply scrolling if needed
  let visible_lines = if self.scrollable && wrapped_lines.length() > inner_height {
    let start = self.scroll_offset.val
    let end = if start + inner_height > wrapped_lines.length() {
      wrapped_lines.length()
    } else {
      start + inner_height
    }
    
    let visible : Array[String] = []
    for i = start; i < end; i = i + 1 {
      visible.push(wrapped_lines[i])
    }
    visible
  } else {
    wrapped_lines
  }
  
  // Create text views for each line
  let line_views : Array[@view.View] = []
  for i = 0; i < visible_lines.length(); i = i + 1 {
    line_views.push(
      @view.View::text(visible_lines[i], color=self.style.text_color)
    )
  }
  
  // Add empty lines to fill height if needed
  let empty_lines = inner_height - visible_lines.length()
  if empty_lines > 0 {
    for i = 0; i < empty_lines; i = i + 1 {
      line_views.push(@view.View::text("", color=self.style.text_color))
    }
  }
  
  // Create container
  let mut container = @view.View::container_views(line_views)
    .direction(@view.Direction::Column)
    .width(self.width)
    .height(self.height)
    .padding(self.style.padding)
  
  // Apply background if specified
  match self.style.background {
    Some(bg) => container = container.background(bg)
    None => ()
  }
  
  // Apply border if specified
  match self.style.border {
    Some(border_style) => {
      container = container.border(border_style, color=@core.Color::White)
      
      // Add scroll indicator if scrollable
      if self.scrollable && wrapped_lines.length() > inner_height {
        let title = "[\{self.scroll_offset.val + 1}/\{wrapped_lines.length() - inner_height + 1}]"
        container = container.title(title).title_align(@view.TitleAlign::Right)
      }
    }
    None => ()
  }
  
  // Make focusable if scrollable
  if self.scrollable {
    container = container.focusable().on_event(fn(ev) { self.handle_event(ev) })
  }
  
  // Apply ID if provided
  match self.id {
    Some(id) => container.id(id)
    None => container
  }
}

///|
pub impl @view.Component for TextArea with handle_event(self, event) {
  if not(self.scrollable) { return false }
  match event {
    @events.Event::Key(key) =>
      match key {
        @ffi.KeyEvent::ArrowUp => self.scroll_up()
        @ffi.KeyEvent::ArrowDown => self.scroll_down()
        @ffi.KeyEvent::PageUp => {
          let raw = self.height.to_int() - (self.style.padding.to_int() * 2)
          let step = if raw / 2 < 1 { 1 } else { raw / 2 }
          for i = 0; i < step; i = i + 1 { let _ = self.scroll_up() }
          true
        }
        @ffi.KeyEvent::PageDown => {
          let raw = self.height.to_int() - (self.style.padding.to_int() * 2)
          let step = if raw / 2 < 1 { 1 } else { raw / 2 }
          for i = 0; i < step; i = i + 1 { let _ = self.scroll_down() }
          true
        }
        @ffi.KeyEvent::Home => { self.scroll_offset.val = 0; true }
        @ffi.KeyEvent::End => {
          // Max scroll is computed at render; here approximate by large scroll down
          for i = 0; i < 1000; i = i + 1 { let _ = self.scroll_down() }
          true
        }
        _ => false
      }
    @events.Event::KeyMod(key, _mods) =>
      match key {
        @ffi.KeyEvent::ArrowUp => self.scroll_up()
        @ffi.KeyEvent::ArrowDown => self.scroll_down()
        @ffi.KeyEvent::PageUp => {
          let raw = self.height.to_int() - (self.style.padding.to_int() * 2)
          let step = if raw / 2 < 1 { 1 } else { raw / 2 }
          for i = 0; i < step; i = i + 1 { let _ = self.scroll_up() }
          true
        }
        @ffi.KeyEvent::PageDown => {
          let raw = self.height.to_int() - (self.style.padding.to_int() * 2)
          let step = if raw / 2 < 1 { 1 } else { raw / 2 }
          for i = 0; i < step; i = i + 1 { let _ = self.scroll_down() }
          true
        }
        @ffi.KeyEvent::Home => { self.scroll_offset.val = 0; true }
        @ffi.KeyEvent::End => { for i = 0; i < 1000; i = i + 1 { let _ = self.scroll_down() }; true }
        _ => false
      }
    _ => false
  }
}

///|
pub impl @view.Component for TextArea with is_focusable(self) {
  self.scrollable
}
