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
        event_type: "session_update",
        data: Json::object({ "status": new.to_string_value().to_json() }),
      }
    BeforeIteration(n) =>
      {
        event_type: "progress",
        data: Json::object({
          "phase": "active".to_json(),
          "message": "Thinking...".to_json(),
          "progress_type": "thinking".to_json(),
          "metadata": Json::object({ "iteration": n.to_json() }),
          "started_at": @agent.current_time_ms().to_string().to_json(),
        }),
      }
    AfterIteration(_n) =>
      {
        event_type: "progress",
        data: Json::object({ "phase": "done".to_json() }),
      }
    BeforeLlmCall =>
      {
        event_type: "phase_start",
        data: Json::object({
          "phase_id": "llm_call".to_json(),
          "kind": "llm_call".to_json(),
          "label": "LLM call".to_json(),
        }),
      }
    AfterLlmCall =>
      {
        event_type: "phase_end",
        data: Json::object({ "phase_id": "llm_call".to_json() }),
      }
    MessageAdded =>
      {
        event_type: "progress",
        data: Json::object({ "phase": "done".to_json() }),
      }
    ToolExecuting(name, args) =>
      {
        event_type: "tool_call",
        data: Json::object({
          "name": name.to_json(),
          "args": args.to_json(),
          "summary": Json::null(),
        }),
      }
    ToolExecuted(_name, result) => {
      let is_err = result.is_error
      let output = result.content
      if is_err {
        {
          event_type: "tool_error",
          data: Json::object({ "error": output.to_json() }),
        }
      } else {
        {
          event_type: "tool_result",
          data: Json::object({ "result": output.to_json() }),
        }
      }
    }
    ErrorOccurred(msg) =>
      { event_type: "error", data: Json::object({ "message": msg.to_json() }) }
    RunCompleted(result) => {
      let cs = result.cache_stats
      {
        event_type: "complete",
        data: Json::object({
          "iterations": result.iterations.to_json(),
          "cost": result.total_cost_usd.to_json(),
          "cost_source": result.cost_source.to_string_value().to_json(),
          "cache_stats": Json::object({
            "total_requests": cs.total_requests.to_json(),
            "cache_hit_requests": cs.cache_hit_requests.to_json(),
            "cache_read_input_tokens": cs.cache_read_input_tokens.to_json(),
          }),
        }),
      }
    }
    StreamChunk(chunk) =>
      {
        event_type: "assistant_message",
        data: Json::object({
          "content": chunk.to_json(),
          "partial": true.to_json(),
        }),
      }
    SessionStarted(session_id) =>
      {
        event_type: "session_update",
        data: Json::object({
          "session_id": session_id.to_json(),
          "status": "running".to_json(),
        }),
      }
    SessionEnded(session_id) =>
      {
        event_type: "session_update",
        data: Json::object({
          "session_id": session_id.to_json(),
          "status": "idle".to_json(),
        }),
      }
    CostUpdated(cost) =>
      {
        event_type: "token_usage",
        data: Json::object({ "cost": cost.to_json() }),
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
        data: Json::object({
          "phase_id": "thinking".to_json(),
          "kind": "thinking".to_json(),
          "label": "Thinking".to_json(),
        }),
      }
    ThinkingEnded =>
      {
        event_type: "phase_end",
        data: Json::object({ "phase_id": "thinking".to_json() }),
      }
    SubagentStarted(name) =>
      {
        event_type: "phase_start",
        data: Json::object({
          "phase_id": name.to_json(),
          "kind": "skill_evolution".to_json(),
          "label": name.to_json(),
        }),
      }
    SubagentEnded(name) =>
      {
        event_type: "phase_end",
        data: Json::object({
          "phase_id": name.to_json(),
          "summary": Json::null(),
        }),
      }
    RetryAttempt(n, reason) =>
      {
        event_type: "progress",
        data: Json::object({
          "phase": "active".to_json(),
          "message": "Retrying...".to_json(),
          "progress_type": "retry".to_json(),
          "metadata": Json::object({
            "attempt": n.to_json(),
            "reason": reason.to_json(),
          }),
          "started_at": @agent.current_time_ms().to_string().to_json(),
        }),
      }
    ToolDenied(name) =>
      {
        event_type: "tool_error",
        data: Json::object({ "error": ("Tool denied: " + name).to_json() }),
      }
    UsageUpdated(data) =>
      {
        event_type: "token_usage",
        data: Json::object({
          "prompt_tokens": data.prompt_tokens.to_json(),
          "completion_tokens": data.completion_tokens.to_json(),
          "delta_tokens": data.delta_tokens.to_json(),
          "total_tokens": data.total_tokens.to_json(),
          "cost": data.cost.to_json(),
          "cost_source": data.cost_source.to_string_value().to_json(),
          "cache_read": data.cache_read.to_json(),
          "cache_write": data.cache_write.to_json(),
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
  build_event(mapped.event_type, session_id, mapped.data)
}

///|
/// Build a session_update snapshot event from a SessionData.
/// Sent on initial subscribe; uses the `session` object shape the frontend
/// session_update handler expects (ws-dispatcher.js shape 1).
pub fn build_session_snapshot(data : @agent.SessionData) -> String {
  let messages_arr : Array[Json] = []
  for msg in data.messages {
    messages_arr.push(msg.to_json())
  }
  let model_field : Json = match data.model_name {
    Some(m) => m.to_json()
    None => Json::null()
  }
  build_event(
    "session_update",
    data.session_id,
    Json::object({
      "session": Json::object({
        "id": data.session_id.to_json(),
        "name": data.name.to_json(),
        "status": data.last_status.to_json(),
        "working_dir": data.working_dir.to_json(),
        "model": model_field,
        "created_at": data.created_at.to_json(),
        "total_tasks": data.stats.total_tasks.to_json(),
        "total_cost": data.stats.total_cost_usd.to_json(),
        "cost_source": data.stats.cost_source.to_json(),
        "source": data.source.to_json(),
        "latest_latency": data.latest_latency_ms.to_json(),
        "messages": messages_arr.to_json(),
      }),
    }),
  )
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
        "role": role.to_json(),
        "content": content.to_json(),
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
