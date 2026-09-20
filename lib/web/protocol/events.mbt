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
  let protocol_event = @agent.hook_event_to_protocol(event)
  { event_type: protocol_event.type_name(), data: payload_of(protocol_event), }
}

///|
/// The event body without its `type` discriminator 鈥?the historical
/// `MappedWsEvent.data` shape, kept for the REST history path and the
/// existing white-box tests.
fn payload_of(event : @proto.Event) -> Json {
  match event.to_json() {
    Object(fields) => {
      let out : Map[String, Json] = Map([])
      for entry in fields {
        if entry.0 != "type" {
          out[entry.0] = entry.1
        }
      }
      Json::object(out)
    }
    other => other
  }
}

///|
/// Adapt an agent status string for the frontend contract (I-028): the
/// ws-dispatcher only recognises "idle" / "running", so the agent-internal
/// "completed" is mapped to "idle" at this boundary. TUI and CLI consume the
/// raw status.
fn adapt_status(status : String?) -> String? {
  match status {
    Some("completed") => Some("idle")
    other => other
  }
}

///|
/// Frame a protocol event for the web frontend: session-scoped events carry
/// the session id, global frames do not. This exhaustive match is the web
/// end's contract surface 鈥?adding an `Event` variant fails compilation here
/// until the web layer accounts for it.
pub fn ws_frame(session_id : String, event : @proto.Event) -> String {
  let frame : String? = if event.is_global() { None } else { Some(session_id) }
  match event {
    @proto.SessionUpdate(u) =>
      @proto.SessionUpdate({ ..u, status: adapt_status(u.status), }).to_wire(
        frame,
      )
    @proto.Progress(_)
    | @proto.PhaseStart(_)
    | @proto.PhaseEnd(_)
    | @proto.ToolCall(_)
    | @proto.ToolResult(_)
    | @proto.ToolError(_)
    | @proto.ErrorMessage(_)
    | @proto.Complete(_)
    | @proto.AssistantMessage(_)
    | @proto.TokenUsage(_)
    | @proto.TokenDelta(_)
    | @proto.Warning(_)
    | @proto.Info(_)
    | @proto.Success(_)
    | @proto.FilePreview(_)
    | @proto.ToolStdout(_)
    | @proto.RequestFeedback(_)
    | @proto.RequestConfirmation(_)
    | @proto.Interrupted
    | @proto.SessionRestored(_)
    | @proto.SessionRenamed(_)
    | @proto.SessionDeleted
    | @proto.HistoryUserMessage(_)
    | @proto.TaskFinished(_)
    | @proto.FeedbackResponse(_)
    | @proto.ConfirmationResponse(_)
    | @proto.Connected(_)
    | @proto.Subscribed(_)
    | @proto.SessionList(_)
    | @proto.Pong => event.to_wire(frame)
  }
}

///|
/// Build the full JSON wire string for a mapped hook event, scoped to a session.
pub fn format_hook_event(
  session_id : String,
  event : @agent.HookEvent,
) -> String {
  ws_frame(session_id, @agent.hook_event_to_protocol(event))
}

///|
/// A `session_update` status patch frame.
pub fn session_status_frame(session_id : String, status : String) -> String {
  ws_frame(
    session_id,
    @proto.SessionUpdate({
      status: Some(status),
      session_id: None,
      cost: None,
      cost_source: None,
      latency: None,
      session: None,
    }),
  )
}

///|
/// A `session_update` cost patch frame (fix-08 partial update).
pub fn session_cost_frame(
  session_id : String,
  cost : Double,
  cost_source : String,
) -> String {
  ws_frame(
    session_id,
    @proto.SessionUpdate({
      status: None,
      session_id: None,
      cost: Some(cost),
      cost_source: Some(cost_source),
      latency: None,
      session: None,
    }),
  )
}

///|
/// A `session_update` latency patch frame (fix-08 partial update).
pub fn session_latency_frame(session_id : String, latency : Json) -> String {
  ws_frame(
    session_id,
    @proto.SessionUpdate({
      status: None,
      session_id: None,
      cost: None,
      cost_source: None,
      latency: Some(latency),
      session: None,
    }),
  )
}

///|
/// A `progress` done frame (closes the frontend progress indicator).
pub fn progress_done_frame(session_id : String) -> String {
  ws_frame(
    session_id,
    @proto.Progress({
      phase: "done",
      message: None,
      progress_type: None,
      metadata: None,
      started_at: None,
    }),
  )
}

///|
/// A complete (non-partial) assistant message frame.
pub fn assistant_message_frame(
  session_id : String,
  role : String,
  content : String,
) -> String {
  ws_frame(
    session_id,
    @proto.AssistantMessage({
      content,
      role: Some(role),
      partial: None,
      created_at: None,
    }),
  )
}

///|
/// A tool confirmation request frame.
pub fn request_confirmation_frame(
  session_id : String,
  request_id : String,
  message : String,
) -> String {
  ws_frame(session_id, @proto.RequestConfirmation({ id: request_id, message, }))
}

///|
/// A feedback request frame.
pub fn request_feedback_frame(
  session_id : String,
  request_id : String,
  question : String,
  context : String?,
  options : Array[String]?,
) -> String {
  ws_frame(
    session_id,
    @proto.RequestFeedback({ question, id: Some(request_id), context, options, }),
  )
}

///|
/// Build a token_delta event for real-time streaming (typing animation).
/// T13: Forwarded alongside chunk aggregation so the frontend can animate
/// token-by-token while the complete message is still sent on MessageAdded.
pub fn build_token_delta_event(session_id : String, chunk : String) -> String {
  @proto.TokenDelta({ content: chunk, }).to_wire(Some(session_id))
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
  let patch = @proto.SessionUpdate({
    status: None,
    session_id: None,
    cost: None,
    cost_source: None,
    latency: None,
    session: Some(
      Json::object({
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
    ),
  })
  patch.to_wire(Some(data.session_id))
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
      // Expose injected (non-user-authored) messages so the frontend can skip
      // them in its created_at-based dedup: injected context shares no real
      // user intent and must never be treated as the round's user message.
      let event = @proto.HistoryUserMessage({
        content: message_content(msg),
        role,
        created_at: if ts.is_empty() {
          None
        } else {
          Some(ts)
        },
        system_injected: match msg.system_injected {
          Some(true) => Some(true)
          _ => None
        },
      })
      out.push(event.to_framed_json(Some(session_id)))
    }
    "assistant" => {
      let content = message_content(msg)
      if !content.is_empty() {
        let event = @proto.AssistantMessage({
          content,
          role: Some(role),
          partial: None,
          created_at: if ts.is_empty() {
            None
          } else {
            Some(ts)
          },
        })
        out.push(event.to_framed_json(Some(session_id)))
      }
      match msg.tool_calls {
        Some(calls) =>
          for call in calls {
            let args_json : Json = @json.parse(call.function.arguments) catch {
              _ => call.function.arguments.to_json()
            }
            let stamp = if ts.is_empty() {
              None
            } else {
              Some(ts + "#" + msg_index.to_string() + "." + ev_idx.to_string())
            }
            if !ts.is_empty() {
              ev_idx = ev_idx + 1
            }
            let event = @proto.ToolCall({
              name: call.function.name,
              args: args_json,
              summary: None,
              created_at: stamp,
            })
            out.push(event.to_framed_json(Some(session_id)))
          }
        None => ()
      }
    }
    _ => {
      // role == "tool": surface the stored result so history shows each
      // tool call's outcome.
      let stamp = if ts.is_empty() {
        None
      } else {
        Some(ts + "#" + msg_index.to_string() + "." + ev_idx.to_string())
      }
      let event = @proto.ToolResult({
        result: message_content(msg),
        created_at: stamp,
      })
      out.push(event.to_framed_json(Some(session_id)))
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
