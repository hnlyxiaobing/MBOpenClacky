///|
/// Tool output component — displays latest tool execution results.
///
/// Shows tool calls and their results in a bordered box,
/// separate from the main message history.

///|
/// Build the tool output view from current TUI state.
pub fn tool_view_render(state : Ref[TuiState]) -> @view.View {
  let s = state.val
  let output = s.tool_output

  if output.length() == 0 {
    // Empty state
    @widget.Box::new([@widget.Text::caption("No tool output yet")])
    .border(Single)
    .title("Tool Output")
    .render()
  } else {
    // Show the tool output text
    @widget.Box::new([@widget.Text::new(output).color(@tui_core.Yellow)])
    .border(Single)
    .title("Tool Output")
    .render()
  }
}
