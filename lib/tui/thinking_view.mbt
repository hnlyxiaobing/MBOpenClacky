///|
/// Thinking Live View: real-time rendering of agent thinking/reasoning.
///
/// During the thinking phase, displays the last N lines of the thinking
/// buffer in a bordered panel. After thinking ends, shows a one-line summary.
/// Uses ThinkingVerbAnimator for dynamic status text.

///|
/// Maximum lines to display in the thinking view.
let thinking_max_display_lines = 5

///|
/// Maximum buffer size before truncating head (10KB).
let thinking_max_buffer_size = 10240

///|
/// Render the thinking live view as a Node tree.
///
/// Returns `Node::Empty` when there is no thinking content to display.
pub fn render_thinking_live_view(
  state : TuiState,
  animator : ThinkingVerbAnimator,
) -> Node {
  if state.thinking_buffer.get().length() == 0 {
    return Node::Empty
  }

  let is_active = is_thinking_phase_active(state)
  let verb = if is_active { animator.next() } else { "💭 Thought" }

  let lines = get_last_n_lines(
    state.thinking_buffer.get(),
    thinking_max_display_lines,
  )

  let children : Array[Node] = []
  children.push(
    Node::Text(
      verb,
      Style::new(fg=@color.Color::Basic(@color.BasicColor::Magenta), bold=true),
    ),
  )
  children.push(Node::Text("", Style::default_()))

  for line in lines {
    children.push(Node::Text(line, Style::new(dim=true)))
  }

  Node::Border(Some("Thinking"), children)
}

///|
/// Render a one-line summary of completed thinking.
pub fn render_thinking_summary(state : TuiState) -> Node {
  if state.thinking_buffer.get().length() == 0 {
    return Node::Empty
  }

  let char_count = state.thinking_buffer.get().length()
  let line_count = state.thinking_buffer.get().split("\n").to_array().length()
  let summary = "💭 Thought for \{char_count} chars (\{line_count} lines)"

  Node::Text(summary, Style::new(dim=true))
}

///|
/// Check if thinking is currently active by examining the phase stack.
pub fn is_thinking_phase_active(state : TuiState) -> Bool {
  for phase in state.phase_stack {
    if phase == "thinking" {
      return true
    }
  }
  false
}

///|
/// Get the last N lines from a multi-line string.
fn get_last_n_lines(text : String, n : Int) -> Array[String] {
  let all_lines = text.split("\n").to_array()
  let total = all_lines.length()
  if total == 0 {
    return []
  }
  let start = if total > n { total - n } else { 0 }
  let result : Array[String] = []
  for i in start..<total {
    let line = all_lines[i].to_owned()
    let display = if line.length() > 120 {
      line[0:117].to_owned() + "..."
    } else {
      line
    }
    result.push(display)
  }
  result
}

///|
/// Truncate thinking buffer if it exceeds the maximum size.
pub fn truncate_thinking_buffer(state : TuiState) -> Unit {
  if state.thinking_buffer.get().length() > thinking_max_buffer_size {
    let excess = state.thinking_buffer.get().length() - thinking_max_buffer_size
    state.thinking_buffer.set(state.thinking_buffer.get()[excess:].to_owned())
  }
}

///|
/// Render the thinking live view as a VNode tree directly.
///
/// Uses mizchi/tui's spinner component for animated status and returns
/// a bordered panel with the last N lines of thinking content.
/// Returns a text VNode with empty content when there is nothing to display.
pub fn render_thinking_live_vnode(
  state : TuiState,
  animator : ThinkingVerbAnimator,
  tick : Int,
) -> @vnode.TuiNode {
  if state.thinking_buffer.get().length() == 0 {
    return @vnode.text("")
  }

  let is_active = is_thinking_phase_active(state)
  let verb = if is_active { animator.next() } else { "Thought" }

  let lines = get_last_n_lines(
    state.thinking_buffer.get(),
    thinking_max_display_lines,
  )

  let children : Array[@vnode.TuiNode] = []
  // Animated header: spinner + verb
  if is_active {
    children.push(@tui_components.spinner(tick, label=verb))
  } else {
    children.push(@vnode.text("  " + verb, fg="magenta", bold=true))
  }

  // Separator
  children.push(@vnode.text(" "))

  // Thinking content lines (dimmed)
  for line in lines {
    children.push(@vnode.text(line, fg="rgb(128,128,128)"))
  }

  @vnode.view(
    direction="column",
    border="rounded",
    border_color="magenta",
    padding_x=1.0,
    children,
  )
}

///|
/// Render a one-line summary of completed thinking as a VNode.
pub fn render_thinking_summary_vnode(state : TuiState) -> @vnode.TuiNode {
  if state.thinking_buffer.get().length() == 0 {
    return @vnode.text("")
  }

  let char_count = state.thinking_buffer.get().length()
  let line_count = state.thinking_buffer.get().split("\n").to_array().length()
  let summary = "  Thought for \{char_count} chars (\{line_count} lines)"
  @vnode.text(summary, fg="rgb(128,128,128)")
}
