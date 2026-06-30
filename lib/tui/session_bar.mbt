///|
/// Session bar component displaying session metadata in a single line.
///
/// Shows session ID, working directory, mode, model name, and cost.
/// Rendered between the content area and the input/status bar.

///|
/// Session bar data for rendering session-level metadata.
pub(all) struct SessionBar {
  /// Current session identifier (truncated for display).
  mut session_id : String
  /// Working directory path.
  mut working_dir : String
  /// Current TUI mode label.
  mut mode : String
  /// LLM model name.
  mut model : String
  /// Number of active tasks.
  mut task_count : Int
  /// Accumulated cost in USD.
  mut cost : Double
  /// Current agent status label.
  mut status : String
  /// Animation frame counter for spinner effects.
  mut animation_frame : Int
} derive(Debug)

///|
/// Create a new SessionBar with default empty values.
pub fn SessionBar::new() -> SessionBar {
  {
    session_id: "",
    working_dir: "",
    mode: "idle",
    model: "",
    task_count: 0,
    cost: 0.0,
    status: "idle",
    animation_frame: 0,
  }
}

///|
/// Render the session bar as a single-line View.
///
/// Output format:
///   [session: abcd1234]  dir: ~/proj  |  mode: auto  |  model: claude-3  |  $0.05
pub fn SessionBar::render(self : SessionBar) -> @view.View {
  let sid = if self.session_id.length() > 8 {
    self.session_id[0:8].to_string()
  } else {
    self.session_id
  }
  let dir_display = if self.working_dir.length() > 20 {
    "..." + self.working_dir[self.working_dir.length() - 17:].to_string()
  } else {
    self.working_dir
  }

  let session_text = "[session: \{sid}]"
  let dir_text = "dir: \{dir_display}"
  let mode_text = "mode: \{self.mode}"
  let model_text = "model: \{self.model}"
  let cost_text = "$\{format_session_cost(self.cost)}"

  @view.View::container_views([
    @view.View::text(session_text, color=@tui_core.Cyan),
    @view.View::text("  "),
    @view.View::text(dir_text, color=@tui_core.Gray),
    @view.View::text("  |  ", color=@tui_core.Gray),
    @view.View::text(mode_text, color=@tui_core.BrightWhite),
    @view.View::text("  |  ", color=@tui_core.Gray),
    @view.View::text(model_text, color=@tui_core.Blue),
    @view.View::text("  |  ", color=@tui_core.Gray),
    @view.View::text(cost_text, color=@tui_core.Green),
  ])
  .direction(Row)
  .padding(1.0)
  .background(@tui_core.RGB(0.12, 0.12, 0.18))
}

///|
/// Update session bar fields from the current TuiState.
pub fn SessionBar::update_from_state(
  self : SessionBar,
  state : TuiState,
) -> Unit {
  self.session_id = state.session_id
  self.mode = match state.mode {
    Idle => "idle"
    Running => "running"
  }
  self.model = state.model_name
  self.cost = state.total_cost
  self.status = state.agent_status
  self.animation_frame = self.animation_frame + 1
}

///|
/// Format cost for session bar display (2 decimal places).
fn format_session_cost(cost : Double) -> String {
  // Multiply by 100, round, then format manually
  let cents = (cost * 100.0).round().to_int()
  let dollars = cents / 100
  let remainder = cents - dollars * 100
  let remainder_str = if remainder < 10 {
    "0\{remainder}"
  } else {
    "\{remainder}"
  }
  "\{dollars}.\{remainder_str}"
}
