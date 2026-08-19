///| White-box tests for fake tool call detection.

///|
test "detect_fake_tool_call invoke pattern" {
  let content = "Let me help. " + "<" + "invoke name=\"search\">q</invoke>"
  assert_true(detect_fake_tool_call(content))
}

///|
test "detect_fake_tool_call function_calls pattern" {
  let content = "call: " + "<" + "function_calls>x</function_calls>"
  assert_true(detect_fake_tool_call(content))
}

///|
test "detect_fake_tool_call tool_use pattern" {
  let content = "resp: " + "<" + "tool_use name=\"search\">q</tool_use>"
  assert_true(detect_fake_tool_call(content))
}

///|
test "detect_fake_tool_call antml:invoke pattern" {
  let content = "x " + "<" + "antml:invoke name=\"search\">y</antml:invoke>"
  assert_true(detect_fake_tool_call(content))
}

///|
test "detect_fake_tool_call antml pattern" {
  let content = "x " + "<" + "antml:function_calls>y</antml:function_calls>"
  assert_true(detect_fake_tool_call(content))
}

///|
test "detect_fake_tool_call case-insensitive" {
  assert_true(detect_fake_tool_call("<INVOKE NAME=\"search\">q</INVOKE>"))
  assert_true(detect_fake_tool_call("<FUNCTION_CALLS>x</FUNCTION_CALLS>"))
  assert_true(detect_fake_tool_call("<TOOL_USE name=\"read\">"))
  assert_true(detect_fake_tool_call("<ANTML:INVOKE NAME=\"write\">"))
  assert_true(
    detect_fake_tool_call("<ANTML:FUNCTION_CALLS>y</ANTML:FUNCTION_CALLS>"),
  )
}

///|
test "detect_fake_tool_call not a tool_user false positive" {
  assert_true(!detect_fake_tool_call("the <tool_user> role is not a tool call"))
}

///|
test "detect_fake_tool_call normal content" {
  assert_true(!detect_fake_tool_call("Hello, how can I help you today?"))
}

///|
test "detect_fake_tool_call empty content" {
  assert_true(!detect_fake_tool_call(""))
}

///|
test "detect_fake_tool_call code discussion" {
  assert_true(
    !detect_fake_tool_call(
      "You can use the map function to transform elements.",
    ),
  )
}

///|
test "max_fake_tool_call_retries is 2" {
  @debug.assert_eq(max_fake_tool_call_retries, 2)
}
