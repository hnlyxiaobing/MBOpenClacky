///|
/// Todo area component displaying active tasks above the message area.
///
/// Shows up to max_display tasks with their status indicators.
/// Can be hidden/shown dynamically based on whether tasks exist.

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
/// Render the todo area as a View.
///
/// Shows up to max_display items with status bullets:
/// ```
/// Tasks [2/5]:
///   ● #3 - Current task description
///   ○ #4 - Pending task
/// ```
pub fn TodoArea::render(self : TodoArea) -> @view.View {
  if self.hidden || self.items.length() == 0 {
    return @view.View::container_views([])
  }

  let children : Array[@view.View] = []

  // Header line
  let header = "Tasks [\{self.completed_count}/\{self.total_count}]:"
  children.push(@view.View::text(header, color=@tui_core.Yellow))

  // Render up to max_display items
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
    let bullet_color = match item.status {
      "completed" => @tui_core.Green
      "in_progress" => @tui_core.Cyan
      "cancelled" => @tui_core.Gray
      "failed" => @tui_core.Red
      _ => @tui_core.Gray
    }
    let line = "  \{bullet} #\{item.id} - \{item.title}"
    children.push(@view.View::text(line, color=bullet_color))
    i = i + 1
  }

  // Show overflow indicator
  if self.items.length() > self.max_display {
    let remaining = self.items.length() - self.max_display
    children.push(
      @view.View::text("  ... and \{remaining} more", color=@tui_core.Gray),
    )
  }

  @view.View::container_views(children)
  .padding(1.0)
  .background(@tui_core.RGB(0.1, 0.1, 0.14))
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
