///| Agent was interrupted by user or system.

///|
/// Maps to Ruby's AgentInterrupted < Exception, which bypasses rescue StandardError.
pub(all) suberror AgentInterrupted {
  AgentInterrupted(String)
} derive(ToJson, Debug)

///|
pub extend AgentInterrupted with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend AgentInterrupted with ToJson::{to_json}

///| Base error for agent-related errors.

///|
/// Maps to Ruby's AgentError < StandardError.
pub(all) suberror AgentError {
  AgentError(String)
} derive(ToJson, Debug)

///|
pub extend AgentError with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend AgentError with ToJson::{to_json}

///| HTTP 400-level error from the LLM API.

///|
/// Maps to Ruby's BadRequestError < AgentError.
pub(all) suberror BadRequestError {
  BadRequestError(Int, String)
} derive(ToJson, Debug)

///|
pub extend BadRequestError with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend BadRequestError with ToJson::{to_json}

///| Error during tool execution.

///|
/// Maps to Ruby's ToolCallError < AgentError.
pub(all) suberror ToolCallError {
  ToolCallError(String, String)
} derive(ToJson, Debug)

///|
pub extend ToolCallError with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ToolCallError with ToJson::{to_json}

///| Browser debugging port is not reachable.

///|
/// Maps to Ruby's BrowserNotReachableError < AgentError.
pub(all) suberror BrowserNotReachableError {
  BrowserNotReachableError(String)
} derive(ToJson, Debug)

///|
pub extend BrowserNotReachableError with @moonbitlang/core/debug.Debug::{
  to_repr,
}

///|
pub extend BrowserNotReachableError with ToJson::{to_json}

///| Transient error that warrants retry (5xx, rate limit, etc.).

///|
/// Maps to Ruby's RetryableError < StandardError.
pub(all) suberror RetryableError {
  RetryableError(String)
} derive(ToJson, Debug)

///|
pub extend RetryableError with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend RetryableError with ToJson::{to_json}

///| Upstream API returned tool_calls with truncated/unparseable arguments.

///|
/// Maps to Ruby's UpstreamTruncatedError < RetryableError.
pub(all) suberror UpstreamTruncatedError {
  UpstreamTruncatedError(String)
} derive(ToJson, Debug)

///|
pub extend UpstreamTruncatedError with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend UpstreamTruncatedError with ToJson::{to_json}

///| Extract a human-readable message from an error.

///|
/// The default `Error::to_string()` only prints the package path and
/// constructor name; this pulls out the embedded message instead.
/// Falls back to `to_string()` for unknown error types.
pub fn error_message(err : Error) -> String {
  match err {
    AgentInterrupted(msg) => msg
    AgentError(msg) => msg
    BadRequestError(code, msg) => "[HTTP \{code}] \{msg}"
    ToolCallError(name, msg) => "[Tool: \{name}] \{msg}"
    BrowserNotReachableError(msg) => msg
    RetryableError(msg) => msg
    UpstreamTruncatedError(msg) => msg
    _ => err.to_string()
  }
}

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
