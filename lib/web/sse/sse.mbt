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

///| Convert a HookEvent into a CapturedHookEvent.
pub fn capture_hook_event(event : @agent.HookEvent) -> CapturedHookEvent {
  match event {
    StatusChanged(_old, new) => {
      let j = { "status": new.to_string_value() } : Json
      { event_type: "status", data: j }
    }
    BeforeIteration(n) => {
      let j = { "iteration": n } : Json
      { event_type: "iteration", data: j }
    }
    AfterIteration(n) => {
      let j = { "iteration": n } : Json
      { event_type: "after_iteration", data: j }
    }
    BeforeLlmCall => {
      let j = { "phase": "llm_call" } : Json
      { event_type: "llm_start", data: j }
    }
    AfterLlmCall => {
      let j = { "phase": "llm_call" } : Json
      { event_type: "llm_end", data: j }
    }
    MessageAdded => {
      let j = { "message": "added" } : Json
      { event_type: "message_added", data: j }
    }
    ToolExecuting(name, args) => {
      let j = { "tool": name, "arguments": args } : Json
      { event_type: "tool_executing", data: j }
    }
    ToolExecuted(name, _result) => {
      let j = { "tool": name } : Json
      { event_type: "tool_executed", data: j }
    }
    ErrorOccurred(msg) => {
      let j = { "message": msg } : Json
      { event_type: "error", data: j }
    }
    RunCompleted(result) => {
      let j = {
        "status": result.status.to_string_value(),
        "session_id": result.session_id,
        "iterations": result.iterations,
        "total_cost_usd": result.total_cost_usd,
      } : Json
      { event_type: "done", data: j }
    }
  }
}


///| Build the complete SSE body from captured events and RunResult.
pub fn build_sse_body(events : Array[CapturedHookEvent], result : @agent.RunResult) -> String {
  let mut body = ""
  for evt in events {
    body = body + format_sse_event(evt.event_type, evt.data)
  }
  // Append final done event with RunResult
  let done_data = {
    "status": result.status.to_string_value(),
    "session_id": result.session_id,
    "iterations": result.iterations,
    "total_cost_usd": result.total_cost_usd,
  } : Json
  body = body + format_sse_event("done", done_data)
  body
}
