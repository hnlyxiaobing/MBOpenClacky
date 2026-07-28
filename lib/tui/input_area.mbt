///|
/// Input area component — wraps LineEditor and provides rendering data.
///
/// Manages the multi-line text editor inside the bordered input region.
/// Provides:
/// - Text lines for rendering
/// - Display cursor position (accounting for CJK width)
/// - Prompt prefix support
/// - Placeholder text when empty
pub(all) struct InputArea {
  /// The underlying line editor.
  editor : LineEditor
  /// Prompt prefix (e.g., ">" or "»").
  mut prompt : String
  /// Placeholder shown when input is empty.
  mut placeholder : String
  /// Border color name for the input box.
  border_color : @color.Color
}

///|
/// Create a new single-line InputArea.
pub fn InputArea::new() -> InputArea {
  {
    editor: LineEditor::new(),
    prompt: "» ",
    placeholder: "Type a message and press Enter to send...",
    border_color: @color.Color::Basic(@color.BasicColor::Blue),
  }
}

///|
/// Create a new multi-line InputArea.
pub fn InputArea::multiline_new() -> InputArea {
  {
    editor: LineEditor::multiline_new(),
    prompt: "» ",
    placeholder: "Type a message (Enter to send, Ctrl+J for newline)...",
    border_color: @color.Color::Basic(@color.BasicColor::Blue),
  }
}

///|
/// Get the full text content.
pub fn InputArea::text(self : InputArea) -> String {
  self.editor.text()
}

///|
/// Check if the input is empty.
pub fn InputArea::is_empty(self : InputArea) -> Bool {
  self.editor.is_empty()
}

///|
/// Clear the input content.
pub fn InputArea::clear(self : InputArea) -> Unit {
  self.editor.clear()
}

///|
/// Set the text content directly.
pub fn InputArea::set_text(self : InputArea, text : String) -> Unit {
  self.editor.set_text(text)
}

///|
/// Get the number of text lines.
pub fn InputArea::line_count(self : InputArea) -> Int {
  self.editor.line_count()
}

///|
/// Get a specific line's text.
pub fn InputArea::get_line(self : InputArea, idx : Int) -> String {
  self.editor.get_line(idx)
}

///|
/// Get the display cursor position as (line_index, display_column).
///
/// The display column accounts for CJK double-width characters
/// and the prompt prefix offset.
pub fn InputArea::cursor_display_pos(self : InputArea) -> (Int, Int) {
  let (line, _col) = self.editor.cursor_pos()
  let display_col = self.editor.display_col()
  // Add prompt length to the display column
  let prompt_len = @tui_core.string_display_width(self.prompt)
  (line, display_col + prompt_len)
}

// ── Editing operations (delegate to LineEditor) ──────────────────

///|
/// Insert a character at the cursor position.
pub fn InputArea::insert_char(self : InputArea, c : Char) -> Unit {
  self.editor.insert_char(c)
}

///|
/// Insert text at the cursor position.
pub fn InputArea::insert_text(self : InputArea, text : String) -> Unit {
  self.editor.insert_text(text)
}

///|
/// Delete the character before the cursor (backspace).
pub fn InputArea::backspace(self : InputArea) -> Unit {
  self.editor.backspace()
}

///|
/// Delete the character at the cursor (forward delete).
pub fn InputArea::delete_forward(self : InputArea) -> Unit {
  self.editor.delete_forward()
}

///|
/// Handle Enter key.
///
/// In multi-line mode, inserts a newline.
/// In single-line mode, submits.
pub fn InputArea::handle_enter(self : InputArea) -> Unit {
  self.editor.handle_enter()
}

///|
/// Submit the input, adding to history.
///
/// Returns the submitted text, or empty string if nothing to submit.
pub fn InputArea::submit(self : InputArea) -> String {
  self.editor.submit()
}

// ── Cursor movement (delegate to LineEditor) ────────────────────

///|
/// Move cursor left.
pub fn InputArea::cursor_left(self : InputArea) -> Unit {
  self.editor.cursor_left()
}

///|
/// Move cursor right.
pub fn InputArea::cursor_right(self : InputArea) -> Unit {
  self.editor.cursor_right()
}

///|
/// Move cursor up (multi-line mode).
pub fn InputArea::cursor_up(self : InputArea) -> Unit {
  self.editor.cursor_up()
}

///|
/// Move cursor down (multi-line mode).
pub fn InputArea::cursor_down(self : InputArea) -> Unit {
  self.editor.cursor_down()
}

///|
/// Move cursor to start of line.
pub fn InputArea::cursor_home(self : InputArea) -> Unit {
  self.editor.cursor_home()
}

///|
/// Move cursor to end of line.
pub fn InputArea::cursor_end(self : InputArea) -> Unit {
  self.editor.cursor_end()
}

// ── Kill operations ──────────────────────────────────────────────

///|
/// Kill from cursor to end of line (Ctrl-K).
pub fn InputArea::kill_to_end(self : InputArea) -> Unit {
  self.editor.kill_to_end()
}

///|
/// Kill from start of line to cursor (Ctrl-U).
pub fn InputArea::kill_to_start(self : InputArea) -> Unit {
  self.editor.kill_to_start()
}

///|
/// Kill the previous word (Ctrl-W).
pub fn InputArea::kill_word(self : InputArea) -> Unit {
  self.editor.kill_word()
}

// ── History ──────────────────────────────────────────────────────

///|
/// Navigate to previous history entry.
pub fn InputArea::prev_history(self : InputArea) -> Unit {
  self.editor.prev_history()
}

///|
/// Navigate to next history entry.
pub fn InputArea::next_history(self : InputArea) -> Unit {
  self.editor.next_history()
}

// ── Rendering helpers ─────────────────────────────────────────────

///|
/// Render the input text lines for display.
///
/// Returns an array of strings, one per line of input.
/// If the input is empty, returns a single line with the placeholder.
pub fn InputArea::render_lines(self : InputArea) -> Array[String] {
  let lines : Array[String] = []
  if self.editor.is_empty() {
    // Show placeholder in dim style
    lines.push(self.placeholder)
    return lines
  }
  let n = self.editor.line_count()
  for i = 0; i < n; i = i + 1 {
    let line = self.editor.get_line(i)
    if i == 0 {
      lines.push(self.prompt + line)
    } else {
      lines.push(line)
    }
  }
  return lines
}

///|
/// Get the raw text lines without prompt prefix or placeholder.
pub fn InputArea::raw_lines(self : InputArea) -> Array[String] {
  let lines : Array[String] = []
  let n = self.editor.line_count()
  for i = 0; i < n; i = i + 1 {
    lines.push(self.editor.get_line(i))
  }
  return lines
}

///|
/// Set the prompt prefix.
pub fn InputArea::set_prompt(self : InputArea, prompt : String) -> Unit {
  self.prompt = prompt
}

///|
/// Set the placeholder text.
pub fn InputArea::set_placeholder(
  self : InputArea,
  placeholder : String,
) -> Unit {
  self.placeholder = placeholder
}

///|
/// Get a snapshot of the editor state (for undo/restore).
pub fn InputArea::snapshot(self : InputArea) -> LineEditorSnapshot {
  self.editor.snapshot()
}

///|
/// Restore the editor state from a snapshot.
pub fn InputArea::restore(self : InputArea, snap : LineEditorSnapshot) -> Unit {
  self.editor.restore(snap)
}
