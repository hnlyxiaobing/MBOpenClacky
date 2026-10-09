///|
/// Regression test for BUG-0061: the ask_user family must not reach the browser
/// as a generic `tool_call` / `tool_result` pair.
///
/// Ruby's `WebUI::UIController#show_tool_call` handles the ask_user family by
/// emitting `request_feedback` and returning, and `#show_tool_result` is
/// skipped on the awaiting-feedback path — so the frontend renders the
/// interactive card exactly once.

///|
test "forwards_tool_frames suppresses the ask_user family" {
  // Both spellings route to the same tool (legacy alias included).
  assert_false(forwards_tool_frames("ask_user"))
  assert_false(forwards_tool_frames("request_user_feedback"))
  // Ordinary tools keep their tool_call / tool_result frames.
  assert_true(forwards_tool_frames("read_file"))
  assert_true(forwards_tool_frames("write"))
  assert_true(forwards_tool_frames("browser"))
}
