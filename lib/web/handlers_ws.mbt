///| WebSocket handler for the /ws single-endpoint protocol.

///|

///| Supports 8 upstream message types:

///|   subscribe, message, edit_message, interrupt, confirmation,

///|   run_task, ping, list_sessions

///|

///| Agent runs are spawned as background async tasks (via run_async) so the

///| WS read loop never blocks: interrupt and confirmation messages can be

///| processed while a run is in progress.

///|
/// Per-session WS runtime state.
priv struct WsSessionState {
  /// Whether an agent run is currently in progress for this session.
  mut running : Bool
  /// Handle of the spawned run task, used to deliver cancellation on
  /// interrupt. None when running synchronously (test fallback).
  mut running_task : @async.Task[Unit]?
  /// Aggregates StreamChunk deltas into one complete assistant_message
  /// (T13: token-level streaming now forwarded via token_delta events).
  mut chunk_buf : String
  /// Sequence counter for confirmation request ids.
  mut confirm_seq : Int
  /// Pending confirmation replies, keyed by request_id. The WS
  /// `confirmation` upstream message resolves the queue; the confirmation
  /// bridge task awaits it with a timeout.
  pending_confirmations : Map[String, @async.Queue[Bool]]
  /// Pending feedback replies, keyed by request_id. The WS `feedback`
  /// upstream message resolves the queue; the feedback bridge task awaits
  /// it with a timeout.
  pending_feedback : Map[String, @async.Queue[String]]
  /// Time Machine state for file-change snapshots (undo/restore).
  time_machine : @agent.TimeMachineState
}

///|
/// WS runtime state for all sessions.
let ws_states : Map[String, WsSessionState] = Map([])

///|
/// Task group used to spawn background agent runs. Installed once by
/// WebServer::start via set_ws_task_group. When absent (e.g. unit tests
/// dispatching without a running server), runs fall back to a blocking
/// synchronous execution.
let ws_task_group : Ref[@async.TaskGroup[Unit]?] = Ref(None)

///|
/// Install the server's long-lived task group for background WS runs.
/// Called once from WebServer::start before serving.
pub fn set_ws_task_group(group : @async.TaskGroup[Unit]) -> Unit {
  ws_task_group.val = Some(group)
}

///|
/// Get or create the WS runtime state for a session.
fn get_ws_state(session_id : String) -> WsSessionState {
  match ws_states.get(session_id) {
    Some(s) => s
    None => {
      let s = WsSessionState::{
        running: false,
        running_task: None,
        chunk_buf: "",
        confirm_seq: 0,
        pending_confirmations: Map([]),
        pending_feedback: Map([]),
        time_machine: @agent.TimeMachineState::new(session_id),
      }
      ws_states[session_id] = s
      s
    }
  }
}

///|
/// Handle WebSocket events for /ws (single-endpoint protocol).
/// Unlike the legacy /ws/sessions/:id, this handler does NOT auto-subscribe
/// on connect. The client must send a `subscribe` message to bind to a session.
async fn handle_ws_global(
  server_ref : Ref[WebServer],
  event : @ws.WebSocketEvent,
) -> Unit {
  match event {
    Open(peer) => {
      let hub = server_ref.val.hub
      hub.register(peer)
      // orig does not push a "connected" event on Open; the client must
      // send subscribe/message to initiate interaction.
    }
    Message(peer, msg) =>
      match msg {
        Text(text) => {
          let json = @json.parse(text) catch {
            _ => {
              peer.text(@protocol.build_error_event("", "invalid JSON frame"))
              return
            }
          }
          let obj = match json {
            Object(o) => o
            _ => {
              peer.text(@protocol.build_error_event("", "expected JSON object"))
              return
            }
          }
          // A missing type must never default to "message": malformed frames
          // must not trigger a billed LLM run.
          let msg_type_str = match obj.get("type") {
            Some(String(t)) => t
            _ => {
              peer.text(@protocol.build_error_event("", "missing message type"))
              return
            }
          }
          let conn_id = peer.connection_id()
          let hub = server_ref.val.hub
          match @protocol.parse_upstream_type(msg_type_str) {
            Some(@protocol.Ping) => handle_ws_ping(peer)
            Some(@protocol.Subscribe) =>
              handle_ws_subscribe(server_ref, peer, conn_id, hub, obj)
            Some(@protocol.ListSessions) =>
              handle_ws_list_sessions(server_ref, peer)
            Some(@protocol.Interrupt) =>
              handle_ws_interrupt(server_ref, peer, conn_id, hub, obj)
            Some(@protocol.Message) =>
              handle_ws_message(server_ref, peer, conn_id, hub, obj)
            Some(@protocol.EditMessage) =>
              handle_ws_edit_message(server_ref, peer, conn_id, hub, obj)
            Some(@protocol.Confirmation) =>
              handle_ws_confirmation(server_ref, peer, obj)
            Some(@protocol.Feedback) =>
              handle_ws_feedback(server_ref, peer, obj)
            Some(@protocol.RunTask) =>
              handle_ws_run_task(server_ref, peer, conn_id, hub, obj)
            None =>
              peer.text(
                @protocol.build_error_event(
                  "",
                  "unknown message type: " + msg_type_str,
                ),
              )
          }
        }
        Binary(_) => ()
      }
    Close(peer) => {
      let hub = server_ref.val.hub
      hub.unregister(peer.connection_id())
    }
  }
}

///|
/// Handle ping → pong.
fn handle_ws_ping(peer : @ws.WebSocketPeer) -> Unit {
  peer.text(@protocol.build_pong())
}

///|
/// Handle subscribe message.
/// Format: {"type": "subscribe", "session_id": "..."}
/// Switches the connection's session subscription and sends:
///   1. subscribed confirmation
///   2. session_update snapshot (if session exists)
///   3. session_list (full current list)
fn handle_ws_subscribe(
  server_ref : Ref[WebServer],
  peer : @ws.WebSocketPeer,
  conn_id : String,
  hub : @broadcast.Hub,
  obj : Map[String, Json],
) -> Unit {
  let target = match obj.get("session_id") {
    Some(String(sid)) if !sid.is_empty() => sid
    _ => {
      // Subscribe to global broadcast.
      hub.subscribe_global(conn_id)
      peer.text(@protocol.build_subscribed_event("global"))
      return
    }
  }

  // I-013: Verify session exists before switching subscription.
  // If neither persisted nor in-memory, reply with an error and keep the
  // current subscription unchanged (prevents "ghost session" UX).
  let session_opt = @agent.load_session(target)
  let exists = match session_opt {
    Some(_) => true
    None => server_ref.val.active_agents.contains(target)
  }
  if !exists {
    peer.text(@protocol.build_error_event(target, "Session not found"))
    return
  }

  // Switch to the new session (unsubscribe old, subscribe new).
  hub.switch_session(conn_id, target)
  peer.text(@protocol.build_subscribed_event(target))

  // Send session snapshot.
  match session_opt {
    Some(data) => peer.text(@protocol.build_session_snapshot(data))
    None =>
      // In-memory active agent (guaranteed to exist by the check above).
      match server_ref.val.active_agents.get(target) {
        Some(agent) =>
          peer.text(@protocol.build_session_snapshot(agent.to_session_data()))
        None => ()
      }
  }

  // Send current session list.
  send_session_list(server_ref, peer)
}

///|
/// Handle list_sessions message.
/// Returns the full list of sessions as session_list event.
fn handle_ws_list_sessions(
  server_ref : Ref[WebServer],
  peer : @ws.WebSocketPeer,
) -> Unit {
  send_session_list(server_ref, peer)
}

///|
/// Build and send the session list event to a peer.
/// Reuses SessionSummary so the WS payload is isomorphic to the REST
/// GET /api/sessions response.
///
/// IMPORTANT: merges in-memory active_agents that have no on-disk file.
/// This prevents sessions whose `save_session` failed silently from
/// vanishing on browser refresh (the frontend's `_sessions` is cleared
/// on full-page reload and repopulated solely from this event).
fn send_session_list(
  server_ref : Ref[WebServer],
  peer : @ws.WebSocketPeer,
) -> Unit {
  let disk_sessions = @agent.list_sessions()
  let pinned_map = load_pinned_map()
  let model_options : Array[String] = server_ref.val.config.models.map(m => {
    m.model
  })
  let default_model : String? = match server_ref.val.config.current_model() {
    Some(mc) => Some(mc.model)
    None => None
  }
  // Collect on-disk session IDs so we can detect memory-only sessions.
  let disk_ids : Map[String, Bool] = Map([])
  let all_sessions : Array[@agent.SessionData] = []
  for sd in disk_sessions {
    disk_ids[sd.session_id] = true
    all_sessions.push(sd)
  }
  // Merge active_agents that are NOT on disk (save_session may have failed).
  for sid, agent in server_ref.val.active_agents {
    if disk_ids.get(sid) is None {
      all_sessions.push(agent.to_session_data())
    }
  }
  let summaries : Array[Json] = []
  for sd in all_sessions {
    summaries.push(
      SessionSummary::{
        id: sd.session_id,
        name: sd.name,
        working_dir: sd.working_dir,
        status: sd.last_status,
        created_at: sd.created_at,
        updated_at: sd.created_at, // TODO(P1): track real updated_at
        total_tasks: sd.stats.total_tasks,
        total_cost: sd.stats.total_cost_usd,
        cost_source: sd.stats.cost_source,
        error: sd.last_error,
        model: match sd.model_name {
          Some(m) => Some(m)
          None => default_model
        },
        source: sd.source,
        latest_latency: SessionLatency::from_session_data(sd),
        pinned: pinned_map.get(sd.session_id).unwrap_or(false),
        agent_profile: sd.agent_profile,
        sub_model: sd.sub_model,
        sub_model_options: model_options,
        reasoning_effort: sd.reasoning_effort,
        model_id: sd.model_config_id,
        card_model: sd.model_name,
        channel_info: sd.channel_info,
        error_code: sd.error_code,
        top_up_url: sd.top_up_url,
        raw_message: sd.raw_message,
      }.to_json(),
    )
  }
  peer.text(@protocol.build_session_list_event(summaries))
}

///|
/// Resolve the target session_id from a message's session_id field,
/// falling back to the connection's current subscription.
fn resolve_session_id(
  hub : @broadcast.Hub,
  conn_id : String,
  obj : Map[String, Json],
) -> String? {
  match obj.get("session_id") {
    Some(String(s)) if !s.is_empty() => Some(s)
    _ => {
      let subs = hub.get_connection_sessions(conn_id)
      if subs.length() > 0 {
        Some(subs[0])
      } else {
        None
      }
    }
  }
}

///|
/// Ensure the connection is subscribed to the given session.
fn ensure_subscribed(
  hub : @broadcast.Hub,
  conn_id : String,
  session_id : String,
) -> Unit {
  let current_subs = hub.get_connection_sessions(conn_id)
  for sid in current_subs {
    if sid == session_id {
      return
    }
  }
  hub.switch_session(conn_id, session_id)
}

///|
/// Handle interrupt message.
/// Format: {"type": "interrupt", "session_id": "..."}
/// Sets the cancellation flag (checked by the run worker and hooks) and
/// cancels the spawned run task, which aborts the run at the next async
/// suspension point (e.g. while awaiting the LLM response). The interrupted
/// event is broadcast immediately.
fn handle_ws_interrupt(
  server_ref : Ref[WebServer],
  _peer : @ws.WebSocketPeer,
  conn_id : String,
  hub : @broadcast.Hub,
  obj : Map[String, Json],
) -> Unit {
  let sid = match resolve_session_id(hub, conn_id, obj) {
    Some(s) => s
    None => return
  }
  match ws_states.get(sid) {
    Some(state) =>
      if state.running {
        server_ref.val.cancelled[sid] = true
        match state.running_task {
          Some(t) => t.cancel()
          None => ()
        }
        hub.broadcast_session(sid, @protocol.build_interrupted_event(sid))
        // I-027: After interrupt, send the same closing frames as a normal
        // run end so the frontend status bar transitions to idle and the
        // progress indicator clears.
        hub.broadcast_session(
          sid,
          @protocol.build_event(
            @protocol.event_session_update,
            sid,
            Json::object({ "status": "idle".to_json() }),
          ),
        )
        hub.broadcast_session(
          sid,
          @protocol.build_event(
            @protocol.event_progress,
            sid,
            Json::object({ "phase": "done".to_json() }),
          ),
        )
      }
    None => ()
  }
}

///|
/// Handle message (chat) message.
/// Format: {"type": "message", "session_id": "...", "content": "...",
///           "attachments": [...], "images": [...]}
/// `attachments` are folded into the user message text as file
/// references (agent can read them via file tools). `images` carrying
/// inline base64 data are injected as real `ContentBlock::Image`
/// blocks via `Agent::inject_user_image`, mirroring the observe()
/// tool-result image_inject path in react.mbt. Images with only a
/// `path` (no base64) are treated as file references in the text.
async fn handle_ws_message(
  server_ref : Ref[WebServer],
  _peer : @ws.WebSocketPeer,
  conn_id : String,
  hub : @broadcast.Hub,
  obj : Map[String, Json],
) -> Unit {
  let message = match obj.get("content") {
    Some(String(m)) => m
    _ => return
  }
  let session_id = match resolve_session_id(hub, conn_id, obj) {
    Some(s) => s
    None => return
  }
  ensure_subscribed(hub, conn_id, session_id)
  // Parse images: those with inline base64 go through the real
  // injection path; those with only a path become text references.
  let injectable_images = extract_injectable_images(obj)
  let path_only_hints = extract_path_only_image_hints(obj)
  let attachment_hints = extract_attachment_hint(obj)
  let mut text_suffix = ""
  if path_only_hints.length() > 0 {
    text_suffix = text_suffix + "\n\n[images]\n" + path_only_hints
  }
  if attachment_hints.length() > 0 {
    text_suffix = text_suffix + "\n\n[attachments]\n" + attachment_hints
  }
  let final_message = if text_suffix.length() > 0 {
    message + text_suffix
  } else {
    message
  }
  start_ws_run(server_ref, session_id, final_message, images=injectable_images)
}

///|
/// Extract images that carry inline base64 data, ready for
/// `Agent::inject_user_image`. Each element is (base64_data,
/// mime_type, path?).
fn extract_injectable_images(
  obj : Map[String, Json],
) -> Array[(String, String, String?)] {
  let result : Array[(String, String, String?)] = []
  match obj.get("images") {
    Some(Array(arr)) =>
      for item in arr {
        match item {
          Object(o) =>
            match
              (
                o.get("data"),
                o.get("base64_data"),
                o.get("mime_type"),
                o.get("path"),
              ) {
              (Some(String(d)), _, Some(String(mt)), p) =>
                result.push(
                  (
                    d,
                    mt,
                    match p {
                      Some(String(pp)) => Some(pp)
                      _ => None
                    },
                  ),
                )
              (_, Some(String(d)), Some(String(mt)), p) =>
                result.push(
                  (
                    d,
                    mt,
                    match p {
                      Some(String(pp)) => Some(pp)
                      _ => None
                    },
                  ),
                )
              _ => ()
            }
          _ => ()
        }
      }
    _ => ()
  }
  result
}

///|
/// Extract image path-only hints (images without inline base64 data)
/// as text references for the user message.
fn extract_path_only_image_hints(obj : Map[String, Json]) -> String {
  let parts : Array[String] = []
  match obj.get("images") {
    Some(Array(arr)) =>
      for item in arr {
        match item {
          Object(o) =>
            // Only include images that have a path but NO base64 data.
            match (o.get("path"), o.get("data"), o.get("base64_data")) {
              (Some(String(p)), None, None) => parts.push("image:" + p)
              _ => ()
            }
          String(s) => parts.push("image:" + s)
          _ => ()
        }
      }
    _ => ()
  }
  parts.join("\n")
}

///|
/// Extract a compact description of any `attachments` / `images`
/// fields present on a WS message object. Returns an empty string
/// when neither field is present. The description is appended to the
/// user message so the agent can act on referenced files. This is the
/// parsing half of the WS attachment pipeline (spec 2026-08-18_17
/// decision 3); the injection half waits on B2.
fn extract_attachment_hint(obj : Map[String, Json]) -> String {
  let parts : Array[String] = []
  match obj.get("attachments") {
    Some(Array(arr)) =>
      for item in arr {
        match item {
          Object(o) =>
            match (o.get("path"), o.get("name")) {
              (Some(String(p)), _) => parts.push("file:" + p)
              (_, Some(String(n))) => parts.push("file:" + n)
              _ => ()
            }
          String(s) => parts.push("file:" + s)
          _ => ()
        }
      }
    _ => ()
  }
  match obj.get("images") {
    Some(Array(arr)) =>
      for item in arr {
        match item {
          Object(o) =>
            match o.get("path") {
              Some(String(p)) => parts.push("image:" + p)
              _ => ()
            }
          String(s) => parts.push("image:" + s)
          _ => ()
        }
      }
    _ => ()
  }
  parts.join("\n")
}

///|
/// Handle edit_message message.
/// Format: {"type": "edit_message", "session_id": "...", "content": "..."}
/// Optional `message_id` (matched against message.created_at) locates
/// the edit point; when absent the handler keeps the legacy "last user
/// message" behaviour. Dropping everything after the edit point and
/// re-running mirrors the Ruby edit_message semantics (see spec
/// 2026-08-18_17 decision 4).
async fn handle_ws_edit_message(
  server_ref : Ref[WebServer],
  _peer : @ws.WebSocketPeer,
  conn_id : String,
  hub : @broadcast.Hub,
  obj : Map[String, Json],
) -> Unit {
  let message = match obj.get("content") {
    Some(String(m)) => m
    _ => return
  }
  let session_id = match resolve_session_id(hub, conn_id, obj) {
    Some(s) => s
    None => return
  }
  ensure_subscribed(hub, conn_id, session_id)
  let agent = server_ref.val.get_or_create_agent(session_id)
  // Resolve the edit point. If the client supplied `message_id` we
  // match it against message.created_at; otherwise we fall back to the
  // last user message (legacy behaviour).
  let target_id = match obj.get("message_id") {
    Some(String(s)) if !s.is_empty() => Some(s)
    _ => None
  }
  let mut target_idx = -1
  match target_id {
    Some(id) => {
      let mut i = 0
      for m in agent.history.all() {
        match m.created_at {
          Some(ts) if ts == id => {
            target_idx = i
            break
          }
          _ => ()
        }
        i = i + 1
      }
      if target_idx < 0 {
        hub.broadcast_session(
          session_id,
          @protocol.build_error_event(session_id, "message_id not found: " + id),
        )
        return
      }
    }
    None => {
      // Legacy: locate the last user message in the agent history.
      for i, m in agent.history.all() {
        if m.role is @message.User {
          target_idx = i
        }
      }
      if target_idx < 0 {
        hub.broadcast_session(
          session_id,
          @protocol.build_error_event(session_id, "no user message to edit"),
        )
        return
      }
    }
  }
  // Drop the target message and everything after it; the run re-pushes
  // the edited message as the new last user message.
  while agent.history.size() > target_idx {
    ignore(agent.history.pop_last())
  }
  start_ws_run(server_ref, session_id, message)
}

///|
/// Handle confirmation message.
/// Format: {"type": "confirmation", "session_id": "...", "id": "...", "result": true/false}
/// Delivers the reply to the pending confirmation queue that the
/// confirmation bridge is awaiting, then acknowledges the client.
fn handle_ws_confirmation(
  _server_ref : Ref[WebServer],
  peer : @ws.WebSocketPeer,
  obj : Map[String, Json],
) -> Unit {
  let request_id = match obj.get("id") {
    Some(String(rid)) => rid
    _ => {
      peer.text(@protocol.build_error_event("", "missing id"))
      return
    }
  }
  let confirmed = match obj.get("result") {
    Some(String("yes")) => true
    Some(True) => true
    _ => false
  }
  // Deliver the reply to the pending confirmation, if any. Prefer the
  // session hinted by the client; otherwise scan all sessions.
  let mut delivered = false
  match obj.get("session_id") {
    Some(String(sid)) if !sid.is_empty() =>
      match ws_states.get(sid) {
        Some(state) =>
          delivered = deliver_confirmation(state, request_id, confirmed)
        None => ()
      }
    _ =>
      for _, state in ws_states {
        if deliver_confirmation(state, request_id, confirmed) {
          delivered = true
          break
        }
      }
  }
  // Acknowledge the client (delivered=false means the request was unknown
  // or already resolved, e.g. after a timeout).
  peer.text(@protocol.build_confirmation_response(request_id, delivered))
}

///|
/// Deliver a confirmation reply to a session's pending confirmation queue.
/// Returns true if a matching pending request was found and resolved.
fn deliver_confirmation(
  state : WsSessionState,
  request_id : String,
  confirmed : Bool,
) -> Bool {
  match state.pending_confirmations.get(request_id) {
    Some(q) => q.try_put(confirmed) catch { _ => false }
    None => false
  }
}

///|
/// Handle run_task message.
/// Format: {"type": "run_task", "session_id": "..."}
/// Triggers an agent run for a session that was created via REST API
/// (e.g. cron task run). The task content is already associated with the
/// session on the server side; if a `task` field is present it is used
/// directly as the message.
async fn handle_ws_run_task(
  server_ref : Ref[WebServer],
  _peer : @ws.WebSocketPeer,
  conn_id : String,
  hub : @broadcast.Hub,
  obj : Map[String, Json],
) -> Unit {
  let session_id = match resolve_session_id(hub, conn_id, obj) {
    Some(s) => s
    None => return
  }
  ensure_subscribed(hub, conn_id, session_id)
  let task = match obj.get("task") {
    Some(String(t)) => t
    _ => ""
  }
  if task.is_empty() {
    return
  }
  start_ws_run(server_ref, session_id, task)
}

///|
/// fix-08: Broadcast a partial session_update frame carrying latency
/// metrics (ttft_ms, duration_ms, output_tokens, tps) derived from the
/// agent's latest LLM call latency and the current usage data.
fn broadcast_latency_frame(
  hub : @broadcast.Hub,
  sid : String,
  agent : @agent.Agent,
  usage_data : @agent.IterationTokenData,
) -> Unit {
  match agent.latest_latency {
    Some(lat) => {
      let tps = if lat.duration_ms > 0 {
        usage_data.completion_tokens.to_double() *
        1000.0 /
        lat.duration_ms.to_double()
      } else {
        0.0
      }
      let ttft : Json = match lat.ttft_ms {
        Some(t) => t.to_json()
        None => Json::null()
      }
      let lat_inner : Map[String, Json] = {
        "ttft_ms": ttft,
        "duration_ms": lat.duration_ms.to_json(),
        "output_tokens": usage_data.completion_tokens.to_json(),
        "tps": tps.to_json(),
      }
      hub.broadcast_session_raw(
        sid,
        @protocol.build_event(
          @protocol.event_session_update,
          sid,
          Json::object({ "latency": Json::object(lat_inner) }),
        ),
      )
    }
    None => ()
  }
}

///|
/// Register the WS broadcast hook on the agent (exactly once per agent
/// instance). The hook:
///   - aggregates StreamChunk deltas into one complete assistant_message
///   - forwards token_delta events for real-time typing animation (T13)
///   - suppresses the complete/error events when the run was interrupted
///   - forwards every other event through the protocol event mapper
/// (Cancellation itself is delivered via Task::cancel on the run task;
/// hook callbacks cannot raise.)
fn register_ws_hooks(
  server_ref : Ref[WebServer],
  agent : @agent.Agent,
  session_id : String,
) -> Unit {
  // Guard against duplicate registration (repeated messages on the same
  // agent must not multiply broadcasts).
  if agent.hook_manager.callbacks.length() > 0 {
    return
  }
  let hub = server_ref.val.hub
  let sid = session_id
  let state = get_ws_state(sid)
  agent.hook_manager.register(fn(evt : @agent.HookEvent) {
    match evt {
      @agent.StreamChunk(chunk) => {
        // Aggregate; pushed as one complete assistant_message on MessageAdded.
        state.chunk_buf = state.chunk_buf + chunk
        // T13: Also forward token-level delta for real-time typing animation.
        hub.broadcast_session_raw(
          sid,
          @protocol.build_token_delta_event(sid, chunk),
        )
      }
      @agent.MessageAdded =>
        if state.chunk_buf.length() > 0 {
          let content = state.chunk_buf
          state.chunk_buf = ""
          hub.broadcast_session(
            sid,
            @protocol.build_event(
              @protocol.event_assistant_message,
              sid,
              Json::object({
                "role": "assistant".to_json(),
                "content": content.to_json(),
              }),
            ),
          )
        } else {
          hub.broadcast_session_raw(sid, @protocol.format_hook_event(sid, evt))
        }
      @agent.RunCompleted(_) =>
        if server_ref.val.cancelled.get(sid) == Some(true) {
          // Run was interrupted: the interrupted event was already sent by
          // the interrupt handler; suppress the contradictory complete.
          server_ref.val.cancelled[sid] = false
        } else {
          if state.chunk_buf.length() > 0 {
            // Flush any trailing partial chunk defensively.
            let content = state.chunk_buf
            state.chunk_buf = ""
            hub.broadcast_session(
              sid,
              @protocol.build_event(
                @protocol.event_assistant_message,
                sid,
                Json::object({
                  "role": "assistant".to_json(),
                  "content": content.to_json(),
                }),
              ),
            )
          }
          hub.broadcast_session_raw(sid, @protocol.format_hook_event(sid, evt))
        }
      @agent.ErrorOccurred(_) =>
        // Suppress the error event raised by an interrupt abort.
        if server_ref.val.cancelled.get(sid) != Some(true) {
          hub.broadcast_session_raw(sid, @protocol.format_hook_event(sid, evt))
        }
      @agent.UsageUpdated(usage_data) =>
        // I-040: Suppress duplicate token_usage frames where delta_tokens
        // is zero (no new information). The frontend builds a DOM row per
        // frame, so a second delta=0 frame creates a visually duplicate line.
        if usage_data.delta_tokens != 0 {
          hub.broadcast_session_raw(sid, @protocol.format_hook_event(sid, evt))
          // fix-08: Emit partial session_update frames for cost and latency
          // so the frontend can patch the session without a full snapshot.
          let cost_obj : Map[String, Json] = {
            "cost": usage_data.cost.to_json(),
            "cost_source": usage_data.cost_source.to_string_value().to_json(),
          }
          hub.broadcast_session_raw(
            sid,
            @protocol.build_event(
              @protocol.event_session_update,
              sid,
              Json::object(cost_obj),
            ),
          )
          broadcast_latency_frame(hub, sid, agent, usage_data)
        }
      @agent.ToolExecuting(name, args) => {
        // Time machine: snapshot file content before a write-type tool
        // modifies it (mirrors TUI agent_hooks.mbt pattern).
        if is_file_write_tool(name) {
          match json_string_field(args, "path") {
            Some(path) => {
              let content : String? = if @fs.path_exists(path) {
                Some(@fs.read_file_to_string(path) catch { _ => "" })
              } else {
                None
              }
              state.time_machine.record_file_before_change(path, content)
            }
            None => ()
          }
        }
        // Forward event to web UI
        hub.broadcast_session_raw(sid, @protocol.format_hook_event(sid, evt))
      }
      _ => hub.broadcast_session_raw(sid, @protocol.format_hook_event(sid, evt))
    }
  })
}

///|
/// Whether the tool modifies file contents (for time-machine snapshots).
fn is_file_write_tool(name : String) -> Bool {
  name == "write" ||
  name == "edit" ||
  name == "write_file" ||
  name == "file_edit" ||
  name == "create_file" ||
  name == "patch"
}

///|
/// Extract a string field from a JSON object text; None on any mismatch.
fn json_string_field(json_text : String, key : String) -> String? {
  let parsed = @json.parse(json_text) catch { _ => return None }
  match parsed {
    Object(obj) =>
      match obj.get(key) {
        Some(String(s)) => Some(s)
        _ => None
      }
    _ => None
  }
}

///|
/// Set up the async confirmation bridge for the agent (once per agent).
/// The agent pushes (tool, args) onto req_q and awaits a Bool on resp_q;
/// the bridge task broadcasts request_confirmation and waits (with timeout)
/// for the client's confirmation reply. Requires the WS task group; when
/// unavailable (unit tests), the agent keeps its headless default and tools
/// needing confirmation are denied.
fn setup_confirmation_bridge(
  server_ref : Ref[WebServer],
  agent : @agent.Agent,
  session_id : String,
) -> Unit {
  if agent.confirmation_request is Some(_) {
    return
  }
  match ws_task_group.val {
    Some(group) => {
      let req_q : @async.Queue[(String, String)] = @async.Queue::Queue(
        kind=Unbounded,
      )
      let resp_q : @async.Queue[Bool] = @async.Queue::Queue(kind=Unbounded)
      agent.confirmation_request = Some(req_q)
      agent.confirmation_response = Some(resp_q)
      group.spawn_bg(no_wait=true, allow_failure=true, () => {
        run_confirmation_bridge(server_ref, session_id, req_q, resp_q)
      })
    }
    None => ()
  }
}

///|
/// Confirmation bridge task: forwards agent confirmation requests to WS
/// clients and delivers their replies back to the agent. A reply that does
/// not arrive within 300s is treated as denied (mirrors the original Ruby
/// blocking-with-timeout semantics).
async fn run_confirmation_bridge(
  server_ref : Ref[WebServer],
  session_id : String,
  req_q : @async.Queue[(String, String)],
  resp_q : @async.Queue[Bool],
) -> Unit {
  let hub = server_ref.val.hub
  let state = get_ws_state(session_id)
  while true {
    let (tool, _) = req_q.get()
    state.confirm_seq = state.confirm_seq + 1
    let request_id = session_id + "-conf-" + state.confirm_seq.to_string()
    let reply_q : @async.Queue[Bool] = @async.Queue::Queue(kind=Unbounded)
    state.pending_confirmations[request_id] = reply_q
    hub.broadcast_session(
      session_id,
      @protocol.build_event(
        @protocol.event_request_confirmation,
        session_id,
        Json::object({
          "id": request_id.to_json(),
          "message": ("Allow tool \"" + tool + "\" to execute?").to_json(),
        }),
      ),
    )
    let answer = @async.with_timeout_opt(300_000, () => reply_q.get())
    state.pending_confirmations.remove(request_id)
    match answer {
      Some(ok) => resp_q.put(ok)
      None => {
        hub.broadcast_session(
          session_id,
          @protocol.build_error_event(
            session_id, "confirmation timed out, denied",
          ),
        )
        resp_q.put(false)
      }
    }
  }
}

///|
/// Set up the async feedback bridge for the agent (once per agent).
/// The agent pushes (question, context, options) onto req_q and awaits a
/// String on resp_q; the bridge task broadcasts request_feedback and waits
/// (with timeout) for the client's feedback reply. Requires the WS task
/// group; when unavailable (unit tests), feedback is unavailable.
fn setup_feedback_bridge(
  server_ref : Ref[WebServer],
  agent : @agent.Agent,
  session_id : String,
) -> Unit {
  if agent.feedback_request is Some(_) {
    return
  }
  match ws_task_group.val {
    Some(group) => {
      let req_q : @async.Queue[(String, String?, Array[String]?)] = @async.Queue::Queue(
        kind=Unbounded,
      )
      let resp_q : @async.Queue[String] = @async.Queue::Queue(kind=Unbounded)
      agent.feedback_request = Some(req_q)
      agent.feedback_response = Some(resp_q)
      group.spawn_bg(no_wait=true, allow_failure=true, () => {
        run_feedback_bridge(server_ref, session_id, req_q, resp_q)
      })
    }
    None => ()
  }
}

///|
/// Feedback bridge task: forwards agent feedback requests to WS clients
/// and delivers their replies back to the agent. A reply that does not
/// arrive within 300s is treated as empty (mirrors confirmation timeout).
async fn run_feedback_bridge(
  server_ref : Ref[WebServer],
  session_id : String,
  req_q : @async.Queue[(String, String?, Array[String]?)],
  resp_q : @async.Queue[String],
) -> Unit {
  let hub = server_ref.val.hub
  let state = get_ws_state(session_id)
  while true {
    let (question, context, options) = req_q.get()
    state.confirm_seq = state.confirm_seq + 1
    let request_id = session_id + "-fb-" + state.confirm_seq.to_string()
    let reply_q : @async.Queue[String] = @async.Queue::Queue(kind=Unbounded)
    state.pending_feedback[request_id] = reply_q
    let opt_json : Json = match options {
      Some(arr) => arr.to_json()
      None => Json::null()
    }
    let ctx_json : Json = match context {
      Some(c) => c.to_json()
      None => Json::null()
    }
    hub.broadcast_session(
      session_id,
      @protocol.build_event(
        @protocol.event_request_feedback,
        session_id,
        Json::object({
          "id": request_id.to_json(),
          "question": question.to_json(),
          "context": ctx_json,
          "options": opt_json,
        }),
      ),
    )
    let answer = @async.with_timeout_opt(300_000, () => reply_q.get())
    state.pending_feedback.remove(request_id)
    match answer {
      Some(text) => resp_q.put(text)
      None => {
        hub.broadcast_session(
          session_id,
          @protocol.build_error_event(
            session_id, "feedback timed out, empty response",
          ),
        )
        resp_q.put("")
      }
    }
  }
}

///|
/// Handle feedback message (client -> server).
/// Format: {"type": "feedback", "session_id": "...", "id": "...", "content": "..."}
/// Delivers the reply to the pending feedback queue that the feedback
/// bridge is awaiting, then acknowledges the client.
fn handle_ws_feedback(
  _server_ref : Ref[WebServer],
  peer : @ws.WebSocketPeer,
  obj : Map[String, Json],
) -> Unit {
  let request_id = match obj.get("id") {
    Some(String(rid)) => rid
    _ => {
      peer.text(@protocol.build_error_event("", "missing id"))
      return
    }
  }
  let content = match obj.get("content") {
    Some(String(c)) => c
    _ => ""
  }
  // Deliver the reply to the pending feedback, if any.
  let mut delivered = false
  match obj.get("session_id") {
    Some(String(sid)) if !sid.is_empty() =>
      match ws_states.get(sid) {
        Some(state) =>
          match state.pending_feedback.get(request_id) {
            Some(q) => {
              ignore(q.try_put(content) catch { _ => false })
              delivered = true
            }
            None => ()
          }
        None => ()
      }
    _ =>
      for _, state in ws_states {
        match state.pending_feedback.get(request_id) {
          Some(q) => {
            ignore(q.try_put(content) catch { _ => false })
            delivered = true
            break
          }
          None => ()
        }
      }
  } // Acknowledge the client.
  peer.text(
    @protocol.build_global_event(
      "feedback_response",
      Json::object({
        "request_id": request_id.to_json(),
        "received": delivered.to_json(),
      }),
    ),
  )
}

///|
/// Start an agent run for a session. Registers hooks/confirmation bridge,
/// echoes the user message, clears the cancel flag, and dispatches the run
/// to a background async task so the WS read loop returns immediately.
/// 
/// `images` carries inline base64 images (if any) that are injected into
/// the agent history as `ContentBlock::Image` blocks BEFORE the run
/// starts, mirroring the observe() tool-result image_inject path.
async fn start_ws_run(
  server_ref : Ref[WebServer],
  session_id : String,
  message : String,
  images? : Array[(String, String, String?)] = [],
) -> Unit {
  let hub = server_ref.val.hub
  let state = get_ws_state(session_id)
  if state.running {
    hub.broadcast_session(
      session_id,
      @protocol.build_error_event(
        session_id, "a run is already in progress for this session",
      ),
    )
    return
  }
  let agent = server_ref.val.get_or_create_agent(session_id)
  register_ws_hooks(server_ref, agent, session_id)
  setup_confirmation_bridge(server_ref, agent, session_id)
  setup_feedback_bridge(server_ref, agent, session_id)

  // Time machine: open a new task so file writes in this run can be undone
  ignore(state.time_machine.start_new_task(Some(message)))

  // Inject inline base64 images into the agent history before the run
  // starts. Each image becomes a `role:"user"` message with a
  // ContentBlock::Image, identical to the observe() tool-result path.
  // The user's text message is then run as the next user turn.
  if images.length() > 0 {
    for entry in images {
      let (base64_data, mime_type, path) = entry
      agent.inject_user_image(base64_data, mime_type, path~)
    }
  }

  // Echo the user message back as history_user_message.
  hub.broadcast_session(
    session_id,
    @protocol.build_history_user_message(session_id, message),
  )

  // Clear any stale cancel flag, mark the run as active.
  server_ref.val.cancelled[session_id] = false
  state.running = true
  state.chunk_buf = ""
  match ws_task_group.val {
    Some(group) => {
      let task = group.spawn(no_wait=true, allow_failure=true, () => {
        run_ws_agent(server_ref, session_id, agent, message)
      })
      state.running_task = Some(task)
    }
    // Fallback for environments without a task group (unit tests): run
    // synchronously. The WS read loop is not active in that context.
    None => run_ws_agent_blocking(server_ref, session_id, agent, message)
  }
}

///|
/// Async agent run worker: executes the run without blocking the WS read
/// loop. The complete event is broadcast by the RunCompleted hook mapping;
/// here we only handle errors, interrupts, and session persistence.
async fn run_ws_agent(
  server_ref : Ref[WebServer],
  session_id : String,
  agent : @agent.Agent,
  message : String,
) -> Unit {
  let hub = server_ref.val.hub
  let state = get_ws_state(session_id)
  let result = agent.run_async(message) catch {
    err => {
      state.running = false
      state.running_task = None
      state.chunk_buf = ""
      if server_ref.val.cancelled.get(session_id) == Some(true) ||
        @async.is_cancellation_error(err) {
        // Interrupted: the interrupted event was already broadcast by the
        // interrupt handler; clear the flag and suppress the error.
        server_ref.val.cancelled[session_id] = false
      } else {
        let err_msg = if @errors.is_agent_error(err) {
          @errors.error_message(err)
        } else {
          "Agent execution failed"
        }
        hub.broadcast_session(
          session_id,
          @protocol.build_error_event(session_id, err_msg),
        )
      }
      // B-2026-07-26-03: After error / interrupt, send the same closing
      // frames as a normal run end so the frontend status bar transitions
      // to idle and the progress indicator clears. Without these, the
      // frontend stays stuck on "running" with the stop button visible
      // until the page is reloaded. On the interrupt path, the cancel
      // handler has already sent an `interrupted` event; the closing
      // frames are still required so the status bar follows up.
      hub.broadcast_session(
        session_id,
        @protocol.build_event(
          @protocol.event_session_update,
          session_id,
          Json::object({ "status": "idle".to_json() }),
        ),
      )
      hub.broadcast_session(
        session_id,
        @protocol.build_event(
          @protocol.event_progress,
          session_id,
          Json::object({ "phase": "done".to_json() }),
        ),
      )
      // Persist even on error so the user's input is not lost.
      let err_data = agent.to_session_data()
      @agent.save_session(err_data) catch {
        _ => ()
      }
      return
    }
  }
  ignore(result)
  state.running = false
  state.running_task = None

  // Persist the session after a successful run.
  let data = agent.to_session_data()
  @agent.save_session(data) catch {
    _ => ()
  }
  // Content-based auto-rename for placeholder ("Session N") sessions.
  maybe_auto_rename_session(hub, agent, session_id)
  @agent.enforce_session_cap()
  // I-029: Broadcast task_finished to session subscribers (not global).
  // The frontend subscribes per-session; global_subs is empty during normal
  // browsing, so broadcast_global never reaches the client.
  hub.broadcast_session(
    session_id,
    @protocol.build_task_finished_event(session_id),
  )
}

///|
/// Fallback of run_ws_agent for contexts without a task group
/// (unit tests dispatching events without a running server).
async fn run_ws_agent_blocking(
  server_ref : Ref[WebServer],
  session_id : String,
  agent : @agent.Agent,
  message : String,
) -> Unit {
  let hub = server_ref.val.hub
  let state = get_ws_state(session_id)
  let result = agent.run(message) catch {
    err => {
      state.running = false
      state.running_task = None
      state.chunk_buf = ""
      if server_ref.val.cancelled.get(session_id) == Some(true) {
        server_ref.val.cancelled[session_id] = false
      } else {
        let err_msg = if @errors.is_agent_error(err) {
          @errors.error_message(err)
        } else {
          "Agent execution failed"
        }
        hub.broadcast_session(
          session_id,
          @protocol.build_error_event(session_id, err_msg),
        )
      }
      // B-2026-07-26-03: Same closing frames as the async path so the
      // frontend status bar transitions to idle in fallback contexts
      // (unit tests, environments without a task group) too.
      hub.broadcast_session(
        session_id,
        @protocol.build_event(
          @protocol.event_session_update,
          session_id,
          Json::object({ "status": "idle".to_json() }),
        ),
      )
      hub.broadcast_session(
        session_id,
        @protocol.build_event(
          @protocol.event_progress,
          session_id,
          Json::object({ "phase": "done".to_json() }),
        ),
      )
      // Persist even on error so the user's input is not lost.
      let err_data = agent.to_session_data()
      @agent.save_session(err_data) catch {
        _ => ()
      }
      return
    }
  }
  ignore(result)
  state.running = false
  state.running_task = None
  let data = agent.to_session_data()
  @agent.save_session(data) catch {
    _ => ()
  }
  // Content-based auto-rename for placeholder ("Session N") sessions.
  maybe_auto_rename_session(hub, agent, session_id)
  @agent.enforce_session_cap()
  // I-029: Broadcast task_finished to session subscribers (same as async path).
  hub.broadcast_session(
    session_id,
    @protocol.build_task_finished_event(session_id),
  )
}

///|
/// Placeholder names assigned at creation time ("Session N") are eligible
/// for content-based auto-renaming; user-chosen names are never touched.
fn is_placeholder_session_name(name : String) -> Bool {
  if !name.has_prefix("Session ") {
    return false
  }
  let digits = name[8:].to_owned()
  if digits.is_empty() {
    return false
  }
  for c in digits {
    if !(c >= '0' && c <= '9') {
      return false
    }
  }
  true
}

///|
/// Extract plain text from a message (local mirror of the protocol helper).
fn ws_message_text(msg : @message.Message) -> String {
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
      buf.join(" ")
    }
  }
}

///|
/// Derive a session title from the first user message: collapse all
/// whitespace runs to single spaces and cap at 30 chars with an ellipsis.
fn derive_session_title(text : String) -> String {
  let buf = StringBuilder::new()
  let mut last_was_space = true // also trims leading whitespace
  let mut count = 0
  let mut truncated = false
  for c in text {
    if c.is_whitespace() {
      if !last_was_space {
        if count >= 30 {
          truncated = true
          break
        }
        buf.write_char(' ')
        last_was_space = true
        count = count + 1
      }
    } else {
      if count >= 30 {
        truncated = true
        break
      }
      buf.write_char(c)
      last_was_space = false
      count = count + 1
    }
  }
  let mut title = buf.to_string()
  while title.has_suffix(" ") {
    title = title[:title.length() - 1].to_owned()
  }
  if truncated {
    title = title + "…"
  }
  title
}

///|
/// Auto-rename a placeholder session ("Session N") from its first real user
/// message (skipping injected context), persisting and broadcasting so the
/// sidebar updates live.
fn maybe_auto_rename_session(
  hub : @broadcast.Hub,
  agent : @agent.Agent,
  session_id : String,
) -> Unit {
  if !is_placeholder_session_name(agent.name) {
    return
  }
  for m in agent.history.all() {
    if m.role is @message.User && !(m.system_injected is Some(true)) {
      let title = derive_session_title(ws_message_text(m))
      if !title.is_empty() && title != agent.name {
        agent.rename(title)
        @agent.save_session(agent.to_session_data()) catch {
          _ => ()
        }
        hub.broadcast_session(
          session_id,
          @protocol.build_session_renamed_event(session_id, title),
        )
      }
      return
    }
  }
}
