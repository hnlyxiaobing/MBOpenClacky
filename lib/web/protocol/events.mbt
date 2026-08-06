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
    StatusChanged(_old, new) => {
      // I-028: The frontend ws-dispatcher only recognises "idle" / "running".
      // Agent-internal "completed" must be mapped to "idle" at the WS contract
      // boundary so the frontend triggers Tasks/Skills refresh & clearProgress.
      // TUI consumes AgentStatus directly (not via this mapping), so it is
      // unaffected.
      let status_str = match new {
        @agent.Completed => "idle"
        _ => new.to_string_value()
      }
      {
        event_type: "session_update",
        data: Json::object({ "status": status_str.to_json() }),
      }
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
    ToolStdout(lines) =>
      {
        event_type: "tool_stdout",
        data: Json::object({ "lines": lines.to_json() }),
      }
    InfoMessage(msg) =>
      { event_type: "info", data: Json::object({ "message": msg.to_json() }) }
    SuccessMessage(msg) =>
      {
        event_type: "success",
        data: Json::object({ "message": msg.to_json() }),
      }
    FeedbackRequested(question, context, options) => {
      let opt_json : Json = match options {
        Some(arr) => arr.to_json()
        None => Json::null()
      }
      let ctx_json : Json = match context {
        Some(c) => c.to_json()
        None => Json::null()
      }
      {
        event_type: "request_feedback",
        data: Json::object({
          "question": question.to_json(),
          "context": ctx_json,
          "options": opt_json,
        }),
      }
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
/// Build a token_delta event for real-time streaming (typing animation).
/// T13: Forwarded alongside chunk aggregation so the frontend can animate
/// token-by-token while the complete message is still sent on MessageAdded.
pub fn build_token_delta_event(session_id : String, chunk : String) -> String {
  build_event(
    event_token_delta,
    session_id,
    Json::object({ "content": chunk.to_json() }),
  )
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
///
/// Pagination: `offset` is a positional cursor over the filtered event
/// stream (newest end) — skip `offset` events, then collect `limit`.
/// `before` (timestamp string) is the legacy cursor, kept for compatibility.
pub fn build_messages_history(
  session_id : String,
  messages : Array[@message.Message],
  limit? : Int = 100,
  before? : String? = None,
  offset? : Int = 0,
) -> Json {
  // Build event-shaped entries for each message (same as WS would emit).
  let events : Array[Json] = []
  let mut count = 0
  let mut skipped = 0
  let mut i = messages.length() - 1
  // Iterate in reverse to apply before/limit efficiently.
  // Collect in reverse then flip.
  let collected : Array[Json] = []
  // Determine the before cutoff.
  let before_ts : String = match before {
    Some(t) => t
    None => ""
  }
  // True when iteration stopped because of the limit rather than exhaustion.
  let mut truncated = false
  let mut done = false
  // Events of the limit-hit message that did not fit the page (they belong
  // to the next, older page → has_more must be true).
  let mut pending_in_message = 0
  while i >= 0 && !done {
    let msg = messages[i]
    // Skip messages strictly newer than the before cursor (best-effort
    // string compare on epoch-ms). Messages without a timestamp (legacy
    // session files) are never filtered out. The boundary message itself
    // is kept; the frontend dedups the overlap by created_at.
    if !before_ts.is_empty() {
      let msg_ts = message_timestamp(msg)
      if !msg_ts.is_empty() && msg_ts > before_ts {
        i = i - 1
        continue
      }
    }
    let role = message_role_str(msg)
    // System prompts contain confidential brand instructions; never expose via history API.
    if role == "system" {
      i = i - 1
      continue
    }
    // Expand the message into wire events (history_user_message /
    // assistant_message / tool_call / tool_result) so the Web UI can
    // reconstruct tool activity when re-rendering history.
    let evs = history_message_events(msg, role, session_id, i)
    let mut k = 0
    while k < evs.length() && !done {
      // Positional cursor: skip the first `offset` events.
      if skipped < offset {
        skipped = skipped + 1
      } else {
        collected.push(evs[k])
        count = count + 1
        if count >= limit {
          truncated = true
          done = true
          pending_in_message = evs.length() - k - 1
        }
      }
      k = k + 1
    }
    i = i - 1
  }
  // has_more is true only when we stopped due to the limit AND at least one
  // older message would still pass the before/role filters. Filtered-out
  // system/tool messages must not count towards has_more.
  let mut has_more = false
  if truncated {
    if pending_in_message > 0 {
      has_more = true
    } else {
      // `i` already points one below the last processed message.
      let mut k = i
      while k >= 0 {
        let m = messages[k]
        let r = message_role_str(m)
        if r != "system" {
          if before_ts.is_empty() {
            has_more = true
            break
          }
          let ts = message_timestamp(m)
          if ts.is_empty() || ts <= before_ts {
            has_more = true
            break
          }
        }
        k = k - 1
      }
    }
  }
  // Reverse collected to get chronological order.
  let mut j = collected.length() - 1
  while j >= 0 {
    events.push(collected[j])
    j = j - 1
  }
  Json::object({ "events": events.to_json(), "has_more": has_more.to_json() })
}

///|
/// Expand one stored message into history wire events so the Web UI can
/// reconstruct tool activity (tool_call / tool_result rows) after a session
/// switch:
/// - user      → history_user_message (carries the system_injected flag)
/// - assistant → assistant_message for the text part (omitted when empty,
///               e.g. tool-call-only turns — no placeholder bubble) plus one
///               tool_call event per stored tool call
/// - tool      → tool_result event with the stored result text
/// Plain user/assistant events keep the plain created_at timestamp; tool
/// events get a deterministic per-event stamp (`ts#msgIdx.evIdx`) so events
/// sharing one millisecond never collide in the frontend dedup set while
/// page-overlap dedup still works.
fn history_message_events(
  msg : @message.Message,
  role : String,
  session_id : String,
  msg_index : Int,
) -> Array[Json] {
  let ts = message_timestamp(msg)
  let out : Array[Json] = []
  let mut ev_idx = 0
  match role {
    "user" => {
      let obj : Map[String, Json] = {
        "type": "history_user_message".to_json(),
        "session_id": session_id.to_json(),
        "role": role.to_json(),
        "content": message_content(msg).to_json(),
      }
      // Expose injected (non-user-authored) messages so the frontend can skip
      // them in its created_at-based dedup: injected context shares no real
      // user intent and must never be treated as the round's user message.
      match msg.system_injected {
        Some(true) => obj["system_injected"] = true.to_json()
        _ => ()
      }
      if !ts.is_empty() {
        obj["created_at"] = ts.to_json()
      }
      out.push(Json::object(obj))
    }
    "assistant" => {
      let content = message_content(msg)
      if !content.is_empty() {
        let obj : Map[String, Json] = {
          "type": "assistant_message".to_json(),
          "session_id": session_id.to_json(),
          "role": role.to_json(),
          "content": content.to_json(),
        }
        if !ts.is_empty() {
          obj["created_at"] = ts.to_json()
        }
        out.push(Json::object(obj))
      }
      match msg.tool_calls {
        Some(calls) =>
          for call in calls {
            let args_json : Json = @json.parse(call.function.arguments) catch {
              _ => call.function.arguments.to_json()
            }
            let obj : Map[String, Json] = {
              "type": "tool_call".to_json(),
              "session_id": session_id.to_json(),
              "name": call.function.name.to_json(),
              "args": args_json,
              "summary": Json::null(),
            }
            if !ts.is_empty() {
              obj["created_at"] = (ts +
              "#" +
              msg_index.to_string() +
              "." +
              ev_idx.to_string()).to_json()
              ev_idx = ev_idx + 1
            }
            out.push(Json::object(obj))
          }
        None => ()
      }
    }
    _ => {
      // role == "tool": surface the stored result so history shows each
      // tool call's outcome.
      let obj : Map[String, Json] = {
        "type": "tool_result".to_json(),
        "session_id": session_id.to_json(),
        "result": message_content(msg).to_json(),
      }
      if !ts.is_empty() {
        obj["created_at"] = (ts +
        "#" +
        msg_index.to_string() +
        "." +
        ev_idx.to_string()).to_json()
      }
      out.push(Json::object(obj))
    }
  }
  out
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
fn message_timestamp(msg : @message.Message) -> String {
  msg.created_at.unwrap_or("")
}
