///| Event mapping: agent HookEvent → WS downstream events.

///|

///| Converts agent-internal hook events into JSON payloads suitable for

///| WebSocket transmission. The event names and field structures are aligned

///| with the original ws-dispatcher.js contract.

///|
/// A mapped WS event: the downstream event type name and its JSON data payload.
pub(all) struct MappedWsEvent {
  /// Downstream event type (e.g. "tool_call", "phase_start").
  event_type : String
  /// Event data payload.
  data : Json
}

///|
/// Convert an agent HookEvent into a MappedWsEvent.
/// This is the single source of truth for event name and field mapping
/// shared by both the WS push path and the REST history path.
pub fn map_hook_event(event : @agent.HookEvent) -> MappedWsEvent {
  match event {
    StatusChanged(_old, new) =>
      {
        event_type: "status",
        data: Json::object({ "status": new.to_string_value().to_json() }),
      }
    BeforeIteration(n) =>
      {
        event_type: "progress",
        data: Json::object({
          "iteration": n.to_json(),
          "phase": "iteration_start".to_json(),
        }),
      }
    AfterIteration(n) =>
      {
        event_type: "progress",
        data: Json::object({
          "iteration": n.to_json(),
          "phase": "iteration_end".to_json(),
        }),
      }
    BeforeLlmCall =>
      {
        event_type: "phase_start",
        data: Json::object({ "phase": "llm_call".to_json() }),
      }
    AfterLlmCall =>
      {
        event_type: "phase_end",
        data: Json::object({ "phase": "llm_call".to_json() }),
      }
    MessageAdded =>
      {
        event_type: "progress",
        data: Json::object({ "phase": "message_added".to_json() }),
      }
    ToolExecuting(name, args) =>
      {
        event_type: "tool_call",
        data: Json::object({
          "tool": name.to_json(),
          "arguments": args.to_json(),
        }),
      }
    ToolExecuted(name, result) => {
      let is_err = result.is_error
      let output = result.content
      if is_err {
        {
          event_type: "tool_error",
          data: Json::object({
            "tool": name.to_json(),
            "error": output.to_json(),
          }),
        }
      } else {
        {
          event_type: "tool_result",
          data: Json::object({
            "tool": name.to_json(),
            "output": output.to_json(),
          }),
        }
      }
    }
    ErrorOccurred(msg) =>
      { event_type: "error", data: Json::object({ "error": msg.to_json() }) }
    RunCompleted(result) => {
      let err_field : Json = match result.error {
        Some(e) => e.to_json()
        None => Json::null()
      }
      {
        event_type: "complete",
        data: Json::object({
          "status": result.status.to_string_value().to_json(),
          "session_id": result.session_id.to_json(),
          "iterations": result.iterations.to_json(),
          "total_cost_usd": result.total_cost_usd.to_json(),
          "error": err_field,
        }),
      }
    }
    // NOTE: the WS push path aggregates StreamChunk into a single complete
    // assistant_message in the WS adapter (spec decision 3); this branch is
    // only a pure mapping for non-WS consumers.
    StreamChunk(chunk) =>
      {
        event_type: "assistant_message",
        data: Json::object({
          "role": "assistant".to_json(),
          "content": chunk.to_json(),
          "partial": true.to_json(),
        }),
      }
    SessionStarted(session_id) =>
      {
        event_type: "session_update",
        data: Json::object({
          "session_id": session_id.to_json(),
          "phase": "started".to_json(),
        }),
      }
    SessionEnded(session_id) =>
      {
        event_type: "session_update",
        data: Json::object({
          "session_id": session_id.to_json(),
          "phase": "ended".to_json(),
        }),
      }
    CostUpdated(cost) =>
      {
        event_type: "token_usage",
        data: Json::object({ "total_cost_usd": cost.to_json() }),
      }
    WarningOccurred(msg) =>
      {
        event_type: "warning",
        data: Json::object({ "message": msg.to_json() }),
      }
    FileAccessed(path, op) =>
      {
        event_type: "file_preview",
        data: Json::object({ "path": path.to_json(), "op": op.to_json() }),
      }
    ThinkingStarted =>
      {
        event_type: "phase_start",
        data: Json::object({ "phase": "thinking".to_json() }),
      }
    ThinkingEnded =>
      {
        event_type: "phase_end",
        data: Json::object({ "phase": "thinking".to_json() }),
      }
    SubagentStarted(name) =>
      {
        event_type: "phase_start",
        data: Json::object({
          "phase": "subagent".to_json(),
          "agent": name.to_json(),
        }),
      }
    SubagentEnded(name) =>
      {
        event_type: "phase_end",
        data: Json::object({
          "phase": "subagent".to_json(),
          "agent": name.to_json(),
        }),
      }
    RetryAttempt(n, reason) =>
      {
        event_type: "progress",
        data: Json::object({
          "phase": "retry".to_json(),
          "attempt": n.to_json(),
          "reason": reason.to_json(),
        }),
      }
    ToolDenied(name) =>
      {
        event_type: "tool_denied",
        data: Json::object({ "tool": name.to_json() }),
      }
    UsageUpdated(data) =>
      {
        event_type: "token_usage",
        data: Json::object({
          "input_tokens": data.prompt_tokens.to_json(),
          "output_tokens": data.completion_tokens.to_json(),
          "delta_tokens": data.delta_tokens.to_json(),
          "total_tokens": data.total_tokens.to_json(),
          "cost_usd": data.cost.to_json(),
        }),
      }
  }
}

///|
/// Build the full JSON wire string for a mapped hook event, scoped to a session.
pub fn format_hook_event(
  session_id : String,
  event : @agent.HookEvent,
) -> String {
  let mapped = map_hook_event(event)
  Json::object({
    "type": mapped.event_type.to_json(),
    "session_id": session_id.to_json(),
    "data": mapped.data,
  }).stringify()
}

///|
/// Build a session_update snapshot event from a SessionData.
/// This is sent on initial subscribe to give the client a full state picture.
pub fn build_session_snapshot(data : @agent.SessionData) -> String {
  let messages_arr : Array[Json] = []
  for msg in data.messages {
    messages_arr.push(msg.to_json())
  }
  let model_field : Json = match data.model_name {
    Some(m) => m.to_json()
    None => Json::null()
  }
  Json::object({
    "type": "session_update".to_json(),
    "session_id": data.session_id.to_json(),
    "data": Json::object({
      "session_id": data.session_id.to_json(),
      "name": data.name.to_json(),
      "status": data.last_status.to_json(),
      "working_dir": data.working_dir.to_json(),
      "model": model_field,
      "created_at": data.created_at.to_json(),
      "total_tasks": data.stats.total_tasks.to_json(),
      "total_cost_usd": data.stats.total_cost_usd.to_json(),
      "iterations": data.stats.total_iterations.to_json(),
      "messages": messages_arr.to_json(),
    }),
  }).stringify()
}

///|
/// Build session messages history response.
/// Returns events array in the same shape as WS events for isomorphism.
pub fn build_messages_history(
  session_id : String,
  messages : Array[@message.Message],
  limit? : Int = 100,
  before? : String? = None,
) -> Json {
  // Build event-shaped entries for each message (same as WS would emit).
  let events : Array[Json] = []
  let mut count = 0
  let mut i = messages.length() - 1
  // Iterate in reverse to apply before/limit efficiently.
  // Collect in reverse then flip.
  let collected : Array[Json] = []
  // Determine the before cutoff.
  let before_ts : String = match before {
    Some(t) => t
    None => ""
  }
  while i >= 0 {
    let msg = messages[i]
    // Simple before filter: compare message timestamp if available.
    // For now, we include all messages (before is optional pagination).
    if !before_ts.is_empty() {
      // Skip messages at or after the before timestamp (best-effort string compare).
      let msg_ts = message_timestamp(msg)
      if !msg_ts.is_empty() && msg_ts >= before_ts {
        i = i - 1
        continue
      }
    }
    let role = message_role_str(msg)
    let content = message_content(msg)
    collected.push(
      Json::object({
        "type": (if role == "user" {
          "history_user_message"
        } else {
          "assistant_message"
        }).to_json(),
        "session_id": session_id.to_json(),
        "data": Json::object({
          "role": role.to_json(),
          "content": content.to_json(),
        }),
      }),
    )
    count = count + 1
    if count >= limit {
      break
    }
    i = i - 1
  }
  // Reverse collected to get chronological order.
  let mut j = collected.length() - 1
  while j >= 0 {
    events.push(collected[j])
    j = j - 1
  }
  let has_more = messages.length() > events.length()
  Json::object({ "events": events.to_json(), "has_more": has_more.to_json() })
}

///|
/// Extract a string role from a Message.
fn message_role_str(msg : @message.Message) -> String {
  match msg.role {
    @message.User => "user"
    @message.Assistant => "assistant"
    @message.System => "system"
    @message.Tool => "tool"
  }
}

///|
/// Extract text content from a Message.
fn message_content(msg : @message.Message) -> String {
  match msg.content {
    Text(t) => t
    Blocks(parts) => {
      let buf : Array[String] = []
      for p in parts {
        match p {
          @message.Text(tb) => buf.push(tb.text)
          _ => ()
        }
      }
      buf.join("\n")
    }
  }
}

///|
/// Best-effort timestamp extraction from a message (empty string if unavailable).
fn message_timestamp(_msg : @message.Message) -> String {
  // Messages don't carry per-message timestamps in the current schema.
  // Return empty to disable before-filtering by timestamp.
  ""
}
