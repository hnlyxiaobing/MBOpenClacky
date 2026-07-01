///|
/// Status bar component displaying agent status, model name, and iteration count.
///
/// Renders as a single row at the bottom of the TUI layout (above input).
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
  
  // Format: ● idle | c6f1feb6 | /mnt/d/MoonBit/MBOpenClacky | confirm_safes | or-gemini-3-1-pro | 0 tasks | $0.0
  let session_hash = if s.session_id.length() >= 8 { s.session_id.substring(end=8) } else { s.session_id }
  
  // Create parts
  let status_text = "● \{s.agent_status}"
  let sep = " | "
  let session_text = session_hash
  let dir_text = s.working_dir
  let perm_text = s.permission_mode
  let model_text = s.model_name
  let tasks_text = "\{s.active_tasks} tasks"
  
  // Format total cost properly. For now we use debug string interpolation.
  // Assuming total_cost is Double, let's round it manually or format.
  let cost_cents = (s.total_cost * 10000.0).to_int()
  let cost_str = "$\{cost_cents / 10000}.\{cost_cents % 10000}" // Simple workaround if formatting is tricky
  // Actually, let's just use Double to String.
  let cost_text = "$\{s.total_cost}"

  @view.View::container_views([
    @view.View::text(status_text, color=status_color),
    @view.View::text(sep, color=@tui_core.Gray),
    @view.View::text(session_text, color=@tui_core.Cyan),
    @view.View::text(sep, color=@tui_core.Gray),
    @view.View::text(dir_text, color=@tui_core.BrightWhite),
    @view.View::text(sep, color=@tui_core.Gray),
    @view.View::text(perm_text, color=@tui_core.Yellow),
    @view.View::text(sep, color=@tui_core.Gray),
    @view.View::text(model_text, color=@tui_core.Magenta),
    @view.View::text(sep, color=@tui_core.Gray),
    @view.View::text(tasks_text, color=@tui_core.BrightWhite),
    @view.View::text(sep, color=@tui_core.Gray),
    @view.View::text(cost_text, color=@tui_core.Green),
  ])
  .direction(Row)
  .background(@tui_core.RGB(0.15, 0.15, 0.2))
}
