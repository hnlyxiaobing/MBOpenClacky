///|
/// TUI layout: output area + bottom fixed area, aligned with Ruby ui2.
///
/// Single layout (the old GeminiLike/ClaudeCodeLike/Compact brand templates
/// were removed — only the Ruby-aligned structure remains):
/// ```text
/// ┌─────────────────────────┐
/// │ Output Area (flex)      │
/// │ ...                     │
/// ├─────────────────────────┤  fixed area:
/// │ Session/Status Bar (1)  │
/// │ Separator (1)           │
/// │ Attachments (0-N)       │
/// │ Input Lines (1-N wrap)  │
/// │ Separator (1)           │
/// │ Suggestions (0-N)       │
/// │ Tips (0-1)              │
/// └─────────────────────────┘
/// ```
/// The top of the screen must belong to the output area: only rows scrolled
/// off the top enter the terminal scrollback (commit-scrollback model).

///|
/// Build the main layout VNode: flex output area above the bottom fixed area.
///
/// `todo_children` are the todo-area rows rendered directly above the status
/// bar (Ruby ui2 layout order: output / gap / todo / input). `fixed_children`
/// are the rows below the status bar (separators, attachments, input lines,
/// suggestions, tips) in top-to-bottom order; each child must render exactly
/// one terminal row so the fixed-area height stays
/// `todo_children.length() + 1 + fixed_children.length()` — the
/// commit-scrollback overflow math depends on it.
pub fn build_main_layout(
  status_node : @vnode.TuiNode,
  output_children : Array[@vnode.TuiNode],
  todo_children : Array[@vnode.TuiNode],
  fixed_children : Array[@vnode.TuiNode],
  term_width : Double,
) -> @vnode.TuiNode {
  if output_children.is_empty() {
    output_children.push(@vnode.text(" "))
  }
  // NOTE: width is the real terminal width in columns. The DSL interprets a
  // numeric width as DimensionValue::Length (absolute columns), NOT percent —
  // the old hardcoded 100.0 clipped the ~118-column status bar to 100 cols and
  // flex-shrunk its space-containing segments (see SPEC-01).
  let children : Array[@vnode.TuiNode] = [
    @vnode.column(flex_grow=1.0, width=term_width, output_children),
  ]
  for child in todo_children {
    children.push(child)
  }
  children.push(status_node)
  for child in fixed_children {
    children.push(child)
  }
  @vnode.column(width=term_width, height=100.0, children)
}

///|
/// Build a dim horizontal separator row spanning the terminal width
/// (Ruby ui2 render_separator).
pub fn separator_node(term_width : Int) -> @vnode.TuiNode {
  @vnode.text("─".repeat(term_width), fg="rgb(128,128,128)")
}
