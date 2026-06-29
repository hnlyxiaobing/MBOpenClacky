///|
/// Tool output component — displays tool execution history.
///
/// Shows all tool calls from the current run in a scrollable list,
/// with status indicators for running and completed executions.

///|
/// Build the tool history view from current TUI state.
///
/// When `tool_history` contains entries, renders them in a ScrollBox
/// with status icons (⟳ running / ✓ completed). Falls back to the
/// latest `tool_output` text or an empty-state message otherwise.
pub fn tool_view_render(state : Ref[TuiState]) -> @view.View {
  let s = state.val
  let history = s.tool_history

  if history.length() == 0 {
    // No history yet — show current tool output or empty placeholder
    let output = s.tool_output
    if output.length() == 0 {
      @widget.Box::new([@widget.Text::caption("No tool output yet")])
      .border(Single)
      .title("Tool Output")
      .render()
    } else {
      @widget.Box::new([@widget.Text::new(output).color(@tui_core.Yellow)])
      .border(Single)
      .title("Tool Output")
      .render()
    }
  } else {
    // Render the full tool execution history
    let components : Array[&@view.Component] = []
    for exec in history {
      let status_icon = if exec.completed { "✓" } else { "⟳" }
      let color : @tui_core.Color = if exec.completed {
        @tui_core.Green
      } else {
        @tui_core.Yellow
      }
      let detail = if exec.completed { exec.result_summary } else { exec.args }
      let line = "\{status_icon} \{exec.name}: \{detail}"
      components.push(@widget.Text::new(line).color(color))
    }
    let scroll = @widget.ScrollBox::new(components, visible_rows=8)
    scroll.title("Tool History").border(Single).render()
  }
}
