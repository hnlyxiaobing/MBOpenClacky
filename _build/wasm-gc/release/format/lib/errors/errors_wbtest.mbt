///|
test "agent_interrupted_raise_catch" {
  try {
    raise AgentInterrupted("user cancelled")
  } catch {
    AgentInterrupted(msg) => inspect(msg, content="user cancelled")
    _ => inspect("wrong", content="should not reach here")
  }
}

///|
test "agent_error_raise_catch" {
  try {
    raise AgentError("something went wrong")
  } catch {
    AgentError(msg) => inspect(msg, content="something went wrong")
    _ => inspect("wrong", content="should not reach here")
  }
}

///|
test "bad_request_error_raise_catch" {
  try {
    raise BadRequestError(400, "invalid request")
  } catch {
    BadRequestError(status, msg) => {
      assert_eq(status, 400)
      inspect(msg, content="invalid request")
    }
    _ => inspect("wrong", content="should not reach here")
  }
}

///|
test "tool_call_error_raise_catch" {
  try {
    raise ToolCallError("file_reader", "file not found")
  } catch {
    ToolCallError(tool_name, msg) => {
      inspect(tool_name, content="file_reader")
      inspect(msg, content="file not found")
    }
    _ => inspect("wrong", content="should not reach here")
  }
}

///|
test "is_agent_error" {
  assert_true(is_agent_error(AgentError("test")))
  assert_true(is_agent_error(BadRequestError(400, "test")))
  assert_true(is_agent_error(ToolCallError("tool", "test")))
  assert_true(is_agent_error(BrowserNotReachableError("test")))
  assert_false(is_agent_error(RetryableError("test")))
  assert_false(is_agent_error(AgentInterrupted("test")))
}

///|
test "is_retryable_error" {
  assert_true(is_retryable_error(RetryableError("test")))
  assert_true(is_retryable_error(UpstreamTruncatedError("test")))
  assert_false(is_retryable_error(AgentError("test")))
}
