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
  /// (spec decision 3: no token-level streaming on the WS path).
  mut chunk_buf : String
  /// Sequence counter for confirmation request ids.
  mut confirm_seq : Int
  /// Pending confirmation replies, keyed by request_id. The WS
  /// `confirmation` upstream message resolves the queue; the confirmation
  /// bridge task awaits it with a timeout.
  pending_confirmations : Map[String, @async.Queue[Bool]]
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
fn handle_ws_global(
  server_ref : Ref[WebServer],
  event : @ws.WebSocketEvent,
) -> Unit {
  match event {
    Open(peer) => {
      let hub = server_ref.val.hub
      hub.register(peer)
      // Send connected event (no session binding yet).
      peer.text(@protocol.build_connected_event(""))
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

  // Switch to the new session (unsubscribe old, subscribe new).
  hub.switch_session(conn_id, target)
  peer.text(@protocol.build_subscribed_event(target))

  // Send session snapshot if session exists.
  let session_opt = @agent.load_session(target)
  match session_opt {
    Some(data) => peer.text(@protocol.build_session_snapshot(data))
    None =>
      // Check in-memory active agents.
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
fn send_session_list(
  _server_ref : Ref[WebServer],
  peer : @ws.WebSocketPeer,
) -> Unit {
  let all_sessions = @agent.list_sessions()
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
        model: sd.model_name,
        source: sd.source,
        latest_latency_ms: sd.latest_latency_ms,
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
      }
    None => ()
  }
}

///|
/// Handle message (chat) message.
/// Format: {"type": "message", "session_id": "...", "message": "..."}
/// Echoes the user message and starts an async agent run.
fn handle_ws_message(
  server_ref : Ref[WebServer],
  _peer : @ws.WebSocketPeer,
  conn_id : String,
  hub : @broadcast.Hub,
  obj : Map[String, Json],
) -> Unit {
  let message = match obj.get("message") {
    Some(String(m)) => m
    _ => return
  }
  let session_id = match resolve_session_id(hub, conn_id, obj) {
    Some(s) => s
    None => return
  }
  ensure_subscribed(hub, conn_id, session_id)
  start_ws_run(server_ref, session_id, message)
}

///|
/// Handle edit_message message.
/// Format: {"type": "edit_message", "session_id": "...", "message": "..."}
/// Replaces the last user message in the agent history (dropping everything
/// after it) and re-runs the agent.
fn handle_ws_edit_message(
  server_ref : Ref[WebServer],
  _peer : @ws.WebSocketPeer,
  conn_id : String,
  hub : @broadcast.Hub,
  obj : Map[String, Json],
) -> Unit {
  let message = match obj.get("message") {
    Some(String(m)) => m
    _ => return
  }
  let session_id = match resolve_session_id(hub, conn_id, obj) {
    Some(s) => s
    None => return
  }
  ensure_subscribed(hub, conn_id, session_id)
  let agent = server_ref.val.get_or_create_agent(session_id)
  // Locate the last user message in the agent history.
  let mut last_user_idx = -1
  for i, m in agent.history {
    if m.role is @message.User {
      last_user_idx = i
    }
  }
  if last_user_idx < 0 {
    hub.broadcast_session(
      session_id,
      @protocol.build_error_event(session_id, "no user message to edit"),
    )
    return
  }
  // Drop the last user message and everything after it; the run re-pushes
  // the edited message as the new last user message.
  while agent.history.length() > last_user_idx {
    ignore(agent.history.pop())
  }
  start_ws_run(server_ref, session_id, message)
}

///|
/// Handle confirmation message.
/// Format: {"type": "confirmation", "request_id": "...", "confirmed": true/false}
/// Delivers the reply to the pending confirmation queue that the
/// confirmation bridge is awaiting, then acknowledges the client.
fn handle_ws_confirmation(
  _server_ref : Ref[WebServer],
  peer : @ws.WebSocketPeer,
  obj : Map[String, Json],
) -> Unit {
  let request_id = match obj.get("request_id") {
    Some(String(rid)) => rid
    _ => {
      peer.text(@protocol.build_error_event("", "missing request_id"))
      return
    }
  }
  let confirmed = match obj.get("confirmed") {
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
/// Format: {"type": "run_task", "session_id": "...", "task": "..."}
/// Runs a background task in the session context.
fn handle_ws_run_task(
  server_ref : Ref[WebServer],
  _peer : @ws.WebSocketPeer,
  conn_id : String,
  hub : @broadcast.Hub,
  obj : Map[String, Json],
) -> Unit {
  let task = match obj.get("task") {
    Some(String(t)) => t
    _ => return
  }
  let session_id = match resolve_session_id(hub, conn_id, obj) {
    Some(s) => s
    None => return
  }
  ensure_subscribed(hub, conn_id, session_id)

  // Broadcast progress start.
  hub.broadcast_session(
    session_id,
    @protocol.build_event(
      @protocol.event_progress,
      session_id,
      Json::object({ "phase": "task_start".to_json(), "task": task.to_json() }),
    ),
  )
  start_ws_run(server_ref, session_id, task)
}

///|
/// Register the WS broadcast hook on the agent (exactly once per agent
/// instance). The hook:
///   - aggregates StreamChunk deltas into one complete assistant_message
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
      @agent.StreamChunk(chunk) =>
        // Aggregate; pushed as one complete assistant_message on MessageAdded.
        state.chunk_buf = state.chunk_buf + chunk
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
      _ => hub.broadcast_session_raw(sid, @protocol.format_hook_event(sid, evt))
    }
  })
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
    let (tool, args) = req_q.get()
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
          "request_id": request_id.to_json(),
          "tool": tool.to_json(),
          "arguments": args.to_json(),
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
/// Start an agent run for a session. Registers hooks/confirmation bridge,
/// echoes the user message, clears the cancel flag, and dispatches the run
/// to a background async task so the WS read loop returns immediately.
fn start_ws_run(
  server_ref : Ref[WebServer],
  session_id : String,
  message : String,
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
  @agent.enforce_session_cap()
}

///|
/// Synchronous fallback of run_ws_agent for contexts without a task group
/// (unit tests dispatching events without a running server).
fn run_ws_agent_blocking(
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
  @agent.enforce_session_cap()
}
