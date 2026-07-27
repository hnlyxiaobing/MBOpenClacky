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
test "detect_fake_tool_call tool_call pattern" {
  let content = "resp: " + "<" + "tool_call>search</tool_call>"
  assert_true(detect_fake_tool_call(content))
}

///|
test "detect_fake_tool_call antml pattern" {
  let content = "x " + "<" + "antml:function_calls>y</antml:function_calls>"
  assert_true(detect_fake_tool_call(content))
}

///|
test "detect_fake_tool_call functions pattern" {
  let content = "y " + "<" + "functions>z</functions>"
  assert_true(detect_fake_tool_call(content))
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
  assert_true(!detect_fake_tool_call("You can use the map function to transform elements."))
}

///|
test "max_fake_tool_call_retries is 2" {
  @debug.assert_eq(max_fake_tool_call_retries, 2)
}
