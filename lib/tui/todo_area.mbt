///|
/// Todo area component — active task list display.
///
/// Phase 0 stub: keeps the struct and data methods, removes onebit-tui
/// View rendering. Full inline rendering will be implemented in Phase 6.

///|
/// A single display item in the todo area.
pub(all) struct TodoDisplayItem {
  /// Task ID.
  id : Int
  /// Task title.
  title : String
  /// Status label (pending, in_progress, completed, etc.).
  status : String
  /// Task description.
  description : String
} derive(Debug)

///|
/// Todo area widget for displaying active task list.
pub(all) struct TodoArea {
  /// Display items to render.
  mut items : Array[TodoDisplayItem]
  /// Number of completed tasks.
  mut completed_count : Int
  /// Total number of tasks.
  mut total_count : Int
  /// Whether the area is hidden.
  mut hidden : Bool
  /// Maximum number of items to display.
  max_display : Int
} derive(Debug)

///|
/// Create a new empty TodoArea.
pub fn TodoArea::new() -> TodoArea {
  {
    items: [],
    completed_count: 0,
    total_count: 0,
    hidden: true,
    max_display: 3,
  }
}

///|
/// Render the todo area as an array of ANSI strings (inline mode).
///
/// Returns one string per line for direct terminal output.
pub fn TodoArea::render_lines(self : TodoArea) -> Array[String] {
  if self.hidden || self.items.length() == 0 {
    return []
  }
  let lines : Array[String] = []
  let header = "Tasks [\{self.completed_count}/\{self.total_count}]:"
  lines.push(header)
  let limit = if self.items.length() < self.max_display {
    self.items.length()
  } else {
    self.max_display
  }
  let mut i = 0
  while i < limit {
    let item = self.items[i]
    let bullet = match item.status {
      "completed" => "✓"
      "in_progress" => "●"
      "cancelled" => "✗"
      "failed" => "✗"
      _ => "○"
    }
    lines.push("  \{bullet} #\{item.id} - \{item.title}")
    i = i + 1
  }
  if self.items.length() > self.max_display {
    let remaining = self.items.length() - self.max_display
    lines.push("  ... and \{remaining} more")
  }
  lines
}

///|
/// Update the todo area with new items and counts.
pub fn TodoArea::update(
  self : TodoArea,
  items : Array[TodoDisplayItem],
  completed : Int,
  total : Int,
) -> Unit {
  self.items = items
  self.completed_count = completed
  self.total_count = total
  if items.length() > 0 {
    self.hidden = false
  }
}

///|
/// Hide the todo area.
pub fn TodoArea::hide(self : TodoArea) -> Unit {
  self.hidden = true
}

///|
/// Show the todo area.
pub fn TodoArea::show(self : TodoArea) -> Unit {
  self.hidden = false
}

///|
/// Check whether the todo area is visible.
pub fn TodoArea::visible(self : TodoArea) -> Bool {
  !self.hidden && self.items.length() > 0
}
