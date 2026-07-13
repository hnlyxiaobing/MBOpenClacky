///| White-box tests for the Thinking Live View renderer (P1-6).

///|
fn tv_make_state() -> TuiState {
  TuiState::from_agent(make_test_agent())
}

///|
test "thinking live view is empty when idle" {
  let state = tv_make_state()
  assert_eq(render_thinking_live_view(state), "")
}

///|
test "thinking live view shows current phase and verb" {
  let state = tv_make_state()
  state.phase_stack.push("tool_call")
  let view = render_thinking_live_view(state)
  assert_true(view.contains("tool_call"))
  assert_true(view.contains("Thinking Live"))
  // The verb is always suffixed with an ellipsis.
  assert_true(view.contains("..."))
}
