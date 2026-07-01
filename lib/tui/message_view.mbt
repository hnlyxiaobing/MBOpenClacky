///|
/// Message history component — scrollable conversation display.
///
/// Shows all messages in the conversation with role-based coloring.
/// Messages are formatted as "[ROLE] content" and wrapped in a ScrollBox.

///|
/// Build the message history view from current TUI state.
pub fn message_view_render(state : Ref[TuiState]) -> @view.View {
  let s = state.val
  let messages = s.messages

  // Convert stored message strings into colored Text components
  let components : Array[&@view.Component] = []
  for msg_str in messages {
    let component = format_message_line(msg_str, s.theme)
    components.push(component)
  }

  // Show streaming content if active
  if s.streaming_active && s.streaming_buffer.length() > 0 {
    let streaming_text = "Assistant: \{s.streaming_buffer}"
    components.push(@widget.Text::new(streaming_text).color(@tui_core.Cyan))
  }

  // Compute visible rows from the actual terminal height so the message pane
  // fills the screen instead of a hardcoded 15 rows (which caused the pane to
  // collapse / mismatch the terminal). Reserve rows for the status bar (1),
  // the input footer (~3), and the ScrollBox border (2).
  let (_, term_h) = @ffi.get_terminal_size()
  let terminal_height = term_h.reinterpret_as_int()
  let reserved = 6
  let visible_rows = if terminal_height > reserved + 3 {
    terminal_height - reserved
  } else {
    3
  }

  // Auto-scroll to the bottom so the most recent messages are always shown.
  let offset = Ref::new(0)
  let total = components.length()
  if total > visible_rows {
    offset.val = total - visible_rows
  }

  // Wrap in a ScrollBox with a border and title
  let scroll = @widget.ScrollBox::new(
    components,
    visible_rows~,
    offset~,
  )
  scroll.title("Messages").border(Single).render()
}

///|
/// Parse a formatted message string and return a colored component.
///
/// Format: "[ROLE] content"
/// ROLE is one of: system, user, assistant, tool
/// Assistant messages are rendered through MarkdownRenderer for rich formatting.
fn format_message_line(line : String, theme : Theme) -> @widget.Text {
  if line.has_prefix("[assistant]") {
    let content = safe_strip_prefix(line, 12).trim().to_owned()
    let renderer = MarkdownRenderer::new(theme~)
    let rendered = renderer.render(content)
    @widget.Text::new("Assistant: \{rendered}").color(@tui_core.Cyan)
  } else if line.has_prefix("[user]") {
    let content = safe_strip_prefix(line, 7).trim()
    @widget.Text::new("You: \{content}").color(@tui_core.Green)
  } else if line.has_prefix("[system]") {
    let content = safe_strip_prefix(line, 9).trim().to_owned()
    @widget.Text::new(content).color(@tui_core.Gray)
  } else if line.has_prefix("[tool]") {
    let content = safe_strip_prefix(line, 7).trim()
    @widget.Text::new("Tool: \{content}").color(@tui_core.Yellow)
  } else {
    @widget.Text::new(line).color(@tui_core.White)
  }
}

///|
/// Safely strip the first `n` characters from a string.
/// Returns empty string if the string is shorter than `n`.
fn safe_strip_prefix(s : String, n : Int) -> String {
  if s.length() > n {
    s[n:].to_owned()
  } else {
    ""
  }
}
