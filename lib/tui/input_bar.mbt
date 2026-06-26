///|
/// Input bar component — text input + submit/quit buttons.
///
/// Provides a text input field for user messages and buttons
/// to submit the message or quit the TUI. Also provides a
/// standalone InputBar struct for multi-line editing with history.

///|
/// Build the input bar view with text input and action buttons.
///
/// Parameters:
/// - `input_ref`: shared Ref[String] for the TextInput widget
/// - `on_submit`: callback when the user submits a message
/// - `on_quit`: callback when the user quits
pub fn input_bar_render(
  input_ref : Ref[String],
  on_submit : () -> Unit,
  on_quit : () -> Unit,
) -> @view.View {
  let input = @widget.TextInput::new(input_ref)
    .placeholder("Type a message and press Enter or Submit...")
    .width(60.0)

  let submit_btn = @widget.Button::primary(" Submit ", on_submit)
  let quit_btn = @widget.Button::secondary(" Quit ", on_quit)

  @view.View::container_views([
    @widget.row([
      input,
      @widget.Text::new("  "),
      submit_btn,
      @widget.Text::new("  "),
      quit_btn,
    ]),
  ])
  .padding(1.0)
  .background(@tui_core.RGB(0.12, 0.12, 0.17))
}

// ── Standalone multi-line InputBar ──────────────────────────────────

///|
/// Multi-line text input bar with cursor movement and history.
///
/// Can be used independently of the onebit-tui widget system for
/// custom input handling.
pub(all) struct InputBar {
  /// Lines of text content.
  mut content_lines : Array[String]
  /// Whether multi-line mode is enabled.
  multiline : Bool
  /// History of submitted inputs.
  mut history : Array[String]
  /// Current position in history (-1 = not browsing).
  mut history_index : Int
  /// Current cursor line index.
  mut cursor_line : Int
  /// Current cursor column index.
  mut cursor_col : Int
} derive(Debug)

///|
/// Create a new single-line InputBar.
pub fn InputBar::new() -> InputBar {
  {
    content_lines: [""],
    multiline: false,
    history: [],
    history_index: -1,
    cursor_line: 0,
    cursor_col: 0,
  }
}

///|
/// Create a new multi-line InputBar.
pub fn InputBar::multiline_bar() -> InputBar {
  {
    content_lines: [""],
    multiline: true,
    history: [],
    history_index: -1,
    cursor_line: 0,
    cursor_col: 0,
  }
}

///|
/// Insert a character at the current cursor position.
pub fn InputBar::insert_char(self : InputBar, ch : Char) -> Unit {
  let line = self.content_lines[self.cursor_line]
  let chars = line.to_array()
  let col = clamp_col(self.cursor_col, chars.length())
  // Insert character at position
  let new_chars : Array[Char] = []
  for i = 0; i < chars.length(); i = i + 1 {
    if i == col {
      new_chars.push(ch)
    }
    new_chars.push(chars[i])
  }
  if col >= chars.length() {
    new_chars.push(ch)
  }
  self.content_lines[self.cursor_line] = char_array_to_string(new_chars)
  self.cursor_col = col + 1
}

///|
/// Delete the character before the cursor (backspace).
pub fn InputBar::delete_char(self : InputBar) -> Unit {
  let line = self.content_lines[self.cursor_line]
  let chars = line.to_array()
  if self.cursor_col > 0 && self.cursor_col <= chars.length() {
    let new_chars : Array[Char] = []
    for i = 0; i < chars.length(); i = i + 1 {
      if i != self.cursor_col - 1 {
        new_chars.push(chars[i])
      }
    }
    self.content_lines[self.cursor_line] = char_array_to_string(new_chars)
    self.cursor_col = self.cursor_col - 1
  } else if self.cursor_col == 0 && self.cursor_line > 0 && self.multiline {
    // Merge with previous line
    let prev_line = self.content_lines[self.cursor_line - 1]
    let current_line = self.content_lines[self.cursor_line]
    let new_col = prev_line.length()
    self.content_lines[self.cursor_line - 1] = prev_line + current_line
    // Remove current line by rebuilding
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
/// Move cursor one position to the left.
pub fn InputBar::move_cursor_left(self : InputBar) -> Unit {
  if self.cursor_col > 0 {
    self.cursor_col = self.cursor_col - 1
  } else if self.cursor_line > 0 && self.multiline {
    self.cursor_line = self.cursor_line - 1
    self.cursor_col = self.content_lines[self.cursor_line].length()
  }
}

///|
/// Move cursor one position to the right.
pub fn InputBar::move_cursor_right(self : InputBar) -> Unit {
  let line_len = self.content_lines[self.cursor_line].length()
  if self.cursor_col < line_len {
    self.cursor_col = self.cursor_col + 1
  } else if self.cursor_line < self.content_lines.length() - 1 && self.multiline {
    self.cursor_line = self.cursor_line + 1
    self.cursor_col = 0
  }
}

///|
/// Move cursor up one line (multi-line mode only).
pub fn InputBar::move_cursor_up(self : InputBar) -> Unit {
  if self.multiline && self.cursor_line > 0 {
    self.cursor_line = self.cursor_line - 1
    let line_len = self.content_lines[self.cursor_line].length()
    self.cursor_col = if self.cursor_col > line_len {
      line_len
    } else {
      self.cursor_col
    }
  }
}

///|
/// Move cursor down one line (multi-line mode only).
pub fn InputBar::move_cursor_down(self : InputBar) -> Unit {
  if self.multiline && self.cursor_line < self.content_lines.length() - 1 {
    self.cursor_line = self.cursor_line + 1
    let line_len = self.content_lines[self.cursor_line].length()
    self.cursor_col = if self.cursor_col > line_len {
      line_len
    } else {
      self.cursor_col
    }
  }
}

///|
/// Handle the Enter key.
///
/// In single-line mode, returns the current content (ready to submit).
/// In multi-line mode, inserts a newline at the cursor position.
pub fn InputBar::handle_enter(self : InputBar) -> String? {
  if self.multiline {
    // Insert newline at cursor position
    let line = self.content_lines[self.cursor_line]
    let before = line[0:self.cursor_col].to_owned()
    let after = line[self.cursor_col:].to_owned()
    self.content_lines[self.cursor_line] = before
    // Insert new line after current
    let new_lines : Array[String] = []
    for i = 0; i < self.content_lines.length(); i = i + 1 {
      new_lines.push(self.content_lines[i])
      if i == self.cursor_line {
        new_lines.push(after)
      }
    }
    self.content_lines.clear()
    for l in new_lines {
      self.content_lines.push(l)
    }
    self.cursor_line = self.cursor_line + 1
    self.cursor_col = 0
    None
  } else {
    // Single-line: return content
    let content = self.get_content()
    Some(content)
  }
}

///|
/// Handle submit (Ctrl+Enter in multi-line mode).
///
/// Returns the full content if there is content to submit.
pub fn InputBar::handle_submit(self : InputBar) -> String? {
  let content = self.get_content()
  if content.length() > 0 {
    self.history.push(content)
    self.history_index = -1
    Some(content)
  } else {
    None
  }
}

///|
/// Navigate to the previous history entry.
pub fn InputBar::history_prev(self : InputBar) -> Unit {
  if self.history.length() == 0 {
    return
  }
  if self.history_index < 0 {
    self.history_index = self.history.length() - 1
  } else if self.history_index > 0 {
    self.history_index = self.history_index - 1
  }
  if self.history_index >= 0 && self.history_index < self.history.length() {
    self.content_lines.clear()
    self.content_lines.push(self.history[self.history_index])
    self.cursor_line = 0
    self.cursor_col = self.content_lines[0].length()
  }
}

///|
/// Navigate to the next history entry.
pub fn InputBar::history_next(self : InputBar) -> Unit {
  if self.history.length() == 0 || self.history_index < 0 {
    return
  }
  if self.history_index < self.history.length() - 1 {
    self.history_index = self.history_index + 1
    self.content_lines.clear()
    self.content_lines.push(self.history[self.history_index])
    self.cursor_line = 0
    self.cursor_col = self.content_lines[0].length()
  } else {
    // Past the end — clear to empty
    self.history_index = -1
    self.content_lines.clear()
    self.content_lines.push("")
    self.cursor_line = 0
    self.cursor_col = 0
  }
}

///|
/// Clear the input content and reset cursor.
pub fn InputBar::clear(self : InputBar) -> Unit {
  self.content_lines.clear()
  self.content_lines.push("")
  self.cursor_line = 0
  self.cursor_col = 0
}

///|
/// Get the full content as a single string (lines joined by newline).
pub fn InputBar::get_content(self : InputBar) -> String {
  self.content_lines.join("\n")
}

///|
/// Get the current cursor position as (line, column).
pub fn InputBar::get_cursor_position(self : InputBar) -> (Int, Int) {
  (self.cursor_line, self.cursor_col)
}

///|
/// Build the input bar view with command suggestions dropdown above.
///
/// When `suggestions` is visible, renders the dropdown above the input field.
/// Parameters:
/// - `input_ref`: shared Ref[String] for the TextInput widget
/// - `suggestions`: command suggestions controller
/// - `on_submit`: callback when the user submits a message
/// - `on_quit`: callback when the user quits
pub fn input_bar_render_with_suggestions(
  input_ref : Ref[String],
  suggestions : CommandSuggestions,
  on_submit : () -> Unit,
  on_quit : () -> Unit,
) -> @view.View {
  let views : Array[@view.View] = []
  // Render suggestions dropdown if visible
  if suggestions.is_visible() {
    let suggestion_lines = suggestions.render()
    let suggestion_views : Array[@view.View] = []
    for line in suggestion_lines {
      suggestion_views.push(@view.View::text(line, color=@tui_core.Yellow))
    }
    views.push(@view.View::container_views(suggestion_views))
  }
  // Input field and buttons
  let input = @widget.TextInput::new(input_ref)
    .placeholder("Type a message or /command...")
    .width(60.0)
  let submit_btn = @widget.Button::primary(" Submit ", on_submit)
  let quit_btn = @widget.Button::secondary(" Quit ", on_quit)
  views.push(
    @view.View::container_views([
      @widget.row([
        input,
        @widget.Text::new("  "),
        submit_btn,
        @widget.Text::new("  "),
        quit_btn,
      ]),
    ])
    .padding(1.0)
    .background(@tui_core.RGB(0.12, 0.12, 0.17)),
  )
  @view.View::container_views(views).direction(Column)
}

// ── InputSession: unified editor + suggestions controller ────────────

///|
/// A unified input session combining InputBar editing with CommandSuggestions.
///
/// Coordinates between the text editor and the suggestion dropdown:
/// when the user types a "/" prefix, suggestions appear; Tab/Up/Down
/// navigate them; Enter accepts; Escape dismisses.
pub(all) struct InputSession {
  /// The underlying text editor.
  bar : InputBar
  /// Command suggestions dropdown.
  suggestions : CommandSuggestions
  /// Whether to auto-show suggestions when "/" is typed.
  auto_suggest : Bool
} derive(Debug)

///|
/// Create a new InputSession with default settings.
pub fn InputSession::new() -> InputSession {
  {
    bar: InputBar::multiline_bar(),
    suggestions: CommandSuggestions::new(),
    auto_suggest: true,
  }
}

///|
/// Create an InputSession with custom skill commands.
pub fn InputSession::with_skills(
  skill_commands : Array[SuggestionItem],
) -> InputSession {
  {
    bar: InputBar::multiline_bar(),
    suggestions: CommandSuggestions::with_skills(skill_commands),
    auto_suggest: true,
  }
}

///|
/// Handle a character insertion, updating suggestions as needed.
pub fn InputSession::handle_char(self : InputSession, ch : Char) -> Unit {
  self.bar.insert_char(ch)
  self.maybe_update_suggestions()
}

///|
/// Handle backspace, updating suggestions as needed.
pub fn InputSession::handle_backspace(self : InputSession) -> Unit {
  self.bar.delete_char()
  self.maybe_update_suggestions()
}

///|
/// Handle Tab key — navigate suggestions or insert tab.
///
/// Returns true if the Tab was consumed by suggestions.
pub fn InputSession::handle_tab(self : InputSession) -> Bool {
  if self.suggestions.is_visible() {
    self.suggestions.select_next()
    true
  } else {
    false
  }
}

///|
/// Handle Shift+Tab — navigate suggestions backwards.
///
/// Returns true if consumed.
pub fn InputSession::handle_shift_tab(self : InputSession) -> Bool {
  if self.suggestions.is_visible() {
    self.suggestions.select_prev()
    true
  } else {
    false
  }
}

///|
/// Handle Escape key — dismiss suggestions.
///
/// Returns true if consumed.
pub fn InputSession::handle_escape(self : InputSession) -> Bool {
  if self.suggestions.is_visible() {
    self.suggestions.hide()
    true
  } else {
    false
  }
}

///|
/// Handle Enter key — accept suggestion or submit.
///
/// Returns the submitted content if a submission occurred,
/// or None if a suggestion was accepted (content is replaced)
/// or if multi-line mode inserted a newline.
pub fn InputSession::handle_enter(self : InputSession) -> String? {
  if self.suggestions.is_visible() {
    match self.suggestions.accept() {
      Some(cmd) => {
        // Replace input content with selected command
        self.bar.clear()
        for c in cmd.iter() {
          self.bar.insert_char(c)
        }
        self.suggestions.hide()
        None
      }
      None => self.bar.handle_enter()
    }
  } else {
    self.bar.handle_enter()
  }
}

///|
/// Submit the current input, adding to history.
pub fn InputSession::submit(self : InputSession) -> String? {
  self.suggestions.hide()
  self.bar.handle_submit()
}

///|
/// Get the current input content.
pub fn InputSession::get_content(self : InputSession) -> String {
  self.bar.get_content()
}

///|
/// Render the input session for display.
///
/// Returns suggestion lines (if visible) followed by the current
/// input line with cursor indicator.
pub fn InputSession::render(self : InputSession) -> Array[String] {
  let lines : Array[String] = []
  if self.suggestions.is_visible() {
    for sl in self.suggestions.render() {
      lines.push(sl)
    }
  }
  lines.push(self.bar.render_with_cursor())
  lines
}

// ── Internal helpers for InputSession ────────────────────────────────

///|
/// Check if the current input looks like a command prefix and
/// update suggestions accordingly.
fn InputSession::maybe_update_suggestions(self : InputSession) -> Unit {
  if !self.auto_suggest {
    return
  }
  let content = self.bar.get_content()
  // Only show suggestions for single-line slash prefixes
  if self.bar.content_lines.length() == 1 &&
    content.length() > 0 &&
    content.to_array()[0] == '/' {
    self.suggestions.update_filter(content)
  } else {
    self.suggestions.hide()
  }
}

// ── Internal helpers ────────────────────────────────────────────────

///|
/// Clamp column to valid range.
fn clamp_col(col : Int, len : Int) -> Int {
  if col < 0 {
    0
  } else if col > len {
    len
  } else {
    col
  }
}

///|
/// Convert a char array to a string.
fn char_array_to_string(chars : Array[Char]) -> String {
  let sb = StringBuilder::new()
  for c in chars {
    sb.write_char(c)
  }
  sb.to_string()
}
