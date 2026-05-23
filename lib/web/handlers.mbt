///| All HTTP handler functions for the web server.

// ── Session Handlers ────────────────────────────────────────────

///|
/// GET /api/sessions
fn handle_list_sessions(
  _server_ref : Ref[WebServer],
  _event : @crescent.Event,
) -> @core.HttpResponse {
  let sessions = @agent.list_sessions()
  @core.HttpResponse::ok().json_value(
    SessionListResponse::{ sessions, }.to_json(),
  )
}

///|
/// POST /api/sessions
fn handle_create_session(
  server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let j : Json = event.req.body() catch {
    _ => Json::object({ "name": "Web Session".to_json() })
  }
  let name : String = match j {
    Object(obj) =>
      match obj.get("name") {
        Some(String(n)) => n
        _ => "Web Session"
      }
    _ => "Web Session"
  }
  let session_id = @agent.generate_session_id()
  let model_config = match server_ref.val.config.current_model() {
    Some(mc) => mc
    None =>
      return @core.HttpResponse::internal_server_error().json_value(
        Json::object({ "error": "No model configured".to_json() }),
      )
  }
  let api_type = if model_config.anthropic_format {
    @config.AnthropicMessages
  } else {
    @config.Providers::api_type_for(model_config.base_url)
  }
  let client = @client.Client::new(
    model_config.api_key,
    model_config.base_url,
    model_config.model,
    api_type,
  )
  let agent = @agent.Agent::new(
    session_id,
    name,
    ".",
    client,
    server_ref.val.config,
  )
  server_ref.val.active_agents[session_id] = agent
  let data = agent.to_session_data()
  @core.HttpResponse::created().json_value(data.to_json())
}

///|
/// GET /api/sessions/:id
fn handle_get_session(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let id = match event.param("id") {
    Some(p) => p.to_string()
    None =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": "Missing parameter: id".to_json() }),
      )
  }
  let session_opt = @agent.load_session(id) catch { _ => None }
  match session_opt {
    Some(data) => @core.HttpResponse::ok().json_value(data.to_json())
    None =>
      @core.HttpResponse::not_found().json_value(
        Json::object({ "error": "Session not found".to_json() }),
      )
  }
}

///|
/// DELETE /api/sessions/:id
fn handle_delete_session(
  server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let id = match event.param("id") {
    Some(p) => p.to_string()
    None =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": "Missing parameter: id".to_json() }),
      )
  }
  @agent.delete_session(id)
  let _ = server_ref.val.active_agents.remove(id)
  @core.HttpResponse::no_content()
}

///|
/// POST /api/sessions/:id/restore
fn handle_restore_session(
  server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let id = match event.param("id") {
    Some(p) => p.to_string()
    None =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": "Missing parameter: id".to_json() }),
      )
  }
  let session_opt = @agent.load_session(id) catch { _ => None }
  match session_opt {
    Some(data) => {
      let agent = server_ref.val.get_or_create_agent(id)
      agent.restore_from_session(data)
      @core.HttpResponse::ok().json_value(agent.to_session_data().to_json())
    }
    None =>
      @core.HttpResponse::not_found().json_value(
        Json::object({ "error": "Session not found".to_json() }),
      )
  }
}

// ── Chat Handlers ───────────────────────────────────────────────

///|

///|
/// POST /api/sessions/:id/chat
fn handle_chat(
  server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let id = match event.param("id") {
    Some(p) => p.to_string()
    None =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": "Missing parameter: id".to_json() }),
      )
  }
  let j : Json = event.req.body() catch {
    _ =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": "Invalid JSON body".to_json() }),
      )
  }
  let message : String = match j {
    Object(obj) =>
      match obj.get("message") {
        Some(String(m)) => m
        _ =>
          return @core.HttpResponse::bad_request().json_value(
            Json::object({ "error": "Missing 'message' field".to_json() }),
          )
      }
    _ =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": "Invalid JSON body".to_json() }),
      )
  }

  let agent = server_ref.val.get_or_create_agent(id)
  let result = agent.run(message) catch {
    err if @errors.is_agent_error(err) => {
      let err_str = err.to_string()
      @agent.RunResult::{
        status: @agent.RunStatus::Error,
        session_id: id,
        iterations: agent.iterations,
        total_cost_usd: agent.total_cost,
        cost_source: agent.cost_source,
        cache_stats: agent.cache_stats,
        error: Some(err_str),
      }
    }
    err => {
      println("[web] unhandled error: \{err}")
      @agent.RunResult::{
        status: @agent.RunStatus::Error,
        session_id: id,
        iterations: agent.iterations,
        total_cost_usd: agent.total_cost,
        cost_source: agent.cost_source,
        cache_stats: agent.cache_stats,
        error: Some("Internal error"),
      }
    }
  }

  // Save session after execution
  let data = agent.to_session_data()
  @agent.save_session(data) catch {
    _ => ()
  }
  @agent.enforce_session_cap()

  let response = ChatResponse::{
    session_id: id,
    messages: data.messages,
    total_cost_usd: result.total_cost_usd,
    iterations: result.iterations,
    status: result.status.to_string_value(),
  }
  @core.HttpResponse::ok().json_value(response.to_json())
}

///|

///|
/// POST /api/sessions/:id/chat/stream
fn handle_chat_stream(
  server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let id = match event.param("id") {
    Some(p) => p.to_string()
    None =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": "Missing parameter: id".to_json() }),
      )
  }
  let j : Json = event.req.body() catch {
    _ =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": "Invalid JSON body".to_json() }),
      )
  }
  let message : String = match j {
    Object(obj) =>
      match obj.get("message") {
        Some(String(m)) => m
        _ =>
          return @core.HttpResponse::bad_request().json_value(
            Json::object({ "error": "Missing 'message' field".to_json() }),
          )
      }
    _ =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": "Invalid JSON body".to_json() }),
      )
  }

  let agent = server_ref.val.get_or_create_agent(id)

  // Register hook callback to capture events
  let captured : Array[@sse.CapturedHookEvent] = []
  agent.hook_manager.register(fn(evt : @agent.HookEvent) {
    captured.push(@sse.capture_hook_event(evt))
  })

  // Run agent (blocking)
  let result = agent.run(message) catch {
    err if @errors.is_agent_error(err) => {
      let err_str = err.to_string()
      @agent.RunResult::{
        status: @agent.RunStatus::Error,
        session_id: id,
        iterations: agent.iterations,
        total_cost_usd: agent.total_cost,
        cost_source: agent.cost_source,
        cache_stats: agent.cache_stats,
        error: Some(err_str),
      }
    }
    err => {
      println("[web] unhandled error: \{err}")
      @agent.RunResult::{
        status: @agent.RunStatus::Error,
        session_id: id,
        iterations: agent.iterations,
        total_cost_usd: agent.total_cost,
        cost_source: agent.cost_source,
        cache_stats: agent.cache_stats,
        error: Some("Internal error"),
      }
    }
  }

  // Save session after execution
  let data = agent.to_session_data()
  @agent.save_session(data) catch {
    _ => ()
  }

  // Build SSE body from captured events
  let sse_body = @sse.build_sse_body(captured, result)

  @core.HttpResponse::ok()
  .header("Content-Type", "text/event-stream")
  .header("Cache-Control", "no-cache")
  .header("Connection", "keep-alive")
  .body(sse_body)
}

///|

///|
/// GET /api/sessions/:id/status
fn handle_get_status(
  server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let id = match event.param("id") {
    Some(p) => p.to_string()
    None =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": "Missing parameter: id".to_json() }),
      )
  }
  match server_ref.val.active_agents.get(id) {
    Some(agent) => {
      let response = StatusResponse::{
        session_id: id,
        status: agent.status.to_string_value(),
        iterations: agent.iterations,
        error: agent.error,
      }
      @core.HttpResponse::ok().json_value(response.to_json())
    }
    None => {
      let session_opt = @agent.load_session(id)
      match session_opt {
        Some(data) => {
          let response = StatusResponse::{
            session_id: id,
            status: "idle",
            iterations: data.stats.total_iterations,
            error: None,
          }
          @core.HttpResponse::ok().json_value(response.to_json())
        }
        None =>
          @core.HttpResponse::not_found().json_value(
            Json::object({ "error": "Session not found".to_json() }),
          )
      }
    }
  }
}

///|

///|
/// POST /api/sessions/:id/cancel
fn handle_cancel(
  server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let id = match event.param("id") {
    Some(p) => p.to_string()
    None =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": "Missing parameter: id".to_json() }),
      )
  }
  server_ref.val.cancelled[id] = true
  let response = CancelResponse::{ cancelled: true }
  @core.HttpResponse::ok().json_value(response.to_json())
}

///|

///|
/// GET /api/sessions/:id/cost
fn handle_get_cost(
  server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let id = match event.param("id") {
    Some(p) => p.to_string()
    None =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": "Missing parameter: id".to_json() }),
      )
  }
  match server_ref.val.active_agents.get(id) {
    Some(agent) => {
      let response = CostResponse::{
        session_id: id,
        total_cost_usd: agent.total_cost,
        cost_source: agent.cost_source.to_string_value(),
        cache_creation_input_tokens: agent.cache_stats.cache_creation_input_tokens,
        cache_read_input_tokens: agent.cache_stats.cache_read_input_tokens,
        total_requests: agent.cache_stats.total_requests,
        cache_hit_requests: agent.cache_stats.cache_hit_requests,
      }
      @core.HttpResponse::ok().json_value(response.to_json())
    }
    None => {
      let session_opt = @agent.load_session(id)
      match session_opt {
        Some(data) => {
          let response = CostResponse::{
            session_id: id,
            total_cost_usd: data.stats.total_cost_usd,
            cost_source: data.stats.cost_source,
            cache_creation_input_tokens: data.stats.cache_creation_input_tokens,
            cache_read_input_tokens: data.stats.cache_read_input_tokens,
            total_requests: data.stats.total_requests,
            cache_hit_requests: data.stats.cache_hit_requests,
          }
          @core.HttpResponse::ok().json_value(response.to_json())
        }
        None =>
          @core.HttpResponse::not_found().json_value(
            Json::object({ "error": "Session not found".to_json() }),
          )
      }
    }
  }
}

///|

///|
/// GET /api/sessions/:id/tools
fn handle_list_tools(
  server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let id = match event.param("id") {
    Some(p) => p.to_string()
    None =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": "Missing parameter: id".to_json() }),
      )
  }
  let agent = server_ref.val.get_or_create_agent(id)
  let tool_names = agent.tool_registry.tool_names()
  let tools : Array[ToolListEntry] = []
  for name in tool_names {
    match agent.tool_registry.get(name) {
      Some(t) => tools.push({ name, description: t.description() })
      None => ()
    }
  }
  let response = ToolListResponse::{ tools, }
  @core.HttpResponse::ok().json_value(response.to_json())
}

// ── Config Handlers ─────────────────────────────────────────────

///|
/// GET /api/config
fn handle_get_config(
  server_ref : Ref[WebServer],
  _event : @crescent.Event,
) -> @core.HttpResponse {
  let cfg = server_ref.val.config
  let response = ConfigResponse::{
    permission_mode: permission_mode_str(cfg.permission_mode),
    max_tokens: cfg.max_tokens,
    verbose: cfg.verbose,
    current_model_id: cfg.current_model_id,
  }
  @core.HttpResponse::ok().json_value(response.to_json())
}

///|
fn permission_mode_str(mode : @config.PermissionMode) -> String {
  match mode {
    @config.AutoApprove => "auto_approve"
    @config.ConfirmSafes => "confirm_safes"
    @config.ConfirmAll => "confirm_all"
  }
}

///|
/// PUT /api/config
fn handle_update_config(
  server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let cfg = server_ref.val.config
  let j : Json = event.req.body() catch {
    _ =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": "Invalid JSON body".to_json() }),
      )
  }
  match j {
    Object(obj) => {
      match obj.get("permission_mode") {
        Some(String(mode_str)) => {
          let mode = match mode_str {
            "auto_approve" => @config.AutoApprove
            "confirm_safes" => @config.ConfirmSafes
            "confirm_all" => @config.ConfirmAll
            _ => cfg.permission_mode
          }
          cfg.permission_mode = mode
        }
        _ => ()
      }
      match obj.get("max_tokens") {
        Some(Number(n, ..)) => cfg.max_tokens = n.to_int()
        _ => ()
      }
      match obj.get("verbose") {
        Some(True) => cfg.verbose = true
        _ => ()
      }
    }
    _ => ()
  }
  handle_get_config(server_ref, event)
}

///|
/// GET /api/config/models
fn handle_list_models(
  server_ref : Ref[WebServer],
  _event : @crescent.Event,
) -> @core.HttpResponse {
  let response = ModelListResponse::{ models: server_ref.val.config.models }
  @core.HttpResponse::ok().json_value(response.to_json())
}

///|
/// GET /api/config/permissions
fn handle_get_permissions(
  server_ref : Ref[WebServer],
  _event : @crescent.Event,
) -> @core.HttpResponse {
  let mode_str = permission_mode_str(server_ref.val.config.permission_mode)
  let response = PermissionResponse::{
    permission_mode: mode_str,
    safe_tools: ["file_reader", "grep", "glob", "web_search"],
  }
  @core.HttpResponse::ok().json_value(response.to_json())
}

// ── Stats Handlers ──────────────────────────────────────────────

///|
/// GET /api/stats
fn handle_get_stats(
  _server_ref : Ref[WebServer],
  _event : @crescent.Event,
) -> @core.HttpResponse {
  let sessions = @agent.list_sessions()
  let mut total_cost = 0.0
  let mut total_iterations = 0
  let mut total_tasks = 0
  for s in sessions {
    total_cost = total_cost + s.stats.total_cost_usd
    total_iterations = total_iterations + s.stats.total_iterations
    total_tasks = total_tasks + s.stats.total_tasks
  }
  let response = StatsResponse::{
    total_sessions: sessions.length(),
    total_cost_usd: total_cost,
    total_iterations,
    total_tasks,
  }
  @core.HttpResponse::ok().json_value(response.to_json())
}

///|
/// GET /api/stats/aggregate
fn handle_get_aggregate_stats(
  _server_ref : Ref[WebServer],
  _event : @crescent.Event,
) -> @core.HttpResponse {
  let sessions = @agent.list_sessions()
  let mut total_cost = 0.0
  let mut total_messages = 0
  for s in sessions {
    total_cost = total_cost + s.stats.total_cost_usd
    total_messages = total_messages + s.messages.length()
  }
  let response = AggregateStatsResponse::{
    total_cost_usd: total_cost,
    session_count: sessions.length(),
    total_messages,
  }
  @core.HttpResponse::ok().json_value(response.to_json())
}

// ── Info Handler ────────────────────────────────────────────────

///|
/// GET /api/info
fn handle_info(
  server_ref : Ref[WebServer],
  _event : @crescent.Event,
) -> @core.HttpResponse {
  let s = server_ref.val
  let uptime = @async.now() - s.start_time
  let response = InfoResponse::{
    version: "0.1.0",
    name: "MBOpenClacky",
    uptime_seconds: uptime,
    active_sessions: s.active_agents.size(),
  }
  @core.HttpResponse::ok().json_value(response.to_json())
}

// ── WebSocket Handler ─────────────────────────────────────────────

///|

///|
/// Handle WebSocket events for /ws/sessions/:id
fn handle_websocket(
  server_ref : Ref[WebServer],
  event : @ws.WebSocketEvent,
) -> Unit {
  match event {
    Open(peer) => {
      let session_id = peer.param("session_id")
      let sid = match session_id {
        Some(id) => id
        None => "unknown"
      }
      peer.text("{ \"type\": \"connected\", \"session_id\": \"\{sid}\" }")
    }
    Message(peer, msg) =>
      match msg {
        Text(text) => {
          let json = @json.parse(text) catch { _ => return }
          let message : String = match json {
            Object(obj) =>
              match obj.get("message") {
                Some(String(m)) => m
                _ => return
              }
            _ => return
          }
          let session_id = peer.param("session_id")
          let sid = match session_id {
            Some(id) => id
            None => return
          }

          let agent = server_ref.val.get_or_create_agent(sid)

          // Capture hook events
          let captured : Array[@sse.CapturedHookEvent] = []
          agent.hook_manager.register(fn(evt : @agent.HookEvent) {
            captured.push(@sse.capture_hook_event(evt))
          })

          // Run agent (blocking)
          let _result = agent.run(message) catch {
            _ => {
              peer.text(
                "{ \"type\": \"error\", \"message\": \"Agent execution failed\" }",
              )
              return
            }
          }

          // Send captured events via WebSocket
          for evt in captured {
            let payload = "event: \{evt.event_type}\ndata: \{evt.data.to_string()}"
            peer.text(payload)
          }

          // Send final done event
          peer.text("{ \"type\": \"done\", \"session_id\": \"\{sid}\" }")

          // Save session
          let data = agent.to_session_data()
          @agent.save_session(data) catch {
            _ => ()
          }
        }
        Binary(_) => ()
      }
    Close(_peer) => ()
  }
}
