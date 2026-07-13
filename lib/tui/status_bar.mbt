///|
/// Status bar component — formats agent status into colored segments
/// for direct terminal rendering via ScreenBuffer.
///
/// The status bar is a single-line display showing:
/// ```text
/// ● idle | c6f1feb6 | /path/to/dir | confirm_safes | model-name | 0 tasks | $0.0000
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
/// A single colored text segment.
pub(all) struct StatusSegment {
  text : String
  color : SegmentColor
} derive(Debug)

///|
/// Status bar component that formats status data into colored segments.
pub(all) struct StatusBar {
  mut segments : Array[StatusSegment]
} derive(Debug)

///|
/// Create a new empty StatusBar.
pub fn StatusBar::new() -> StatusBar {
  { segments: [] }
}

///|
/// Build status segments from TuiState.
///
/// Produces the standard status line:
/// `● <status> | <session> | <dir> | <perm> | <model> | <n> tasks | $<cost>`
pub fn StatusBar::format_from_state(self : StatusBar, state : TuiState) -> Unit {
  self.segments.clear()
  // Status indicator with color hint
  let status_text = "● \{state.agent_status}"
  self.segments.push(StatusSegment::{
    text: status_text,
    color: SegmentColor::Status,
  })
  self.segments.push(StatusSegment::{ text: " | ", color: Dim })
  // Session ID (truncated to 8 chars)
  let sid = if state.session_id.length() > 8 {
    state.session_id[0:8].to_owned()
  } else {
    state.session_id
  }
  self.segments.push(StatusSegment::{ text: sid, color: Session })
  self.segments.push(StatusSegment::{ text: " | ", color: Dim })
  // Working directory (truncated)
  let dir = truncate_dir(state.working_dir, 30)
  self.segments.push(StatusSegment::{ text: dir, color: Dir })
  self.segments.push(StatusSegment::{ text: " | ", color: Dim })
  // Permission mode
  self.segments.push(StatusSegment::{
    text: state.permission_mode,
    color: Permission,
  })
  self.segments.push(StatusSegment::{ text: " | ", color: Dim })
  // Model name (truncated)
  let model = truncate_model(state.model_name, 24)
  self.segments.push(StatusSegment::{ text: model, color: Model })
  self.segments.push(StatusSegment::{ text: " | ", color: Dim })
  // Task count
  let tasks = "\{state.active_tasks} tasks"
  self.segments.push(StatusSegment::{ text: tasks, color: Tasks })
  self.segments.push(StatusSegment::{ text: " | ", color: Dim })
  // Cost
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
  self.segments.push(StatusSegment::{
    text: "● \{status}",
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
/// Return the plain-text representation (no color codes).
pub fn StatusBar::plain_text(self : StatusBar) -> String {
  let sb = StringBuilder::new()
  for seg in self.segments {
    sb.write_string(seg.text)
  }
  sb.to_string()
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
/// Format cost for display with at least 4 decimal places.
///
/// Preserves extra precision if the value has more than 4 decimal digits.
/// Example: 0.0 → "0.0000", 1.5 → "1.5000", 0.123456 → "0.123456"
///
/// Migrated from session_bar.mbt (deprecated, deleted in Phase 6.5).
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
