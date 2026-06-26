///|
/// Editor extensions for InputBar: kill operations, CJK-aware cursor,
/// and additional editing commands.
///
/// These methods extend the InputBar struct defined in input_bar.mbt
/// with Emacs-style kill operations (Ctrl-K, Ctrl-U, Ctrl-W),
/// home/end cursor movement, and CJK display-width-aware positioning.

///|
/// Kill from cursor to end of current line (Ctrl-K).
///
/// If the cursor is at the end of a line in multi-line mode,
/// joins the next line into the current line instead.
pub fn InputBar::kill_to_end(self : InputBar) -> Unit {
  let line = self.content_lines[self.cursor_line]
  let chars = line.to_array()
  let col = clamp_col(self.cursor_col, chars.length())
  if col < chars.length() {
    // Delete from cursor to end of line
    let kept : Array[Char] = []
    for i = 0; i < col; i = i + 1 {
      kept.push(chars[i])
    }
    self.content_lines[self.cursor_line] = char_array_to_string(kept)
  } else if self.multiline && self.cursor_line < self.content_lines.length() - 1 {
    // At end of line: join with next line
    let next_line = self.content_lines[self.cursor_line + 1]
    self.content_lines[self.cursor_line] = line + next_line
    // Remove the next line
    let new_lines : Array[String] = []
    for i = 0; i < self.content_lines.length(); i = i + 1 {
      if i != self.cursor_line + 1 {
        new_lines.push(self.content_lines[i])
      }
    }
    self.content_lines.clear()
    for l in new_lines {
      self.content_lines.push(l)
    }
  }
}

///|
/// Kill from start of current line to cursor (Ctrl-U).
///
/// Deletes all characters before the cursor on the current line.
/// If the cursor is at column 0 in multi-line mode, joins the
/// current line with the previous line.
pub fn InputBar::kill_to_start(self : InputBar) -> Unit {
  let col = self.cursor_col
  if col > 0 {
    let line = self.content_lines[self.cursor_line]
    let chars = line.to_array()
    let kept : Array[Char] = []
    for i = col; i < chars.length(); i = i + 1 {
      kept.push(chars[i])
    }
    self.content_lines[self.cursor_line] = char_array_to_string(kept)
    self.cursor_col = 0
  } else if self.multiline && self.cursor_line > 0 {
    // At start of line: join with previous line
    let prev_line = self.content_lines[self.cursor_line - 1]
    let current_line = self.content_lines[self.cursor_line]
    let new_col = prev_line.length()
    self.content_lines[self.cursor_line - 1] = prev_line + current_line
    // Remove current line
    let new_lines : Array[String] = []
    for i = 0; i < self.content_lines.length(); i = i + 1 {
      if i != self.cursor_line {
        new_lines.push(self.content_lines[i])
      }
    }
    self.content_lines.clear()
    for l in new_lines {
      self.content_lines.push(l)
    }
    self.cursor_line = self.cursor_line - 1
    self.cursor_col = new_col
  }
}

///|
/// Kill the previous word (Ctrl-W).
///
/// Deletes from the cursor back to the start of the previous word.
/// Word boundaries are whitespace and punctuation.
pub fn InputBar::kill_word(self : InputBar) -> Unit {
  if self.cursor_col == 0 {
    // At start of line: behave like backspace at line boundary
    self.delete_char()
    return
  }
  let line = self.content_lines[self.cursor_line]
  let chars = line.to_array()
  let col = clamp_col(self.cursor_col, chars.length())
  // Walk backward from cursor to find word boundary
  let mut new_col = col - 1
  // Skip trailing whitespace/separators
  while new_col > 0 && is_word_separator(chars[new_col]) {
    new_col = new_col - 1
  }
  // Skip word characters
  while new_col > 0 && !is_word_separator(chars[new_col - 1]) {
    new_col = new_col - 1
  }
  // Build new line: chars[0..new_col] + chars[col..]
  let kept : Array[Char] = []
  for i = 0; i < new_col; i = i + 1 {
    kept.push(chars[i])
  }
  for i = col; i < chars.length(); i = i + 1 {
    kept.push(chars[i])
  }
  self.content_lines[self.cursor_line] = char_array_to_string(kept)
  self.cursor_col = new_col
}

///|
/// Move cursor to the start of the current line (Home / Ctrl-A).
pub fn InputBar::cursor_home(self : InputBar) -> Unit {
  self.cursor_col = 0
}

///|
/// Move cursor to the end of the current line (End / Ctrl-E).
pub fn InputBar::cursor_end(self : InputBar) -> Unit {
  self.cursor_col = self.content_lines[self.cursor_line].length()
}

///|
/// Delete the character at the cursor position (Delete key).
///
/// Unlike backspace (delete_char), this deletes forward.
/// In multi-line mode at end of line, joins with the next line.
pub fn InputBar::delete_forward(self : InputBar) -> Unit {
  let line = self.content_lines[self.cursor_line]
  let chars = line.to_array()
  let col = clamp_col(self.cursor_col, chars.length())
  if col < chars.length() {
    let kept : Array[Char] = []
    for i = 0; i < chars.length(); i = i + 1 {
      if i != col {
        kept.push(chars[i])
      }
    }
    self.content_lines[self.cursor_line] = char_array_to_string(kept)
  } else if self.multiline && self.cursor_line < self.content_lines.length() - 1 {
    // At end of line: join with next line
    let next_line = self.content_lines[self.cursor_line + 1]
    self.content_lines[self.cursor_line] = line + next_line
    let new_lines : Array[String] = []
    for i = 0; i < self.content_lines.length(); i = i + 1 {
      if i != self.cursor_line + 1 {
        new_lines.push(self.content_lines[i])
      }
    }
    self.content_lines.clear()
    for l in new_lines {
      self.content_lines.push(l)
    }
  }
}

///|
/// Get the CJK-aware display column for the current cursor position.
///
/// Returns the visual column offset accounting for double-width characters.
pub fn InputBar::get_display_col(self : InputBar) -> Int {
  let line = self.content_lines[self.cursor_line]
  cursor_display_col(line, self.cursor_col)
}

///|
/// Get the total display width of the current line.
pub fn InputBar::get_line_display_width(self : InputBar) -> Int {
  let line = self.content_lines[self.cursor_line]
  string_display_width(line)
}

///|
/// Insert multiple lines of text (e.g., from a paste operation).
///
/// The first line is inserted at the cursor position on the current line;
/// subsequent lines are inserted as new lines below.
pub fn InputBar::insert_text(self : InputBar, text : String) -> Unit {
  let text_lines : Array[String] = []
  for sv in text.split("\n") {
    text_lines.push(sv.to_owned())
  }
  if text_lines.length() == 0 {
    return
  }
  if text_lines.length() == 1 {
    // Single line: insert at cursor
    for c in text_lines[0].iter() {
      self.insert_char(c)
    }
    return
  }
  // Multi-line paste
  let first = text_lines[0]
  let last = text_lines[text_lines.length() - 1]
  // Insert first part at cursor
  for c in first.iter() {
    self.insert_char(c)
  }
  // Insert newlines and middle lines
  for i = 1; i < text_lines.length() - 1; i = i + 1 {
    self.handle_enter() |> ignore
    for c in text_lines[i].iter() {
      self.insert_char(c)
    }
  }
  // Insert last line via newline
  self.handle_enter() |> ignore
  for c in last.iter() {
    self.insert_char(c)
  }
}

///|
/// Render the current line with cursor position indicator.
///
/// Returns a string with the cursor position marked using `|` character.
/// Uses CJK-aware display width so the cursor indicator is placed at the
/// correct visual column when the line contains double-width characters.
pub fn InputBar::render_with_cursor(self : InputBar) -> String {
  let line = self.content_lines[self.cursor_line]
  let chars = line.to_array()
  let col = clamp_col(self.cursor_col, chars.length())
  let sb = StringBuilder::new()
  // Render characters before cursor
  for i = 0; i < chars.length(); i = i + 1 {
    if i == col {
      sb.write_char('|')
    }
    sb.write_char(chars[i])
  }
  if col >= chars.length() {
    sb.write_char('|')
  }
  sb.to_string()
}

///|
/// Get the visual cursor column for the current line, accounting for CJK double-width.
///
/// Returns the display column where the cursor indicator should be placed,
/// suitable for use with fixed-width terminal rendering.
pub fn InputBar::visual_cursor_col(self : InputBar) -> Int {
  let line = self.content_lines[self.cursor_line]
  cursor_display_col(line, self.cursor_col)
}

// ── Internal helpers ────────────────────────────────────────────────

///|
/// Check if a character is a word separator (whitespace or punctuation).
fn is_word_separator(c : Char) -> Bool {
  c == ' ' ||
  c == '\t' ||
  c == '/' ||
  c == '\\' ||
  c == '.' ||
  c == ',' ||
  c == ';' ||
  c == ':' ||
  c == '-' ||
  c == '_' ||
  c == '(' ||
  c == ')' ||
  c == '[' ||
  c == ']' ||
  c == '{' ||
  c == '}'
}
