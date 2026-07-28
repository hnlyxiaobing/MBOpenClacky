///|
/// Multi-line text editor with CJK-aware cursor positioning.
///
/// Provides Emacs-style editing operations (insert, delete, kill,
/// word motion) with proper handling of double-width characters.
/// The editor tracks cursor position in character indices; display
/// column calculation delegates to `cjk_width` for terminal rendering.
///
/// Design: value-semantics snapshot via `snapshot()` / `restore()`
/// enables cheap undo/redo and render-state isolation.

///|
pub(all) struct LineEditor {
  /// Text content, one string per line.
  mut lines : Array[String]
  /// Whether multi-line editing is enabled.
  multiline : Bool
  /// Submitted input history (newest last).
  mut history : Array[String]
  /// Current history browse index (-1 = not browsing).
  mut history_index : Int
  /// Cursor line index (0-based).
  mut cursor_line : Int
  /// Cursor column index (0-based, character-based).
  mut cursor_col : Int
}

///|
/// Create a single-line editor.
pub fn LineEditor::new() -> LineEditor {
  {
    lines: [""],
    multiline: false,
    history: [],
    history_index: -1,
    cursor_line: 0,
    cursor_col: 0,
  }
}

///|
/// Create a multi-line editor.
pub fn LineEditor::multiline_new() -> LineEditor {
  {
    lines: [""],
    multiline: true,
    history: [],
    history_index: -1,
    cursor_line: 0,
    cursor_col: 0,
  }
}

// ── State queries ──────────────────────────────────────────────────

///|
/// Full text content joined with newlines.
pub fn LineEditor::text(self : LineEditor) -> String {
  let sb = StringBuilder::new()
  for i = 0; i < self.lines.length(); i = i + 1 {
    if i > 0 {
      sb.write_char('\n')
    }
    sb.write_string(self.lines[i])
  }
  sb.to_string()
}

///|
/// Number of lines in the editor.
pub fn LineEditor::line_count(self : LineEditor) -> Int {
  self.lines.length()
}

///|
/// Get a specific line (clamped to valid range).
pub fn LineEditor::get_line(self : LineEditor, idx : Int) -> String {
  let i = if idx < 0 {
    0
  } else if idx >= self.lines.length() {
    self.lines.length() - 1
  } else {
    idx
  }
  self.lines[i]
}

///|
/// Whether the editor has any content.
pub fn LineEditor::is_empty(self : LineEditor) -> Bool {
  self.lines.length() == 1 && self.lines[0].length() == 0
}

///|
/// CJK-aware display column of the cursor on the current line.
pub fn LineEditor::display_col(self : LineEditor) -> Int {
  cursor_display_col(self.lines[self.cursor_line], self.cursor_col)
}

///|
/// Display width of the current line.
pub fn LineEditor::line_display_width(self : LineEditor) -> Int {
  @tui_core.string_display_width(self.lines[self.cursor_line])
}

///|
/// Current cursor (line, col).
pub fn LineEditor::cursor_pos(self : LineEditor) -> (Int, Int) {
  (self.cursor_line, self.cursor_col)
}

// ── Snapshot / Restore ────────────────────────────────────────────

///|
/// Snapshot the current editor state for undo/redo or render isolation.
pub fn LineEditor::snapshot(self : LineEditor) -> LineEditorSnapshot {
  {
    lines: self.lines.copy(),
    cursor_line: self.cursor_line,
    cursor_col: self.cursor_col,
  }
}

///|
/// Restore from a snapshot.
pub fn LineEditor::restore(
  self : LineEditor,
  snap : LineEditorSnapshot,
) -> Unit {
  self.lines.clear()
  for l in snap.lines {
    self.lines.push(l)
  }
  self.cursor_line = snap.cursor_line
  self.cursor_col = snap.cursor_col
}

///|
/// Restore history from another editor (for session restore).
pub fn LineEditor::restore_history(
  self : LineEditor,
  hist : Array[String],
) -> Unit {
  self.history.clear()
  for h in hist {
    self.history.push(h)
  }
  self.history_index = -1
}

///|
/// Immutable snapshot of editor content + cursor.
pub(all) struct LineEditorSnapshot {
  lines : Array[String]
  cursor_line : Int
  cursor_col : Int
}

// ── Content mutation ──────────────────────────────────────────────

///|
/// Replace all content with `text`. Resets cursor to end.
pub fn LineEditor::set_text(self : LineEditor, text : String) -> Unit {
  self.lines.clear()
  for sv in text.split("\n") {
    self.lines.push(sv.to_owned())
  }
  if self.lines.length() == 0 {
    self.lines.push("")
  }
  self.cursor_line = self.lines.length() - 1
  self.cursor_col = self.lines[self.cursor_line].length()
}

///|
/// Clear all content and reset cursor.
pub fn LineEditor::clear(self : LineEditor) -> Unit {
  self.lines.clear()
  self.lines.push("")
  self.cursor_line = 0
  self.cursor_col = 0
  self.history_index = -1
}

// ── Character insertion & deletion ────────────────────────────────

///|
/// Insert a character at the cursor position.
pub fn LineEditor::insert_char(self : LineEditor, c : Char) -> Unit {
  let line = self.lines[self.cursor_line]
  let chars = line.to_array()
  let col = clamp_col(self.cursor_col, chars.length())
  let sb = StringBuilder::new()
  for i = 0; i < col; i = i + 1 {
    sb.write_char(chars[i])
  }
  sb.write_char(c)
  for i = col; i < chars.length(); i = i + 1 {
    sb.write_char(chars[i])
  }
  self.lines[self.cursor_line] = sb.to_string()
  self.cursor_col = col + 1
}

///|
/// Insert text (may contain newlines for multi-line paste).
pub fn LineEditor::insert_text(self : LineEditor, text : String) -> Unit {
  let parts : Array[String] = []
  for sv in text.split("\n") {
    parts.push(sv.to_owned())
  }
  if parts.length() == 0 {
    return
  }
  if parts.length() == 1 {
    for c in parts[0].iter() {
      self.insert_char(c)
    }
    return
  }
  // Multi-line paste: split current line at cursor
  let cur_line = self.lines[self.cursor_line]
  let chars = cur_line.to_array()
  let col = clamp_col(self.cursor_col, chars.length())
  let before : Array[Char] = []
  let after : Array[Char] = []
  for i = 0; i < chars.length(); i = i + 1 {
    if i < col {
      before.push(chars[i])
    } else {
      after.push(chars[i])
    }
  }
  let before_str = char_array_to_string(before)
  let after_str = char_array_to_string(after)
  // Build new lines: before + parts[0], parts[1..n-1], parts[n-1] + after
  let new_lines : Array[String] = []
  for i = 0; i < self.cursor_line; i = i + 1 {
    new_lines.push(self.lines[i])
  }
  new_lines.push(before_str + parts[0])
  for i = 1; i < parts.length() - 1; i = i + 1 {
    new_lines.push(parts[i])
  }
  new_lines.push(parts[parts.length() - 1] + after_str)
  for i = self.cursor_line + 1; i < self.lines.length(); i = i + 1 {
    new_lines.push(self.lines[i])
  }
  self.lines.clear()
  for l in new_lines {
    self.lines.push(l)
  }
  self.cursor_line = self.cursor_line + parts.length() - 1
  self.cursor_col = parts[parts.length() - 1].length()
}

///|
/// Delete the character before the cursor (Backspace).
pub fn LineEditor::backspace(self : LineEditor) -> Unit {
  if self.cursor_col > 0 {
    let line = self.lines[self.cursor_line]
    let chars = line.to_array()
    let col = clamp_col(self.cursor_col, chars.length())
    let sb = StringBuilder::new()
    for i = 0; i < chars.length(); i = i + 1 {
      if i != col - 1 {
        sb.write_char(chars[i])
      }
    }
    self.lines[self.cursor_line] = sb.to_string()
    self.cursor_col = col - 1
  } else if self.multiline && self.cursor_line > 0 {
    // Join with previous line
    let prev = self.lines[self.cursor_line - 1]
    let cur = self.lines[self.cursor_line]
    let new_col = prev.length()
    self.lines[self.cursor_line - 1] = prev + cur
    self.lines.remove(self.cursor_line) |> ignore
    self.cursor_line = self.cursor_line - 1
    self.cursor_col = new_col
  }
}

///|
/// Delete the character at the cursor (Delete key).
pub fn LineEditor::delete_forward(self : LineEditor) -> Unit {
  let line = self.lines[self.cursor_line]
  let chars = line.to_array()
  let col = clamp_col(self.cursor_col, chars.length())
  if col < chars.length() {
    let sb = StringBuilder::new()
    for i = 0; i < chars.length(); i = i + 1 {
      if i != col {
        sb.write_char(chars[i])
      }
    }
    self.lines[self.cursor_line] = sb.to_string()
  } else if self.multiline && self.cursor_line < self.lines.length() - 1 {
    // Join with next line
    let next = self.lines[self.cursor_line + 1]
    self.lines[self.cursor_line] = line + next
    self.lines.remove(self.cursor_line + 1) |> ignore
  }
}

///|
/// Split the current line at the cursor (Enter key).
pub fn LineEditor::handle_enter(self : LineEditor) -> Unit {
  if !self.multiline {
    return
  }
  let line = self.lines[self.cursor_line]
  let chars = line.to_array()
  let col = clamp_col(self.cursor_col, chars.length())
  let before : Array[Char] = []
  let after : Array[Char] = []
  for i = 0; i < chars.length(); i = i + 1 {
    if i < col {
      before.push(chars[i])
    } else {
      after.push(chars[i])
    }
  }
  let new_lines : Array[String] = []
  for i = 0; i < self.cursor_line; i = i + 1 {
    new_lines.push(self.lines[i])
  }
  new_lines.push(char_array_to_string(before))
  new_lines.push(char_array_to_string(after))
  for i = self.cursor_line + 1; i < self.lines.length(); i = i + 1 {
    new_lines.push(self.lines[i])
  }
  self.lines.clear()
  for l in new_lines {
    self.lines.push(l)
  }
  self.cursor_line = self.cursor_line + 1
  self.cursor_col = 0
}

// ── Cursor movement ──────────────────────────────────────────────

///|
/// Move cursor left by one character.
pub fn LineEditor::cursor_left(self : LineEditor) -> Unit {
  if self.cursor_col > 0 {
    self.cursor_col = self.cursor_col - 1
  } else if self.multiline && self.cursor_line > 0 {
    self.cursor_line = self.cursor_line - 1
    self.cursor_col = self.lines[self.cursor_line].length()
  }
}

///|
/// Move cursor right by one character.
pub fn LineEditor::cursor_right(self : LineEditor) -> Unit {
  let line_len = self.lines[self.cursor_line].length()
  if self.cursor_col < line_len {
    self.cursor_col = self.cursor_col + 1
  } else if self.multiline && self.cursor_line < self.lines.length() - 1 {
    self.cursor_line = self.cursor_line + 1
    self.cursor_col = 0
  }
}

///|
/// Move cursor up one line.
pub fn LineEditor::cursor_up(self : LineEditor) -> Unit {
  if self.multiline && self.cursor_line > 0 {
    self.cursor_line = self.cursor_line - 1
    self.cursor_col = clamp_col(
      self.cursor_col,
      self.lines[self.cursor_line].length(),
    )
  }
}

///|
/// Move cursor down one line.
pub fn LineEditor::cursor_down(self : LineEditor) -> Unit {
  if self.multiline && self.cursor_line < self.lines.length() - 1 {
    self.cursor_line = self.cursor_line + 1
    self.cursor_col = clamp_col(
      self.cursor_col,
      self.lines[self.cursor_line].length(),
    )
  }
}

///|
/// Move cursor to start of current line (Home / Ctrl-A).
pub fn LineEditor::cursor_home(self : LineEditor) -> Unit {
  self.cursor_col = 0
}

///|
/// Move cursor to end of current line (End / Ctrl-E).
pub fn LineEditor::cursor_end(self : LineEditor) -> Unit {
  self.cursor_col = self.lines[self.cursor_line].length()
}

// ── Kill operations ──────────────────────────────────────────────

///|
/// Kill from cursor to end of line (Ctrl-K).
pub fn LineEditor::kill_to_end(self : LineEditor) -> Unit {
  let line = self.lines[self.cursor_line]
  let chars = line.to_array()
  let col = clamp_col(self.cursor_col, chars.length())
  if col < chars.length() {
    let sb = StringBuilder::new()
    for i = 0; i < col; i = i + 1 {
      sb.write_char(chars[i])
    }
    self.lines[self.cursor_line] = sb.to_string()
  } else if self.multiline && self.cursor_line < self.lines.length() - 1 {
    // Join with next line
    let next = self.lines[self.cursor_line + 1]
    self.lines[self.cursor_line] = line + next
    self.lines.remove(self.cursor_line + 1) |> ignore
  }
}

///|
/// Kill from start of line to cursor (Ctrl-U).
pub fn LineEditor::kill_to_start(self : LineEditor) -> Unit {
  if self.cursor_col > 0 {
    let line = self.lines[self.cursor_line]
    let chars = line.to_array()
    let col = clamp_col(self.cursor_col, chars.length())
    let sb = StringBuilder::new()
    for i = col; i < chars.length(); i = i + 1 {
      sb.write_char(chars[i])
    }
    self.lines[self.cursor_line] = sb.to_string()
    self.cursor_col = 0
  } else if self.multiline && self.cursor_line > 0 {
    // Join with previous line
    let prev = self.lines[self.cursor_line - 1]
    let cur = self.lines[self.cursor_line]
    let new_col = prev.length()
    self.lines[self.cursor_line - 1] = prev + cur
    self.lines.remove(self.cursor_line) |> ignore
    self.cursor_line = self.cursor_line - 1
    self.cursor_col = new_col
  }
}

///|
/// Kill the previous word (Ctrl-W).
pub fn LineEditor::kill_word(self : LineEditor) -> Unit {
  if self.cursor_col == 0 {
    self.backspace()
    return
  }
  let line = self.lines[self.cursor_line]
  let chars = line.to_array()
  let col = clamp_col(self.cursor_col, chars.length())
  let mut new_col = col - 1
  // Skip trailing separators
  while new_col > 0 && is_word_separator(chars[new_col]) {
    new_col = new_col - 1
  }
  // Skip word characters
  while new_col > 0 && !is_word_separator(chars[new_col - 1]) {
    new_col = new_col - 1
  }
  let sb = StringBuilder::new()
  for i = 0; i < new_col; i = i + 1 {
    sb.write_char(chars[i])
  }
  for i = col; i < chars.length(); i = i + 1 {
    sb.write_char(chars[i])
  }
  self.lines[self.cursor_line] = sb.to_string()
  self.cursor_col = new_col
}

// ── History ──────────────────────────────────────────────────────

///|
/// Navigate to the previous history entry (Up arrow in single-line mode).
pub fn LineEditor::prev_history(self : LineEditor) -> Unit {
  if self.history.is_empty() {
    return
  }
  if self.history_index == -1 {
    self.history_index = self.history.length() - 1
  } else if self.history_index > 0 {
    self.history_index = self.history_index - 1
  } else {
    return
  }
  let entry = self.history[self.history_index]
  self.set_text(entry)
}

///|
/// Navigate to the next history entry (Down arrow in single-line mode).
pub fn LineEditor::next_history(self : LineEditor) -> Unit {
  if self.history_index == -1 {
    return
  }
  if self.history_index < self.history.length() - 1 {
    self.history_index = self.history_index + 1
    let entry = self.history[self.history_index]
    self.set_text(entry)
  } else {
    // At newest: clear editor
    self.history_index = -1
    self.clear()
  }
}

///|
/// Submit the current text: add to history, clear editor, return the text.
pub fn LineEditor::submit(self : LineEditor) -> String {
  let text = self.text()
  if text.length() > 0 {
    self.history.push(text)
  }
  self.clear()
  text
}

// ── Paste helpers ──────────────────────────────────────────────

///|
/// Count the number of newline-separated lines in a paste text.
pub fn paste_line_count(text : String) -> Int {
  let mut count = 1
  for c in text.iter() {
    if c == '\n' {
      count = count + 1
    }
  }
  count
}

///|
/// Build a paste placeholder tag like `[#3 Paste Text]`.
pub fn paste_placeholder_tag(num : Int) -> String {
  "[#\{num} Paste Text]"
}

// ── Internal helpers ─────────────────────────────────────────────

///|
/// Clamp a column value to [0, max].
fn clamp_col(col : Int, max : Int) -> Int {
  if col < 0 {
    0
  } else if col > max {
    max
  } else {
    col
  }
}

///|
/// Convert an array of chars to a string.
fn char_array_to_string(chars : Array[Char]) -> String {
  let sb = StringBuilder::new()
  for c in chars {
    sb.write_char(c)
  }
  sb.to_string()
}

///|
/// Check if a character is a word separator.
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
