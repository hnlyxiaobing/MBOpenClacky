///|
/// Status bar component — formats agent status into colored segments
/// for direct terminal rendering via ScreenBuffer.
///
/// The status bar is a single-line display showing:
/// ```text
/// ● idle │ c6f1feb6 │ /path/to/dir │ confirm_safes │ model-name │ 0 tasks │ $0.0
/// ```

///|
/// Color category for a status bar segment.
pub(all) enum SegmentColor {
  /// Status indicator — color depends on agent status text.
  Status
  /// Session ID (cyan).
  Session
  /// Working directory (white).
  Dir
  /// Permission mode (yellow).
  Permission
  /// Model name (magenta).
  Model
  /// Task count (white).
  Tasks
  /// Cost (green).
  Cost
  /// Separator / dim text (gray).
  Dim
  /// Default foreground.
  Default
} derive(Debug)

///|
pub extend SegmentColor with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// A single colored text segment.
pub(all) struct StatusSegment {
  text : String
  color : SegmentColor
} derive(Debug)

///|
pub extend StatusSegment with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// Status bar component that formats status data into colored segments.
pub(all) struct StatusBar {
  mut segments : Array[StatusSegment]
} derive(Debug)

///|
pub extend StatusBar with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// Create a new empty StatusBar.
pub fn StatusBar::new() -> StatusBar {
  { segments: [] }
}

///|
/// Spinner animation frames for the "working" state.
let spinner_frames : Array[String] = [
  "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏",
]

///|
/// Build status segments from TuiState.
///
/// Produces the standard status line:
/// `● <status> │ <session> │ <dir> │ <perm> │ <model> │ <n> tasks │ $<cost>`
///
/// When the agent is working (not idle), the status indicator uses
/// a spinner frame derived from `iterations` to animate on each Tick.
pub fn StatusBar::format_from_state(self : StatusBar, state : TuiState) -> Unit {
  self.segments.clear()
  // Status indicator: idle = ●, working = spinner frame
  let is_idle = state.agent_status.get() == "idle" ||
    state.mode is TuiMode::Idle
  let indicator = if is_idle {
    "● \{state.agent_status.get()}"
  } else {
    let frame_idx = state.tick_count % spinner_frames.length()
    "\{spinner_frames[frame_idx]} \{state.agent_status.get()}"
  }
  self.segments.push(StatusSegment::{
    text: indicator,
    color: SegmentColor::Status,
  })
  self.segments.push(StatusSegment::{ text: " │ ", color: Dim })
  // Session ID (truncated to 8 chars)
  let sid = if state.session_id.length() > 8 {
    state.session_id[0:8].to_owned()
  } else {
    state.session_id
  }
  self.segments.push(StatusSegment::{ text: sid, color: Session })
  self.segments.push(StatusSegment::{ text: " │ ", color: Dim })
  // Working directory (truncated)
  let dir = truncate_dir(state.working_dir, 30)
  self.segments.push(StatusSegment::{ text: dir, color: Dir })
  self.segments.push(StatusSegment::{ text: " │ ", color: Dim })
  // Permission mode
  self.segments.push(StatusSegment::{
    text: state.permission_mode,
    color: Permission,
  })
  self.segments.push(StatusSegment::{ text: " │ ", color: Dim })
  // Model name (truncated)
  let model = truncate_model(state.model_name, 24)
  self.segments.push(StatusSegment::{ text: model, color: Model })
  self.segments.push(StatusSegment::{ text: " │ ", color: Dim })
  // Task count
  let tasks = "\{state.active_tasks} tasks"
  self.segments.push(StatusSegment::{ text: tasks, color: Tasks })
  self.segments.push(StatusSegment::{ text: " │ ", color: Dim })
  // Cost (calls/iters are debug-only and live in `format_full`, SPEC-02)
  let cost = "$\{format_cost(state.total_cost)}"
  self.segments.push(StatusSegment::{ text: cost, color: Cost })
}

///|
/// Build a simplified status bar (just status + model + cost).
pub fn StatusBar::format_compact(
  self : StatusBar,
  status : String,
  model : String,
  cost : Double,
) -> Unit {
  self.segments.clear()
  let is_idle = status == "idle"
  let indicator = if is_idle {
    "● \{status}"
  } else {
    "\{spinner_frames[0]} \{status}"
  }
  self.segments.push(StatusSegment::{
    text: indicator,
    color: SegmentColor::Status,
  })
  self.segments.push(StatusSegment::{ text: "  ", color: Dim })
  self.segments.push(StatusSegment::{ text: model, color: Model })
  self.segments.push(StatusSegment::{ text: "  ", color: Dim })
  self.segments.push(StatusSegment::{
    text: "$\{format_cost(cost)}",
    color: Cost,
  })
}

///|
/// Build a full status bar with all available information.
///
/// Includes everything from `format_from_state` plus thinking status
/// indicator and latest token delta.
pub fn StatusBar::format_full(self : StatusBar, state : TuiState) -> Unit {
  self.format_from_state(state)
  // Debug-only fields omitted from the default status line (SPEC-02).
  self.segments.push(StatusSegment::{ text: " │ ", color: Dim })
  self.segments.push(StatusSegment::{
    text: "\{state.llm_call_count} calls",
    color: Tasks,
  })
  self.segments.push(StatusSegment::{ text: " │ ", color: Dim })
  self.segments.push(StatusSegment::{
    text: "\{state.iterations} iters",
    color: Tasks,
  })
  if is_thinking_phase_active(state) {
    self.segments.push(StatusSegment::{ text: " │ ", color: Dim })
    self.segments.push(StatusSegment::{
      text: "🧠 thinking",
      color: SegmentColor::Model,
    })
  }
  if state.latest_delta > 0 {
    self.segments.push(StatusSegment::{ text: " │ ", color: Dim })
    self.segments.push(StatusSegment::{
      text: "+\{state.latest_delta} tok",
      color: Tasks,
    })
  }
}

///|
/// Return the plain-text representation (no color codes).
pub fn StatusBar::plain_text(self : StatusBar) -> String {
  let sb = StringBuilder::new()
  for seg in self.segments {
    sb.write_string(seg.text)
  }
  sb.to_string()
}

///|
/// Return the colored ANSI representation with per-segment colors.
///
/// Each segment is wrapped in the appropriate ANSI SGR codes based on
/// its `SegmentColor`. Use this for terminal rendering instead of
/// `plain_text` when color output is desired.
pub fn StatusBar::colored_text(self : StatusBar) -> String {
  let sb = StringBuilder::new()
  for seg in self.segments {
    sb.write_string(segment_color_code(seg.color))
    sb.write_string(seg.text)
    sb.write_string("\u{1b}[0m")
  }
  sb.to_string()
}

///|
/// Return the ANSI SGR escape code for a given SegmentColor.
fn segment_color_code(color : SegmentColor) -> String {
  match color {
    // Status: green for idle, yellow for working
    Status => "\u{1b}[1m\u{1b}[38;2;0;255;100m"
    // Session ID: cyan
    Session => "\u{1b}[38;2;0;200;255m"
    // Working directory: white (bright)
    Dir => "\u{1b}[38;2;220;220;220m"
    // Permission mode: yellow
    Permission => "\u{1b}[38;2;255;255;85m"
    // Model name: magenta
    Model => "\u{1b}[38;2;200;100;255m"
    // Task count: white
    Tasks => "\u{1b}[38;2;220;220;220m"
    // Cost: green
    Cost => "\u{1b}[38;2;0;255;100m"
    // Dim separators
    Dim => "\u{1b}[2m"
    // Default foreground
    Default => "\u{1b}[0m"
  }
}

///|
/// Number of segments.
pub fn StatusBar::segment_count(self : StatusBar) -> Int {
  self.segments.length()
}

///|
/// Get a segment by index.
pub fn StatusBar::get_segment(self : StatusBar, i : Int) -> StatusSegment {
  self.segments[i]
}

///|
/// Truncate a directory path for display.
/// Shows the last `max_len` characters with "..." prefix if too long.
fn truncate_dir(path : String, max_len : Int) -> String {
  if path.length() <= max_len {
    path
  } else {
    "..." + path[path.length() - max_len + 3:].to_owned()
  }
}

///|
/// Truncate a model name for display.
fn truncate_model(name : String, max_len : Int) -> String {
  if name.length() <= max_len {
    name
  } else {
    name[0:max_len - 3].to_owned() + "..."
  }
}

///|
/// Format cost for display — up to 4 decimal places, no trailing zeros.
///
/// Rounds to 4 decimal places, strips trailing zeros, keeps at least one.
/// Example: 0.0 → "0.0", 1.5 → "1.5", 0.123456 → "0.1235"
pub fn format_cost(cost : Double) -> String {
  // Round to 4 decimal places by multiplying, rounding, then dividing
  let rounded = (cost * 10000.0).round() / 10000.0
  let s = rounded.to_string()
  if !s.contains(".") {
    return s + ".0"
  }
  let parts = s.split(".").to_array()
  let int_part = parts[0].to_owned()
  let mut dec = parts[1].to_owned()
  // Strip trailing zeros (but keep at least 1 digit)
  while dec.length() > 1 && dec.has_suffix("0") {
    dec = dec[0:dec.length() - 1].to_owned()
  }
  int_part + "." + dec
}

///|
/// Measure the display column width of a string, respecting CJK double-width.
fn display_width(s : String) -> Int {
  let mut w = 0
  for c in s.iter() {
    w = w + @tui_core.char_display_width(c)
  }
  w
}

///|
/// Truncate a directory path to fit within `max_w` display columns.
/// Shows the last portion with "..." prefix if too long.
fn truncate_dir_to_width(path : String, max_w : Int) -> String {
  let w = display_width(path)
  if w <= max_w {
    return path
  }
  let target = max_w - 3
  if target <= 0 {
    return "..."
  }
  let chars = path.to_array()
  let mut acc_w = 0
  let mut i = chars.length() - 1
  while i >= 0 {
    let cw = @tui_core.char_display_width(chars[i])
    if acc_w + cw > target {
      break
    }
    acc_w = acc_w + cw
    i = i - 1
  }
  let result = StringBuilder::new()
  result.write_string("...")
  let mut j = i + 1
  while j < chars.length() {
    result.write_char(chars[j])
    j = j + 1
  }
  result.to_string()
}

///|
/// Build status segments from TuiState with width-aware field degradation.
///
/// When the terminal is narrow, fields are dropped from lowest to highest
/// priority: directory → session → tasks → permission → cost → model.
/// The status indicator is always shown. The directory field is aggressively
/// compressed (truncated with "..." prefix) before being dropped entirely.
pub fn StatusBar::format_from_state_adaptive(
  self : StatusBar,
  state : TuiState,
  width : Int,
) -> Unit {
  self.segments.clear()
  let sep_w = 3 // " │ "
  let is_idle = state.agent_status.get() == "idle" ||
    state.mode is TuiMode::Idle
  let indicator = if is_idle {
    "● \{state.agent_status.get()}"
  } else {
    let frame_idx = state.tick_count % spinner_frames.length()
    "\{spinner_frames[frame_idx]} \{state.agent_status.get()}"
  }
  let model_name = truncate_model(state.model_name, 24)
  let cost_str = "$\{format_cost(state.total_cost)}"
  let sid = if state.session_id.length() > 8 {
    state.session_id[0:8].to_owned()
  } else {
    state.session_id
  }
  let dir_full = truncate_dir(state.working_dir, 30)
  let tasks_str = "\{state.active_tasks} tasks"

  // Phase 1: determine which optional fields fit (skip dir for now).
  let indicator_w = display_width(indicator)
  let mut budget = width - indicator_w

  let model_w = display_width(model_name)
  let has_model = budget >= sep_w + model_w
  if has_model {
    budget = budget - sep_w - model_w
  }

  let cost_w = display_width(cost_str)
  let has_cost = budget >= sep_w + cost_w
  if has_cost {
    budget = budget - sep_w - cost_w
  }

  let perm_w = display_width(state.permission_mode)
  let has_perm = budget >= sep_w + perm_w
  if has_perm {
    budget = budget - sep_w - perm_w
  }

  let tasks_w = display_width(tasks_str)
  let has_tasks = budget >= sep_w + tasks_w
  if has_tasks {
    budget = budget - sep_w - tasks_w
  }

  let sid_w = display_width(sid)
  let has_session = budget >= sep_w + sid_w
  if has_session {
    budget = budget - sep_w - sid_w
  }

  // Directory uses whatever budget remains (compressed if needed).
  let dir_budget = budget - sep_w
  let dir_compressed = truncate_dir_to_width(dir_full, dir_budget)
  let dir_actual_w = display_width(dir_compressed)
  let has_dir = dir_budget > 3 && budget >= sep_w + dir_actual_w

  // Phase 2: build segments in canonical display order.
  self.segments.push(StatusSegment::{
    text: indicator,
    color: SegmentColor::Status,
  })
  if has_session {
    self.segments.push(StatusSegment::{ text: " │ ", color: Dim })
    self.segments.push(StatusSegment::{ text: sid, color: Session })
  }
  if has_dir {
    self.segments.push(StatusSegment::{ text: " │ ", color: Dim })
    self.segments.push(StatusSegment::{ text: dir_compressed, color: Dir })
  }
  if has_perm {
    self.segments.push(StatusSegment::{ text: " │ ", color: Dim })
    self.segments.push(StatusSegment::{
      text: state.permission_mode,
      color: Permission,
    })
  }
  if has_model {
    self.segments.push(StatusSegment::{ text: " │ ", color: Dim })
    self.segments.push(StatusSegment::{ text: model_name, color: Model })
  }
  if has_tasks {
    self.segments.push(StatusSegment::{ text: " │ ", color: Dim })
    self.segments.push(StatusSegment::{ text: tasks_str, color: Tasks })
  }
  if has_cost {
    self.segments.push(StatusSegment::{ text: " │ ", color: Dim })
    self.segments.push(StatusSegment::{ text: cost_str, color: Cost })
  }
}
