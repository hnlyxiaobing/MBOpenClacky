///| White-box tests for SSE formatting utilities.

///|
/// `format_sse_event` must serialize the data payload as valid JSON
/// (via `Json::stringify`), not MoonBit debug representation.
test "format_sse_event emits valid JSON data line" {
  let event = format_sse_event(
    "status",
    Json::object({ "status": "running".to_json() }),
  )
  // Data line must be parseable JSON containing the raw fields,
  // not debug format like `Object({ "status": String("running") })`.
  assert_true(event.contains("data: {\"status\":\"running\"}"))
  assert_true(event.contains("event: status"))
  assert_false(event.contains("String("))
  // Round-trip: extract the data line and parse it back as JSON.
  let data_line = event
    .split("\n")
    .filter(fn(line) { line.has_prefix("data: ") })
    .collect()[0]
  let payload = data_line.replace(old="data: ", new="")
  let parsed : Json = @json.parse(payload)
  match parsed {
    Object(map) =>
      match map.get("status") {
        Some(String(s)) => assert_eq(s, "running")
        _ => fail("expected status field to be a string")
      }
    _ => fail("expected parsed payload to be a JSON object")
  }
}

///|
/// With an explicit event id, the output must include the `id:` line
/// and still emit valid JSON.
test "format_sse_event includes id line when id >= 0" {
  let event = format_sse_event(
    "stream",
    Json::object({ "chunk": "hello".to_json() }),
    id=7,
  )
  assert_true(event.has_prefix("id: 7\n"))
  assert_true(event.contains("data: {\"chunk\":\"hello\"}"))
  assert_true(event.has_suffix("\n\n"))
}
