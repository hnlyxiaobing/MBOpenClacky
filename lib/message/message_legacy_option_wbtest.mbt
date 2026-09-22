///|
/// Regression tests for the shapes an earlier build's broken `Option`
/// serializer persisted: `Some(x)` was written as `[x]`, which for
/// `tool_calls` produced a nested `[[...]]`.
///
/// These shapes are present in real session files on disk; before the
/// tolerance was added, every one of those sessions failed to decode
/// (`ToolCall: expected object`) and was skipped silently.

///|
/// Nested `tool_calls` with the wire key `type`.
let nested_tool_calls_doc =
  #|{"role":"assistant","content":"","tool_calls":[[{"id":"call_1","type":"function","function":{"name":"glob","arguments":"{\"pattern\":\"*\"}"}}]]}

///|
/// Nested `tool_calls` with the derived key `type_`.
let nested_type_underscore_doc =
  #|{"role":"assistant","content":"","tool_calls":[[{"id":"call_2","type_":"function","function":{"name":"read","arguments":"{}"}}]]}

///|
/// Scalar optionals persisted as single-element arrays.
let wrapped_scalars_doc =
  #|{"role":"tool","content":"ok","tool_call_id":["call_1"],"name":["glob"],"reasoning_content":["thought"]}

///|
/// Bool optionals persisted as single-element arrays.
let wrapped_bools_doc =
  #|{"role":"user","content":"ctx","session_context":[true],"system_injected":[false],"transient":[true]}

///|
/// The plain (current) shape.
let plain_option_doc =
  #|{"role":"tool","content":"ok","tool_call_id":"call_9","name":"read","tool_calls":[{"id":"call_9","type":"function","function":{"name":"read","arguments":"{}"}}]}

///|
/// Parse a persisted message document.
fn legacy_option_message(text : String) -> Message raise {
  let json = @json.parse(text)
  @json.from_json(json)
}

///|
test "ext_message_unwraps_nested_tool_calls" {
  let msg = legacy_option_message(nested_tool_calls_doc)
  let calls = msg.tool_calls.unwrap()
  @debug.assert_eq(calls.length(), 1)
  @debug.assert_eq(calls[0].id, "call_1")
  @debug.assert_eq(calls[0].type_, "function")
  @debug.assert_eq(calls[0].function.name, "glob")
}

///|
test "ext_message_accepts_type_underscore_key" {
  let msg = legacy_option_message(nested_type_underscore_doc)
  @debug.assert_eq(msg.tool_calls.unwrap()[0].type_, "function")
}

///|
test "ext_message_unwraps_scalar_option_fields" {
  let msg = legacy_option_message(wrapped_scalars_doc)
  // `tool_call_id` links the result to its call; losing it would break the
  // tool_use/tool_result pairing on restore.
  @debug.assert_eq(msg.tool_call_id, Some("call_1"))
  @debug.assert_eq(msg.name, Some("glob"))
  @debug.assert_eq(msg.reasoning_content, Some("thought"))
}

///|
test "ext_message_unwraps_bool_option_fields" {
  let msg = legacy_option_message(wrapped_bools_doc)
  @debug.assert_eq(msg.session_context, Some(true))
  @debug.assert_eq(msg.system_injected, Some(false))
  @debug.assert_eq(msg.transient, Some(true))
}

///|
/// The plain shape keeps working: the tolerance must not change what a
/// current file decodes to.
test "ext_message_plain_option_shape_is_unchanged" {
  let msg = legacy_option_message(plain_option_doc)
  @debug.assert_eq(msg.tool_call_id, Some("call_9"))
  @debug.assert_eq(msg.name, Some("read"))
  @debug.assert_eq(msg.tool_calls.unwrap().length(), 1)
}

///|
/// An empty or null tool_calls list stays empty rather than raising.
test "ext_message_empty_tool_calls_shapes" {
  let null_calls =
    #|{"role":"user","content":"hi","tool_calls":null}
  assert_true(legacy_option_message(null_calls).tool_calls is None)
  let empty_calls =
    #|{"role":"user","content":"hi","tool_calls":[]}
  @debug.assert_eq(
    legacy_option_message(empty_calls).tool_calls.unwrap().length(),
    0,
  )
}