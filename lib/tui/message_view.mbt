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
    let component = format_message_line(msg_str)
    components.push(component)
  }

  // Wrap in a ScrollBox with a border and title
  let scroll = @widget.ScrollBox::new(components, visible_rows=15)
  scroll.title("Messages").border(Single).render()
}

///|
/// Parse a formatted message string and return a colored component.
///
/// Format: "[ROLE] content"
/// ROLE is one of: system, user, assistant, tool
fn format_message_line(line : String) -> @widget.Text {
  let color = if line.has_prefix("[system]") {
    @tui_core.Gray
  } else if line.has_prefix("[user]") {
    @tui_core.Green
  } else if line.has_prefix("[assistant]") {
    @tui_core.Cyan
  } else if line.has_prefix("[tool]") {
    @tui_core.Yellow
  } else {
    @tui_core.White
  }
  @widget.Text::new(line).color(color)
}
