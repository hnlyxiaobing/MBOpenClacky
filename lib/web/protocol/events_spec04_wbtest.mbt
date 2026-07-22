///|
/// White-box tests for spec-04 new WS event mappings.
/// Verifies that new HookEvent variants and build_* functions produce
/// correct JSON structures matching ws-dispatcher.js expectations.

///|
test "map_hook_event: ToolStdout maps to tool_stdout" {
  let mapped = map_hook_event(@agent.ToolStdout("line1\nline2\n"))
  @debug.assert_eq(mapped.event_type, "tool_stdout")
  let lines = match mapped.data {
    Object(o) =>
      match o.get("lines") {
        Some(String(s)) => s
        _ => abort("expected lines string")
      }
    _ => abort("expected object")
  }
  @debug.assert_eq(lines, "line1\nline2\n")
}

///|
test "map_hook_event: InfoMessage maps to info" {
  let mapped = map_hook_event(@agent.InfoMessage("hello world"))
  @debug.assert_eq(mapped.event_type, "info")
  let msg = match mapped.data {
    Object(o) =>
      match o.get("message") {
        Some(String(s)) => s
        _ => abort("expected message string")
      }
    _ => abort("expected object")
  }
  @debug.assert_eq(msg, "hello world")
}

///|
test "map_hook_event: SuccessMessage maps to success" {
  let mapped = map_hook_event(@agent.SuccessMessage("done!"))
  @debug.assert_eq(mapped.event_type, "success")
  let msg = match mapped.data {
    Object(o) =>
      match o.get("message") {
        Some(String(s)) => s
        _ => abort("expected message string")
      }
    _ => abort("expected object")
  }
  @debug.assert_eq(msg, "done!")
}

///|
test "map_hook_event: FeedbackRequested maps to request_feedback" {
  let mapped = map_hook_event(
    @agent.FeedbackRequested(
      "What model?",
      Some("model selection"),
      Some(["gpt-4", "claude-3"]),
    ),
  )
  @debug.assert_eq(mapped.event_type, "request_feedback")
  let data = match mapped.data {
    Object(o) => o
    _ => abort("expected object")
  }
  let question = match data.get("question") {
    Some(String(s)) => s
    _ => abort("expected question string")
  }
  @debug.assert_eq(question, "What model?")
  let context = match data.get("context") {
    Some(String(s)) => s
    _ => abort("expected context string")
  }
  @debug.assert_eq(context, "model selection")
}

///|
test "map_hook_event: FeedbackRequested with null context and options" {
  let mapped = map_hook_event(@agent.FeedbackRequested("Continue?", None, None))
  @debug.assert_eq(mapped.event_type, "request_feedback")
  let data = match mapped.data {
    Object(o) => o
    _ => abort("expected object")
  }
  let question = match data.get("question") {
    Some(String(s)) => s
    _ => abort("expected question string")
  }
  @debug.assert_eq(question, "Continue?")
  match data.get("context") {
    Some(Null) => ()
    _ => abort("expected null context")
  }
  match data.get("options") {
    Some(Null) => ()
    _ => abort("expected null options")
  }
}

///|
test "build_session_renamed_event: produces correct JSON" {
  let json_str = build_session_renamed_event("sess-123", "My New Name")
  let j = parse_json(json_str)
  @debug.assert_eq(get_str(j, "type"), "session_renamed")
  @debug.assert_eq(get_str(j, "session_id"), "sess-123")
  @debug.assert_eq(get_str(j, "name"), "My New Name")
}

///|
test "build_session_deleted_event: produces correct JSON" {
  let json_str = build_session_deleted_event("sess-456")
  let j = parse_json(json_str)
  @debug.assert_eq(get_str(j, "type"), "session_deleted")
  @debug.assert_eq(get_str(j, "session_id"), "sess-456")
}

///|
test "build_task_finished_event: produces correct JSON without session_id wrapping" {
  let json_str = build_task_finished_event("sess-789")
  let j = parse_json(json_str)
  @debug.assert_eq(get_str(j, "type"), "task_finished")
  @debug.assert_eq(get_str(j, "session_id"), "sess-789")
}

///|
test "build_session_restored_event: produces correct JSON with nested session" {
  let session_json = Json::object({
    "id": "sess-abc".to_json(),
    "name": "Restored Session".to_json(),
  })
  let json_str = build_session_restored_event("sess-abc", session_json)
  let j = parse_json(json_str)
  @debug.assert_eq(get_str(j, "type"), "session_restored")
  @debug.assert_eq(get_str(j, "session_id"), "sess-abc")
  // Verify nested session object
  match j {
    Object(o) =>
      match o.get("session") {
        Some(Object(s)) => {
          match s.get("id") {
            Some(String(v)) => @debug.assert_eq(v, "sess-abc")
            _ => abort("expected id string in session")
          }
          match s.get("name") {
            Some(String(v)) => @debug.assert_eq(v, "Restored Session")
            _ => abort("expected name string in session")
          }
        }
        _ => abort("expected session object")
      }
    _ => abort("expected object")
  }
}
