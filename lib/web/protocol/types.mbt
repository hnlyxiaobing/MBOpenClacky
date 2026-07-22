///| WebSocket protocol types for the /ws endpoint.

///|

///| Defines upstream (client → server) message types and downstream

///| (server → client) event type constants aligned with the original

///| ws-dispatcher.js contract.

///|
/// Upstream message types (client → server).
/// Parsed from the `type` field of incoming JSON messages.
pub(all) enum UpstreamMessageType {
  /// Subscribe to a session's events (replaces previous session subscriptions).
  Subscribe
  /// Send a chat message to the agent.
  Message
  /// Edit the last user message and re-run.
  EditMessage
  /// Interrupt the current agent run.
  Interrupt
  /// Respond to a confirmation request.
  Confirmation
  /// Run a background task.
  RunTask
  /// Ping / keepalive.
  Ping
  /// Request the list of active sessions.
  ListSessions
}

///|
/// Parse an upstream message type from a string.
/// Returns None if the type is unrecognized.
pub fn parse_upstream_type(s : String) -> UpstreamMessageType? {
  match s {
    "subscribe" => Some(Subscribe)
    "message" => Some(Message)
    "edit_message" => Some(EditMessage)
    "interrupt" => Some(Interrupt)
    "confirmation" => Some(Confirmation)
    "run_task" => Some(RunTask)
    "ping" => Some(Ping)
    "list_sessions" => Some(ListSessions)
    _ => None
  }
}

// ── Downstream event type constants ─────────────────────────────
// These strings are used as the `type` field in JSON messages sent to
// clients. They must match the event names expected by ws-dispatcher.js.

///|
/// Connection established.
pub let event_connected : String = "connected"

///|
/// Subscription confirmed.
pub let event_subscribed : String = "subscribed"

///|
/// Session list update.
pub let event_session_list : String = "session_list"

///|
/// Full session snapshot (on subscribe).
pub let event_session_update : String = "session_update"

///|
/// Incremental session field change.
pub let event_session_updated : String = "session_updated"

///|
/// Echo of user message that was sent.
pub let event_history_user_message : String = "history_user_message"

///|
/// Complete assistant message (not token-level).
pub let event_assistant_message : String = "assistant_message"

///|
/// Tool invocation announced.
pub let event_tool_call : String = "tool_call"

///|
/// Tool arguments streamed.
pub let event_tool_args : String = "tool_args"

///|
/// Tool execution result.
pub let event_tool_result : String = "tool_result"

///|
/// Tool execution error.
pub let event_tool_error : String = "tool_error"

///|
/// Tool stdout output.
pub let event_tool_stdout : String = "tool_stdout"

///|
/// Generic progress update.
pub let event_progress : String = "progress"

///|
/// Agent run completed.
pub let event_complete : String = "complete"

///|
/// Agent asks for user confirmation.
pub let event_request_confirmation : String = "request_confirmation"

///|
/// Agent asks for user feedback.
pub let event_request_feedback : String = "request_feedback"

///|
/// Agent run interrupted.
pub let event_interrupted : String = "interrupted"

///|
/// Informational message.
pub let event_info : String = "info"

///|
/// Warning message.
pub let event_warning : String = "warning"

///|
/// Success message.
pub let event_success : String = "success"

///|
/// Error message.
pub let event_error : String = "error"

///|
/// Phase started (e.g. llm_call, thinking).
pub let event_phase_start : String = "phase_start"

///|
/// Phase ended.
pub let event_phase_end : String = "phase_end"

///|
/// Token usage update.
pub let event_token_usage : String = "token_usage"

///|
/// Diff preview.
pub let event_diff : String = "diff"

///|
/// File preview.
pub let event_file_preview : String = "file_preview"

///|
/// Shell command preview.
pub let event_shell_preview : String = "shell_preview"

///|
/// Todo list update.
pub let event_todo_update : String = "todo_update"

///|
/// Upgrade available notification.
pub let event_upgrade_available : String = "upgrade_available"

///|
/// Upgrade progress.
pub let event_upgrade_progress : String = "upgrade_progress"

///|
/// Server stopping.
pub let event_server_stop : String = "server_stop"

///|
/// Heartbeat pong.
pub let event_pong : String = "pong"

///|
/// Agent status change.
pub let event_status : String = "status"

///|
/// Cost update.
pub let event_cost_update : String = "cost_update"

///|
/// Build a downstream WS event JSON string.
/// Format: {"type": "<event_type>", "session_id": "<sid>", "data": {...}}
pub fn build_event(
  event_type : String,
  session_id : String,
  data : Json,
) -> String {
  Json::object({
    "type": event_type.to_json(),
    "session_id": session_id.to_json(),
    "data": data,
  }).stringify()
}

///|
/// Build a downstream WS event JSON string without session_id.
/// Format: {"type": "<event_type>", "data": {...}}
pub fn build_global_event(event_type : String, data : Json) -> String {
  Json::object({ "type": event_type.to_json(), "data": data }).stringify()
}

///|
/// Build a simple text error event.
pub fn build_error_event(session_id : String, message : String) -> String {
  build_event(
    event_error,
    session_id,
    Json::object({ "error": message.to_json() }),
  )
}

///|
/// Build a pong response.
pub fn build_pong() -> String {
  build_global_event(
    event_pong,
    Json::object({ "timestamp": @agent.current_time_ms().to_json() }),
  )
}

///|
/// Build a connected event.
pub fn build_connected_event(session_id : String) -> String {
  build_global_event(
    event_connected,
    Json::object({ "session_id": session_id.to_json() }),
  )
}

///|
/// Build a subscribed event.
pub fn build_subscribed_event(target : String) -> String {
  build_global_event(
    event_subscribed,
    Json::object({ "target": target.to_json() }),
  )
}

///|
/// Build a session_list event.
pub fn build_session_list_event(sessions : Array[Json]) -> String {
  build_global_event(
    event_session_list,
    Json::object({ "sessions": Json::array(sessions) }),
  )
}

///|
/// Build an interrupted event.
pub fn build_interrupted_event(session_id : String) -> String {
  build_event(
    event_interrupted,
    session_id,
    Json::object({ "session_id": session_id.to_json() }),
  )
}

///|
/// Build a history_user_message event echoing a user message.
pub fn build_history_user_message(
  session_id : String,
  content : String,
) -> String {
  build_event(
    event_history_user_message,
    session_id,
    Json::object({ "role": "user".to_json(), "content": content.to_json() }),
  )
}

///|
/// Build a confirmation response event.
pub fn build_confirmation_response(
  request_id : String,
  confirmed : Bool,
) -> String {
  build_global_event(
    "confirmation_response",
    Json::object({
      "request_id": request_id.to_json(),
      "confirmed": confirmed.to_json(),
    }),
  )
}
