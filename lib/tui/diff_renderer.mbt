///|
/// Diff renderer for displaying unified and side-by-side code diffs.
///
/// Parses unified diff format and renders with color-coded VNode text:
/// - Green for additions (+)
/// - Red for deletions (-)
/// - Cyan for hunk headers (@@)
/// - Gray for context lines

///|
/// Render a unified diff as a VNode tree with color coding.
pub fn render_diff_unified(diff : String) -> @tui.TuiNode {
  let children : Array[@tui.TuiNode] = []
  for line_view in diff.split("\n") {
    let line = line_view.to_owned()
    let vnode = if line.has_prefix("+++") {
      @tui.text(line, fg="rgb(85,255,85)", bold=true)
    } else if line.has_prefix("---") {
      @tui.text(line, fg="rgb(255,85,85)", bold=true)
    } else if line.has_prefix("+") {
      @tui.text(line, fg="rgb(85,255,85)")
    } else if line.has_prefix("-") {
      @tui.text(line, fg="rgb(255,85,85)")
    } else if line.has_prefix("@@") {
      @tui.text(line, fg="rgb(85,255,255)")
    } else if line.has_prefix("diff ") || line.has_prefix("index ") {
      @tui.text(line, fg="rgb(255,255,85)", bold=true)
    } else {
      @tui.text(line, fg="rgb(128,128,128)")
    }
    children.push(vnode)
  }
  if children.is_empty() {
    children.push(@tui.text(" "))
  }
  @tui.column(children)
}

///|
/// Render a side-by-side diff as a VNode tree.
pub fn render_diff_side_by_side(
  before : String,
  after : String,
) -> @tui.TuiNode {
  let before_lines : Array[String] = []
  for line_view in before.split("\n") {
    before_lines.push(line_view.to_owned())
  }
  let after_lines : Array[String] = []
  for line_view in after.split("\n") {
    after_lines.push(line_view.to_owned())
  }
  let max_lines = if before_lines.length() > after_lines.length() {
    before_lines.length()
  } else {
    after_lines.length()
  }
  let left_children : Array[@tui.TuiNode] = []
  let right_children : Array[@tui.TuiNode] = []
  for i = 0; i < max_lines; i = i + 1 {
    let left_line = if i < before_lines.length() { before_lines[i] } else { "" }
    let right_line = if i < after_lines.length() { after_lines[i] } else { "" }
    if left_line != right_line {
      left_children.push(@tui.text("- " + left_line, fg="rgb(255,85,85)"))
      right_children.push(@tui.text("+ " + right_line, fg="rgb(85,255,85)"))
    } else {
      left_children.push(@tui.text("  " + left_line, fg="rgb(128,128,128)"))
      right_children.push(@tui.text("  " + right_line, fg="rgb(128,128,128)"))
    }
  }
  @tui.row(gap=2.0, [
    @tui.column(flex_grow=1.0, left_children),
    @tui.column(flex_grow=1.0, right_children),
  ])
}

///|
/// Check if a string looks like a unified diff.
pub fn is_diff(text : String) -> Bool {
  (text.has_prefix("--- ") && text.contains("\n+++ ")) ||
  text.has_prefix("@@ ") ||
  text.has_prefix("diff --git")
}
