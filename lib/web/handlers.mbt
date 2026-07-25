///| All HTTP handler functions for the web server.

// ── Session Handlers ────────────────────────────────────────────

///|
/// GET /api/sessions
fn handle_list_sessions(
  server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  // Parse query parameters
  let limit_raw = event.req.get_query("limit").unwrap_or("20")
  let limit = (@string.parse_int(limit_raw.to_string_view()) catch { _ => 20 })
    .min(50)
    .max(1)
  let q_filter = event.req.get_query("q").unwrap_or("")
  let before = event.req.get_query("before")
  let type_filter = event.req.get_query("type")
  let exclude_type = event.req.get_query("exclude_type")
  // Fetch all sessions and map to summaries
  let all_sessions = @agent.list_sessions()
  let pinned_map = load_pinned_map()
  // Build sub_model_options from configured models.
  let model_options : Array[String] = server_ref.val.config.models.map(m => {
    m.model
  })
  // Fallback model for legacy session files missing model_name.
  let default_model : String? = match server_ref.val.config.current_model() {
    Some(mc) => Some(mc.model)
    None => None
  }
  let summaries : Array[SessionSummary] = []
  for sd in all_sessions {
    // Apply text search filter (name contains q)
    if q_filter.length() > 0 && !sd.name.contains(q_filter) {
      continue
    }
    // Apply before cursor: only sessions created before the cursor
    // (ISO 8601 timestamps compare lexicographically).
    match before {
      Some(b) => if !b.is_empty() && sd.created_at >= b { continue }
      None => ()
    }
    // Apply type filters against the session source field.
    match type_filter {
      Some(t) => if !t.is_empty() && sd.source != t { continue }
      None => ()
    }
    match exclude_type {
      Some(t) => if !t.is_empty() && sd.source == t { continue }
      None => ()
    }
    summaries.push(SessionSummary::{
      id: sd.session_id,
      name: sd.name,
      working_dir: sd.working_dir,
      status: sd.last_status,
      created_at: sd.created_at,
      updated_at: sd.created_at,
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
      model_id: sd.model_name,
      card_model: sd.model_name,
      channel_info: sd.channel_info,
      error_code: sd.error_code,
      top_up_url: sd.top_up_url,
      raw_message: sd.raw_message,
    })
  }
  let total = summaries.length()
  let has_more = total > limit
  // Apply limit (take first `limit` items)
  let paged = if total > limit {
    summaries[0:limit].to_owned()
  } else {
    summaries
  }
  // Real cron task count from the schedule store (no updated_at is tracked
  // per schedule, so latest_cron_updated_at stays None).
  ensure_schedules_loaded()
  let cron_count = schedule_state.val.scheduler.list_schedules().length()
  let paged_json : Array[Json] = []
  for s in paged {
    paged_json.push(ToJson::to_json(s))
  }
  @core.HttpResponse::ok().json_value(
    Json::object({
      "sessions": ToJson::to_json(paged_json),
      "has_more": ToJson::to_json(has_more),
      "cron_count": ToJson::to_json(cron_count),
      "latest_cron_updated_at": Json::null(),
    }),
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
  // Parse agent_profile from request (web-replication-05).
  let agent_profile : String = match j {
    Object(obj) =>
      match obj.get("agent_profile") {
        Some(String(s)) if !s.is_empty() => s
        _ => "general"
      }
    _ => "general"
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
  // Persist an initial snapshot so the session is immediately visible in
  // GET /api/sessions and WS session_list (both read from disk).
  // IO failure only degrades to the previous in-memory-only behavior.
  @agent.save_session(data) catch {
    _ => ()
  }
  // Include agent_profile and updated_at in the response
  // (web-replication-05; updated_at mirrors created_at for now).
  match ToJson::to_json(data) {
    Object(o) => {
      o["agent_profile"] = ToJson::to_json(agent_profile)
      o["updated_at"] = data.created_at.to_json()
      @core.HttpResponse::created().json_value(Json::object(o))
    }
    other => @core.HttpResponse::created().json_value(other)
  }
}

///|
/// GET /api/sessions/:id
fn handle_get_session(
  server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let id = match event.param("id") {
    Some(p) => p.to_owned()
    None =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": "Missing parameter: id".to_json() }),
      )
  }
  let session_opt = @agent.load_session(id)
  match session_opt {
    Some(data) =>
      @core.HttpResponse::ok().json_value(
        Json::object({ "session": ToJson::to_json(data) }),
      )
    None =>
      // A freshly created session lives only in memory until its first
      // run persists it; serve that instead of a 404 so the frontend
      // history load does not error right after session creation.
      match server_ref.val.active_agents.get(id) {
        Some(agent) =>
          @core.HttpResponse::ok().json_value(
            Json::object({ "session": agent.to_session_data().to_json() }),
          )
        None =>
          @core.HttpResponse::not_found().json_value(
            Json::object({ "error": "Session not found".to_json() }),
          )
      }
  }
}

///|
/// DELETE /api/sessions/:id
fn handle_delete_session(
  server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let id = match event.param("id") {
    Some(p) => p.to_owned()
    None =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": "Missing parameter: id".to_json() }),
      )
  }
  @agent.delete_session(id)
  let _ = server_ref.val.active_agents.remove(id)
  // Broadcast session_deleted via WS so the sidebar updates in real time.
  let hub = server_ref.val.hub
  hub.broadcast_session(id, @protocol.build_session_deleted_event(id))
  @core.HttpResponse::no_content()
}

///|
/// POST /api/sessions/:id/restore
fn handle_restore_session(
  server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let id = match event.param("id") {
    Some(p) => p.to_owned()
    None =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": "Missing parameter: id".to_json() }),
      )
  }
  let session_opt = @agent.load_session(id)
  match session_opt {
    Some(data) => {
      let agent = server_ref.val.get_or_create_agent(id)
      agent.restore_from_session(data)
      let session_data = agent.to_session_data()
      // Broadcast session_restored via WS so the sidebar updates in real time.
      let hub = server_ref.val.hub
      hub.broadcast_session(
        id,
        @protocol.build_session_restored_event(
          id,
          ToJson::to_json(session_data),
        ),
      )
      @core.HttpResponse::ok().json_value(ToJson::to_json(session_data))
    }
    None =>
      @core.HttpResponse::not_found().json_value(
        Json::object({ "error": "Session not found".to_json() }),
      )
  }
}

///|

///|
/// GET /api/sessions/:id/status
fn handle_get_status(
  server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let id = match event.param("id") {
    Some(p) => p.to_owned()
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
      @core.HttpResponse::ok().json_value(ToJson::to_json(response))
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
          @core.HttpResponse::ok().json_value(ToJson::to_json(response))
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
    Some(p) => p.to_owned()
    None =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": "Missing parameter: id".to_json() }),
      )
  }
  server_ref.val.cancelled[id] = true
  let response = CancelResponse::{ cancelled: true }
  @core.HttpResponse::ok().json_value(ToJson::to_json(response))
}

///|

///|
/// GET /api/sessions/:id/cost
fn handle_get_cost(
  server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let id = match event.param("id") {
    Some(p) => p.to_owned()
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
      @core.HttpResponse::ok().json_value(ToJson::to_json(response))
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
          @core.HttpResponse::ok().json_value(ToJson::to_json(response))
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
    Some(p) => p.to_owned()
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
  @core.HttpResponse::ok().json_value(ToJson::to_json(response))
}

// ── Config Handlers ─────────────────────────────────────────────

///|
/// Kinds managed via the dedicated media/OCR config UI. The original
/// `api_get_config` rejects these from the chat-model card list.
let config_media_managed_kinds : Array[String] = [
  "image", "video", "audio", "stt", "video_understanding", "ocr",
]

///|
/// Whether a model entry is managed via the media/OCR config UI rather
/// than the chat-model card list (orig `api_get_config` parity).
fn config_model_is_media_managed(m : @config.ModelConfig) -> Bool {
  fn tagged(t : String?) -> Bool {
    match t {
      Some(v) => config_media_managed_kinds.contains(v)
      None => false
    }
  }

  tagged(m.media_type) || tagged(m.type_)
}

///|
/// Capability summary for the model dropdown's footer, mirroring Ruby
/// `media_capabilities_payload`: `vision` follows the OCR sidecar state
/// (`primary` needs vision-capability detection MoonBit lacks -> false),
/// the media kinds report configured + model.
fn media_capabilities_json(cfg : @config.AgentConfig) -> Json {
  let caps : Map[String, Json] = Map([])
  let ocr = cfg.find_model_by_type("ocr")
  caps["vision"] = Json::object({
    "configured": (ocr is Some(_)).to_json(),
    "primary": false.to_json(),
    "model": config_media_opt_str(ocr.map(fn(m) { m.model })),
  })
  for kind in ["image", "video", "audio", "stt", "video_understanding"] {
    let entry = cfg.find_model_by_type(kind)
    caps[kind] = Json::object({
      "configured": (entry is Some(_)).to_json(),
      "model": config_media_opt_str(entry.map(fn(m) { m.model })),
    })
  }
  Json::object(caps)
}

///|
/// GET /api/config
/// Mirrors Ruby `api_get_config`: models carry their raw-list `index` and
/// the response adds `current_id` / `current_index` / `media_capabilities`.
/// Pre-existing keys (permission_mode, max_tokens, verbose,
/// current_model_id) are kept for the PUT round-trip and other clients.
fn handle_get_config(
  server_ref : Ref[WebServer],
  _event : @crescent.Event,
) -> @core.HttpResponse {
  let cfg = server_ref.val.config
  let models_json : Array[Json] = []
  for i = 0; i < cfg.models.length(); i = i + 1 {
    let m = cfg.models[i]
    // Media/OCR entries are managed via the dedicated media-config UI,
    // not the chat-model card list (orig `api_get_config` parity). The
    // index still refers to the position in the raw models array.
    if config_model_is_media_managed(m) {
      continue
    }
    match model_to_web_json(m) {
      Object(o) => {
        o["index"] = i.to_json()
        models_json.push(Json::object(o))
      }
      _ => ()
    }
  }
  let mut current_index = 0
  let mut current_id : Json = Json::null()
  match cfg.current_model() {
    Some(cur) => {
      current_id = cur.id.to_json()
      for i = 0; i < cfg.models.length(); i = i + 1 {
        if cfg.models[i].id == cur.id {
          current_index = i
          break
        }
      }
    }
    None => ()
  }
  @core.HttpResponse::ok().json_value(
    Json::object({
      "models": models_json.to_json(),
      "current_index": current_index.to_json(),
      "current_id": current_id,
      "media_capabilities": media_capabilities_json(cfg),
      "permission_mode": permission_mode_str(cfg.permission_mode).to_json(),
      "max_tokens": cfg.max_tokens.to_json(),
      "verbose": cfg.verbose.to_json(),
      "current_model_id": cfg.current_model_id.to_json(),
    }),
  )
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
  @core.HttpResponse::ok().json_value(ToJson::to_json(response))
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
  @core.HttpResponse::ok().json_value(ToJson::to_json(response))
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
  @core.HttpResponse::ok().json_value(ToJson::to_json(response))
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
  @core.HttpResponse::ok().json_value(ToJson::to_json(response))
}

// ── Info Handler ────────────────────────────────────────────────

///|
/// GET /api/info
fn handle_info(
  server_ref : Ref[WebServer],
  _event : @crescent.Event,
) -> @core.HttpResponse {
  let s = server_ref.val
  let uptime = @env.now().reinterpret_as_int64() - s.start_time
  let response = InfoResponse::{
    version: "0.1.0",
    name: "MBOpenClacky",
    uptime_seconds: uptime,
    active_sessions: s.active_agents.length(),
  }
  @core.HttpResponse::ok().json_value(ToJson::to_json(response))
}
// Legacy /ws/sessions/:id handler removed (web-parity-05).
// New /ws single-endpoint protocol in handlers_ws.mbt.
