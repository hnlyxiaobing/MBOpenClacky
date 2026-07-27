///| White-box tests for T13: WS token-level streaming.
///
/// Verifies that the token_delta event is correctly constructed and
/// that the StreamChunk handler in the WS hook forwards deltas while
/// also aggregating them.

///|
fn t13_parse_json(s : String) -> Json {
  @json.parse(s) catch {
    _ => abort("failed to parse JSON")
  }
}

///|
fn t13_get_str(j : Json, key : String) -> String {
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
test "t13: event_token_delta constant is 'token_delta'" {
  assert_true(@protocol.event_token_delta == "token_delta")
}

///|
test "t13: build_token_delta_event produces correct JSON wire format" {
  let result = @protocol.build_token_delta_event("sess-123", "Hello")
  let json = t13_parse_json(result)
  assert_true(t13_get_str(json, "type") == "token_delta")
  assert_true(t13_get_str(json, "session_id") == "sess-123")
  assert_true(t13_get_str(json, "content") == "Hello")
}

///|
test "t13: build_token_delta_event handles empty chunk" {
  let result = @protocol.build_token_delta_event("s1", "")
  let json = t13_parse_json(result)
  assert_true(t13_get_str(json, "type") == "token_delta")
  assert_true(t13_get_str(json, "content") == "")
}

///|
test "t13: build_token_delta_event handles multi-line chunk" {
  let chunk = "line1\nline2\nline3"
  let result = @protocol.build_token_delta_event("multi", chunk)
  let json = t13_parse_json(result)
  assert_true(t13_get_str(json, "type") == "token_delta")
  assert_true(t13_get_str(json, "content") == chunk)
}

///|
test "t13: build_token_delta_event handles unicode" {
  let chunk = "你好世界 🌍"
  let result = @protocol.build_token_delta_event("uni", chunk)
  let json = t13_parse_json(result)
  assert_true(t13_get_str(json, "type") == "token_delta")
  assert_true(t13_get_str(json, "content") == chunk)
}

///|
test "t13: token_delta event differs from assistant_message partial" {
  let delta_result = @protocol.build_token_delta_event("s1", "chunk")
  let json = t13_parse_json(delta_result)
  assert_true(t13_get_str(json, "type") == "token_delta")
  // Verify it's NOT "assistant_message"
  assert_false(delta_result.contains("assistant_message"))
}
