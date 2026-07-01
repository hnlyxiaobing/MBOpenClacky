///|
/// Session bar component — session metadata display.
///
/// Phase 0 stub: keeps the struct and data methods, removes onebit-tui
/// View rendering. Full inline rendering will be implemented in Phase 4.

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
/// Render the session bar as a formatted string (inline mode).
///
/// Returns a single-line ANSI string for direct terminal output.
pub fn SessionBar::render_line(self : SessionBar) -> String {
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
  let cost_str = format_session_cost(self.cost)
  "[session: \{sid}]  dir: \{dir_display}  |  mode: \{self.mode}  |  model: \{self.model}  |  $\{cost_str}"
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
/// Format cost for display with at least 4 decimal places.
///
/// Preserves extra precision if the value has more than 4 decimal digits.
/// Example: 0.0 → "0.0000", 1.5 → "1.5000", 0.123456 → "0.123456"
pub fn format_cost(cost : Double) -> String {
  let s = cost.to_string()
  if s.contains(".") {
    let parts = s.split(".").to_array()
    if parts.length() >= 2 {
      let decimals = parts[1]
      if decimals.length() >= 4 {
        s
      } else {
        s + String::repeat("0", 4 - decimals.length())
      }
    } else {
      s + ".0000"
    }
  } else {
    s + ".0000"
  }
}

///|
/// Format cost for session bar display (2 decimal places).
fn format_session_cost(cost : Double) -> String {
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
