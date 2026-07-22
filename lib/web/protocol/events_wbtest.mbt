///|
/// White-box tests for WS event JSON field alignment (spec-03).
/// Verifies that build_event and related functions produce flat JSON
/// structures matching what ws-dispatcher.js expects.
fn parse_json(s : String) -> Json {
  @json.parse(s) catch {
    _ => abort("failed to parse JSON")
  }
}

///|
fn get_str(j : Json, key : String) -> String {
  match j {
    Object(m) =>
      match m.get(key) {
        Some(String(v)) => v
        _ => abort("expected string at key: " + key)
      }
    _ => abort("expected object")
  }
}

///|
fn get_int(j : Json, key : String) -> Int {
  match j {
    Object(m) =>
      match m.get(key) {
        Some(Number(n, ..)) => n.to_int()
        _ => abort("expected number at key: " + key)
      }
    _ => abort("expected object")
  }
}

///|
fn get_bool(j : Json, key : String) -> Bool {
  match j {
    Object(m) =>
      match m.get(key) {
        Some(True) => true
        Some(False) => false
        _ => abort("expected bool at key: " + key)
      }
    _ => abort("expected object")
  }
}

///|
fn has_key(j : Json, key : String) -> Bool {
  match j {
    Object(m) => m.contains(key)
    _ => false
  }
}

///|
fn is_null(j : Json, key : String) -> Bool {
  match j {
    Object(m) =>
      match m.get(key) {
        Some(Null) => true
        _ => false
      }
    _ => false
  }
}

///|
test "build_event: flattens Object data into top level" {
  let result = build_event(
    "assistant_message",
    "sess-1",
    Json::object({
      "role": "assistant".to_json(),
      "content": "Hello!".to_json(),
    }),
  )
  let j = parse_json(result)
  @debug.assert_eq(get_str(j, "type"), "assistant_message")
  @debug.assert_eq(get_str(j, "session_id"), "sess-1")
  @debug.assert_eq(get_str(j, "content"), "Hello!")
  assert_false(has_key(j, "data"))
}

///|
test "build_global_event: flattens Object data without session_id" {
  let result = build_global_event(
    "session_list",
    Json::object({ "count": (3).to_json() }),
  )
  let j = parse_json(result)
  @debug.assert_eq(get_str(j, "type"), "session_list")
  @debug.assert_eq(get_int(j, "count"), 3)
  assert_false(has_key(j, "session_id"))
  assert_false(has_key(j, "data"))
}

///|
test "build_error_event: uses 'message' not 'error'" {
  let result = build_error_event("sess-1", "something went wrong")
  let j = parse_json(result)
  @debug.assert_eq(get_str(j, "type"), "error")
  @debug.assert_eq(get_str(j, "session_id"), "sess-1")
  @debug.assert_eq(get_str(j, "message"), "something went wrong")
  assert_false(has_key(j, "error"))
}

///|
test "build_subscribed_event: uses 'session_id' not 'target'" {
  let result = build_subscribed_event("sess-1")
  let j = parse_json(result)
  @debug.assert_eq(get_str(j, "type"), "subscribed")
  @debug.assert_eq(get_str(j, "session_id"), "sess-1")
  assert_false(has_key(j, "target"))
}

///|
test "build_session_list_event: includes has_more cron_count latest_cron_updated_at" {
  let result = build_session_list_event([])
  let j = parse_json(result)
  @debug.assert_eq(get_str(j, "type"), "session_list")
  @debug.assert_eq(get_bool(j, "has_more"), false)
  @debug.assert_eq(get_int(j, "cron_count"), 0)
  assert_true(is_null(j, "latest_cron_updated_at"))
}

///|
test "build_interrupted_event: only type and session_id, no data" {
  let result = build_interrupted_event("sess-1")
  let j = parse_json(result)
  @debug.assert_eq(get_str(j, "type"), "interrupted")
  @debug.assert_eq(get_str(j, "session_id"), "sess-1")
  assert_false(has_key(j, "data"))
}

///|
test "build_history_user_message: includes created_at and content" {
  let result = build_history_user_message("sess-1", "hello world")
  let j = parse_json(result)
  @debug.assert_eq(get_str(j, "type"), "history_user_message")
  @debug.assert_eq(get_str(j, "session_id"), "sess-1")
  @debug.assert_eq(get_str(j, "content"), "hello world")
  @debug.assert_eq(get_str(j, "role"), "user")
  assert_true(has_key(j, "created_at"))
}
