///|
/// Compact "Thinking Live View" renderer for the TUI.
///
/// While the agent reasons, `TuiState.phase_stack` records the active
/// phase (e.g. "thinking", "tool_call"). This view composes the current
/// phase with a rotating thinking verb so the user gets live feedback
/// without a separate panel. Returns "" when the agent is idle (no
/// active phase on the stack).

///|
/// Render the current Thinking Live View line from TUI state.
fn render_thinking_live_view(state : TuiState) -> String {
  if state.phase_stack.is_empty() {
    return ""
  }
  let phase = state.phase_stack[state.phase_stack.length() - 1]
  let verb = ThinkingVerbAnimator::new().next()
  "Thinking Live ▸ \{phase} · \{verb}"
}
