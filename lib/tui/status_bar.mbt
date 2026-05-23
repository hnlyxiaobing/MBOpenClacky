///|
/// Status bar component displaying agent status, model name, and iteration count.
///
/// Renders as a single row at the top of the TUI layout.
/// Uses onebit-tui raw Views for a lightweight, non-interactive display.

///|
/// Build the status bar view from the current TUI state.
pub fn status_bar_render(state : Ref[TuiState]) -> @view.View {
  let s = state.val
  let status_color = match s.agent_status {
    "running" => @tui_core.Green
    "error" => @tui_core.Red
    "completed" => @tui_core.Blue
    _ => @tui_core.Gray
  }
  // Status indicator: colored dot + status text
  let status_text = "\{s.agent_status}"
  let model_text = "model: \{s.model_name}"
  let iter_text = "iter: \{s.iterations}"

  @view.View::container_views([
    @view.View::text(status_text, color=status_color),
    @view.View::text("  │  "),
    @view.View::text(model_text, color=@tui_core.BrightWhite),
    @view.View::text("  │  "),
    @view.View::text(iter_text, color=@tui_core.Cyan),
  ])
  .direction(Row)
  .padding(1.0)
  .background(@tui_core.RGB(0.15, 0.15, 0.2))
}
