///|
test "agent_interrupted_raise_catch" {
  try {
    raise AgentInterrupted("user cancelled")
  } catch {
    AgentInterrupted(msg) =>
      @debug.debug_inspect(
        msg,
        content=(
          #|"user cancelled"
        ),
      )
  }
}

///|
test "agent_error_raise_catch" {
  try {
    raise AgentError("something went wrong")
  } catch {
    AgentError(msg) =>
      @debug.debug_inspect(
        msg,
        content=(
          #|"something went wrong"
        ),
      )
  }
}

///|
test "bad_request_error_raise_catch" {
  try {
    raise BadRequestError(400, "invalid request")
  } catch {
    BadRequestError(status, msg) => {
      @debug.assert_eq(status, 400)
      @debug.debug_inspect(
        msg,
        content=(
          #|"invalid request"
        ),
      )
    }
  }
}

///|
test "tool_call_error_raise_catch" {
  try {
    raise ToolCallError("file_reader", "file not found")
  } catch {
    ToolCallError(tool_name, msg) => {
      @debug.debug_inspect(
        tool_name,
        content=(
          #|"file_reader"
        ),
      )
      @debug.debug_inspect(
        msg,
        content=(
          #|"file not found"
        ),
      )
    }
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
