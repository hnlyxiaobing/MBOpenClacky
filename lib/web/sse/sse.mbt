///| SSE (Server-Sent Events) formatting utilities.

///| Supports event IDs for resume, heartbeat comments, and retry directives.

///|
/// Captured hook event for batch SSE replay.
pub(all) struct CapturedHookEvent {
  event_type : String
  data : Json
  /// Sequential event ID for resume support.
  id : Int
}

///|
/// Build SSE event string with optional event ID:
/// "id: {id}\nevent: {type}\ndata: {json}\n\n"
pub fn format_sse_event(
  event_type : String,
  data : Json,
  id? : Int = -1,
) -> String {
  let data_str = data.to_string()
  if id >= 0 {
    "id: \{id}\nevent: \{event_type}\ndata: \{data_str}\n\n"
  } else {
    "event: \{event_type}\ndata: \{data_str}\n\n"
  }
}

///|
/// Build an SSE heartbeat comment.
/// SSE spec: lines starting with ":" are comments (ignored by client).
/// Used to keep the connection alive during long operations.
pub fn format_heartbeat() -> String {
  ": heartbeat\n\n"
}

///|
/// Build an SSE retry directive.
/// Tells the client to wait `ms` milliseconds before reconnecting.
pub fn format_retry_directive(ms : Int) -> String {
  "retry: \{ms}\n\n"
}

///|
/// Parse the Last-Event-ID header value from a request.
/// Returns the numeric event ID if valid, or -1 if not present/invalid.
pub fn parse_last_event_id(header_value : String?) -> Int {
  match header_value {
    Some(val) => {
      let trimmed = val.trim_start().trim_end()
      if trimmed.length() == 0 {
        return -1
      }
      let mut result = 0
      let mut i = 0
      while i < trimmed.length() {
        let c = trimmed[i]
        if c >= '0' && c <= '9' {
          result = result * 10 + (c.to_int() - '0'.to_int())
        } else {
          return -1
        }
        i = i + 1
      }
      result
    }
    None => -1
  }
}

///|
/// Convert a HookEvent into a CapturedHookEvent.
pub fn capture_hook_event(
  event : @agent.HookEvent,
  id? : Int = -1,
) -> CapturedHookEvent {
  match event {
    StatusChanged(_old, new) => {
      let j = Json::object({ "status": new.to_string_value().to_json() })
      { event_type: "status", data: j, id }
    }
    BeforeIteration(n) => {
      let j = Json::object({ "iteration": n.to_json() })
      { event_type: "iteration", data: j, id }
    }
    AfterIteration(n) => {
      let j = Json::object({ "iteration": n.to_json() })
      { event_type: "after_iteration", data: j, id }
    }
    BeforeLlmCall => {
      let j = Json::object({ "phase": "llm_call".to_json() })
      { event_type: "llm_start", data: j, id }
    }
    AfterLlmCall => {
      let j = Json::object({ "phase": "llm_call".to_json() })
      { event_type: "llm_end", data: j, id }
    }
    MessageAdded => {
      let j = Json::object({ "message": "added".to_json() })
      { event_type: "message_added", data: j, id }
    }
    ToolExecuting(name, args) => {
      let j = Json::object({
        "tool": name.to_json(),
        "arguments": args.to_json(),
      })
      { event_type: "tool_executing", data: j, id }
    }
    ToolExecuted(name, _result) => {
      let j = Json::object({ "tool": name.to_json() })
      { event_type: "tool_executed", data: j, id }
    }
    ErrorOccurred(msg) => {
      let j = Json::object({ "message": msg.to_json() })
      { event_type: "error", data: j, id }
    }
    RunCompleted(result) => {
      let j = Json::object({
        "status": result.status.to_string_value().to_json(),
        "session_id": result.session_id.to_json(),
        "iterations": result.iterations.to_json(),
        "total_cost_usd": result.total_cost_usd.to_json(),
      })
      { event_type: "done", data: j, id }
    }
    StreamChunk(chunk) => {
      let j = Json::object({ "chunk": chunk.to_json() })
      { event_type: "stream", data: j, id }
    }
    SessionStarted(session_id) => {
      let j = Json::object({ "session_id": session_id.to_json() })
      { event_type: "session_start", data: j, id }
    }
    SessionEnded(session_id) => {
      let j = Json::object({ "session_id": session_id.to_json() })
      { event_type: "session_end", data: j, id }
    }
    CostUpdated(cost) => {
      let j = Json::object({ "cost": cost.to_json() })
      { event_type: "cost", data: j, id }
    }
    WarningOccurred(msg) => {
      let j = Json::object({ "message": msg.to_json() })
      { event_type: "warning", data: j, id }
    }
    FileAccessed(path, op) => {
      let j = Json::object({ "path": path.to_json(), "op": op.to_json() })
      { event_type: "file", data: j, id }
    }
    ThinkingStarted => {
      let j = Json::object({ "phase": "thinking".to_json() })
      { event_type: "think_start", data: j, id }
    }
    ThinkingEnded => {
      let j = Json::object({ "phase": "thinking".to_json() })
      { event_type: "think_end", data: j, id }
    }
    SubagentStarted(name) => {
      let j = Json::object({ "agent": name.to_json() })
      { event_type: "subagent_start", data: j, id }
    }
    SubagentEnded(name) => {
      let j = Json::object({ "agent": name.to_json() })
      { event_type: "subagent_end", data: j, id }
    }
    RetryAttempt(n, reason) => {
      let j = Json::object({
        "attempt": n.to_json(),
        "reason": reason.to_json(),
      })
      { event_type: "retry", data: j, id }
    }
  }
}

///|
/// Build the complete SSE body from captured events and RunResult.
/// Supports resuming from a specific event ID via `resume_from`.
pub fn build_sse_body(
  events : Array[CapturedHookEvent],
  result : @agent.RunResult,
  resume_from? : Int = -1,
) -> String {
  let mut body = ""
  // Add retry directive (30 seconds)
  body = body + format_retry_directive(30000)
  let mut counter = 0
  for evt in events {
    counter = counter + 1
    // Skip events before the resume point
    if resume_from >= 0 && counter <= resume_from {
      ()
    } else {
      body = body + format_sse_event(evt.event_type, evt.data, id=counter)
    }
  }
  // Append final done event with RunResult
  let done_data = Json::object({
    "status": result.status.to_string_value().to_json(),
    "session_id": result.session_id.to_json(),
    "iterations": result.iterations.to_json(),
    "total_cost_usd": result.total_cost_usd.to_json(),
  })
  body = body + format_sse_event("done", done_data, id=counter + 1)
  body
}
