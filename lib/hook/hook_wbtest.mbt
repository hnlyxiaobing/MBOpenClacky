///|
test "parse_hook_event_before_tool_use" {
  let event = parse_hook_event("before_tool_use")
  @debug.assert_eq(event, Some(BeforeToolUse))
}

///|
test "parse_hook_event_after_tool_use" {
  let event = parse_hook_event("after_tool_use")
  @debug.assert_eq(event, Some(AfterToolUse))
}

///|
test "parse_hook_event_on_tool_error" {
  let event = parse_hook_event("on_tool_error")
  @debug.assert_eq(event, Some(OnToolError))
}

///|
test "parse_hook_event_on_start" {
  let event = parse_hook_event("on_start")
  @debug.assert_eq(event, Some(OnStart))
}

///|
test "parse_hook_event_on_iteration" {
  let event = parse_hook_event("on_iteration")
  @debug.assert_eq(event, Some(OnIteration))
}

///|
test "parse_hook_event_on_complete" {
  let event = parse_hook_event("on_complete")
  @debug.assert_eq(event, Some(OnComplete))
}

///|
test "parse_hook_event_session_rollback" {
  let event = parse_hook_event("session_rollback")
  @debug.assert_eq(event, Some(SessionRollback))
}

///|
test "parse_hook_event_invalid" {
  let event = parse_hook_event("unknown_event")
  assert_true(event is None)
}

///|
test "shell_hook_event_name_roundtrip" {
  let events = [
    BeforeToolUse,
    AfterToolUse,
    OnToolError,
    OnStart,
    OnIteration,
    OnComplete,
    SessionRollback,
  ]
  for event in events {
    let name = event.event_name()
    let parsed = parse_hook_event(name)
    @debug.assert_eq(parsed, Some(event))
  }
}

///|
test "hook_exec_result_variants" {
  let allow : HookExecResult = Allow
  let deny : HookExecResult = Deny("blocked")
  let err : HookExecResult = Error("timeout")
  @debug.assert_eq(allow, Allow)
  @debug.assert_eq(deny, Deny("blocked"))
  @debug.assert_eq(err, Error("timeout"))
}