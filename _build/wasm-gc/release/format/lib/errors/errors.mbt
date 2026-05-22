///| Agent was interrupted by user or system.

///|
/// Maps to Ruby's AgentInterrupted < Exception, which bypasses rescue StandardError.
pub suberror AgentInterrupted {
  AgentInterrupted(String)
} derive(ToJson, Debug)

///| Base error for agent-related errors.

///|
/// Maps to Ruby's AgentError < StandardError.
pub suberror AgentError {
  AgentError(String)
} derive(ToJson, Debug)

///| HTTP 400-level error from the LLM API.

///|
/// Maps to Ruby's BadRequestError < AgentError.
pub suberror BadRequestError {
  BadRequestError(Int, String)
} derive(ToJson, Debug)

///| Error during tool execution.

///|
/// Maps to Ruby's ToolCallError < AgentError.
pub suberror ToolCallError {
  ToolCallError(String, String)
} derive(ToJson, Debug)

///| Browser debugging port is not reachable.

///|
/// Maps to Ruby's BrowserNotReachableError < AgentError.
pub suberror BrowserNotReachableError {
  BrowserNotReachableError(String)
} derive(ToJson, Debug)

///| Transient error that warrants retry (5xx, rate limit, etc.).

///|
/// Maps to Ruby's RetryableError < StandardError.
pub suberror RetryableError {
  RetryableError(String)
} derive(ToJson, Debug)

///| Upstream API returned tool_calls with truncated/unparseable arguments.

///|
/// Maps to Ruby's UpstreamTruncatedError < RetryableError.
pub suberror UpstreamTruncatedError {
  UpstreamTruncatedError(String)
} derive(ToJson, Debug)

///| Check if an error is any of the agent-related error variants.

///|
/// Replicates Ruby's "rescue AgentError" catch-all behavior.
pub fn is_agent_error(err : Error) -> Bool {
  match err {
    AgentError(_) => true
    BadRequestError(_, _) => true
    ToolCallError(_, _) => true
    BrowserNotReachableError(_) => true
    _ => false
  }
}

///|
/// Check if an error is a retryable error variant.
pub fn is_retryable_error(err : Error) -> Bool {
  match err {
    RetryableError(_) => true
    UpstreamTruncatedError(_) => true
    _ => false
  }
}
