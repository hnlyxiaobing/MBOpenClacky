///| SSE (Server-Sent Events) formatting utilities.

///|
/// Captured hook event for batch SSE replay.
pub(all) struct CapturedHookEvent {
  event_type : String
  data : Json
}

///|
/// Build SSE event string: "event: {type}\ndata: {json}\n\n"
pub fn format_sse_event(event_type : String, data : Json) -> String {
  let data_str = data.to_string()
  "event: \{event_type}\ndata: \{data_str}\n\n"
}

///|
/// Convert a HookEvent into a CapturedHookEvent.
pub fn capture_hook_event(event : @agent.HookEvent) -> CapturedHookEvent {
  match event {
    StatusChanged(_old, new) => {
      let j = Json::object({ "status": new.to_string_value().to_json() })
      { event_type: "status", data: j }
    }
    BeforeIteration(n) => {
      let j = Json::object({ "iteration": n.to_json() })
      { event_type: "iteration", data: j }
    }
    AfterIteration(n) => {
      let j = Json::object({ "iteration": n.to_json() })
      { event_type: "after_iteration", data: j }
    }
    BeforeLlmCall => {
      let j = Json::object({ "phase": "llm_call".to_json() })
      { event_type: "llm_start", data: j }
    }
    AfterLlmCall => {
      let j = Json::object({ "phase": "llm_call".to_json() })
      { event_type: "llm_end", data: j }
    }
    MessageAdded => {
      let j = Json::object({ "message": "added".to_json() })
      { event_type: "message_added", data: j }
    }
    ToolExecuting(name, args) => {
      let j = Json::object({
        "tool": name.to_json(),
        "arguments": args.to_json(),
      })
      { event_type: "tool_executing", data: j }
    }
    ToolExecuted(name, _result) => {
      let j = Json::object({ "tool": name.to_json() })
      { event_type: "tool_executed", data: j }
    }
    ErrorOccurred(msg) => {
      let j = Json::object({ "message": msg.to_json() })
      { event_type: "error", data: j }
    }
    RunCompleted(result) => {
      let j = Json::object({
        "status": result.status.to_string_value().to_json(),
        "session_id": result.session_id.to_json(),
        "iterations": result.iterations.to_json(),
        "total_cost_usd": result.total_cost_usd.to_json(),
      })
      { event_type: "done", data: j }
    }
  }
}

///|
/// Build the complete SSE body from captured events and RunResult.
pub fn build_sse_body(
  events : Array[CapturedHookEvent],
  result : @agent.RunResult,
) -> String {
  let mut body = ""
  for evt in events {
    body = body + format_sse_event(evt.event_type, evt.data)
  }
  // Append final done event with RunResult
  let done_data = Json::object({
    "status": result.status.to_string_value().to_json(),
    "session_id": result.session_id.to_json(),
    "iterations": result.iterations.to_json(),
    "total_cost_usd": result.total_cost_usd.to_json(),
  })
  body = body + format_sse_event("done", done_data)
  body
}
