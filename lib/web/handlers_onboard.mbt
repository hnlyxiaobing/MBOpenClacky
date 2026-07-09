///| Onboarding REST API handlers.
/// Guides the user through initial setup: device authorization, session creation,
/// and SOUL.md skip option.

// ── Device Flow ───────────────────────────────────────────────────

///|
/// POST /api/onboard/device/start
/// Starts a device authorization flow. In the current implementation this returns
/// a deterministic, locally-generated device code pair; a future iteration can
/// integrate with the platform OAuth endpoint.
fn handle_onboard_device_start(
  _server_ref : Ref[WebServer],
  _event : @crescent.Event,
) -> @core.HttpResponse {
  let device_code = "DEV-" + @agent.generate_session_id()
  let user_code = @agent.generate_session_id()[:8].to_owned().to_upper()
  @core.HttpResponse::ok().json_value(
    Json::object({
      "ok": true.to_json(),
      "device_code": device_code.to_json(),
      "user_code": user_code.to_json(),
      "verification_uri": "https://mbopenclacky.example.com/activate".to_json(),
      "verification_uri_complete": ("https://mbopenclacky.example.com/activate?user_code=" +
      user_code).to_json(),
      "interval": (5).to_json(),
    }),
  )
}

///|
/// GET /api/onboard/device/poll?device_code=...
/// Polls the status of a device authorization request.
fn handle_onboard_device_poll(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let device_code = match event.req.get_query("device_code") {
    Some(code) if !code.is_empty() => code
    _ =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({
          "error": "Missing 'device_code' query parameter".to_json(),
        }),
      )
  }
  // Simulated approval heuristic: codes beginning with "DEV-APPROVED-" are approved.
  if device_code.has_prefix("DEV-APPROVED-") {
    @core.HttpResponse::ok().json_value(
      Json::object({
        "ok": true.to_json(),
        "status": "approved".to_json(),
        "default_model": "default".to_json(),
      }),
    )
  } else {
    @core.HttpResponse::ok().json_value(
      Json::object({ "ok": true.to_json(), "status": "pending".to_json() }),
    )
  }
}

// ── Onboarding Status & Simple Flow ───────────────────────────────

///|
fn onboard_state_path() -> String? {
  match @utils.config_dir() {
    Some(d) =>
      Some(
        @path.Path::join(@path.Path(d), @path.Path("onboard.json")).to_string(),
      )
    None => None
  }
}

///|
fn load_onboard_state() -> Json {
  match onboard_state_path() {
    Some(path) => {
      let content = @fs.read_file_to_string(path) catch {
        _ => return default_onboard_state()
      }
      if content.is_empty() {
        return default_onboard_state()
      }
      @json.parse(content) catch {
        _ => default_onboard_state()
      }
    }
    None => default_onboard_state()
  }
}

///|
fn default_onboard_state() -> Json {
  Json::object({
    "completed": false.to_json(),
    "step": (0).to_json(),
    "skipped": false.to_json(),
  })
}

///|
fn save_onboard_state(j : Json) -> Unit {
  match onboard_state_path() {
    Some(path) => {
      match @utils.config_dir() {
        Some(dir) => @utils.ensure_dir(dir)
        None => ()
      }
      @fs.write_string_to_file(path, j.stringify()) catch {
        _ => ()
      }
    }
    None => ()
  }
}

///|
/// GET /api/onboard/status
fn handle_onboard_status(
  _server_ref : Ref[WebServer],
  _event : @crescent.Event,
) -> @core.HttpResponse {
  let state = load_onboard_state()
  @core.HttpResponse::ok().json_value(state)
}

///|
/// POST /api/onboard/start
fn handle_onboard_start(
  _server_ref : Ref[WebServer],
  _event : @crescent.Event,
) -> @core.HttpResponse {
  let state = load_onboard_state()
  let new_state = Json::object({
    "completed": false.to_json(),
    "step": (1).to_json(),
    "skipped": json_get_bool(state, "skipped"),
  })
  save_onboard_state(new_state)
  @core.HttpResponse::ok().json_value(
    Json::object({
      "ok": true.to_json(),
      "step": (1).to_json(),
      "device_code": Json::null(),
    }),
  )
}

///|
/// POST /api/onboard/skip
fn handle_onboard_skip(
  _server_ref : Ref[WebServer],
  _event : @crescent.Event,
) -> @core.HttpResponse {
  let new_state = Json::object({
    "completed": true.to_json(),
    "step": (2).to_json(),
    "skipped": true.to_json(),
  })
  save_onboard_state(new_state)
  @core.HttpResponse::ok().json_value(Json::object({ "ok": true.to_json() }))
}

///|
fn json_get_bool(j : Json, key : String) -> Json {
  match j {
    Object(obj) =>
      match obj.get(key) {
        Some(v) => v
        _ => false.to_json()
      }
    _ => false.to_json()
  }
}

// ── Onboarding Completion ─────────────────────────────────────────

///|
/// POST /api/onboard/complete
/// Completes onboarding by creating a default session if none exists.
fn handle_onboard_complete(
  server_ref : Ref[WebServer],
  _event : @crescent.Event,
) -> @core.HttpResponse {
  // If an active session already exists, reuse it.
  for session_id, _ in server_ref.val.active_agents {
    return @core.HttpResponse::ok().json_value(
      Json::object({
        "ok": true.to_json(),
        "session_id": session_id.to_json(),
        "created": false.to_json(),
      }),
    )
  }
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
  let session_id = @agent.generate_session_id()
  let agent = @agent.Agent::new(
    session_id,
    "Onboarding Session",
    ".",
    client,
    server_ref.val.config,
  )
  server_ref.val.active_agents[session_id] = agent
  @core.HttpResponse::ok().json_value(
    Json::object({
      "ok": true.to_json(),
      "session_id": session_id.to_json(),
      "created": true.to_json(),
    }),
  )
}

// ── SOUL Skip ─────────────────────────────────────────────────────

///|
/// POST /api/onboard/skip-soul
/// Writes a minimal SOUL.md so the soul-setup phase is not re-triggered.
fn handle_onboard_skip_soul(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let j : Json = event.req.body() catch { _ => Json::object({}) }
  let lang = match j {
    Object(obj) =>
      match obj.get("lang") {
        Some(String(s)) => s
        _ => "en"
      }
    _ => "en"
  }
  let content = if lang == "zh" || lang == "zh-CN" || lang == "zh-TW" {
    "# SOUL\n\n你是 MBOpenClacky，一个乐于助人的 AI 助手。\n"
  } else {
    "# SOUL\n\nYou are MBOpenClacky, a helpful AI assistant.\n"
  }
  let config_dir = match @utils.config_dir() {
    Some(dir) => dir
    None =>
      return @core.HttpResponse::internal_server_error().json_value(
        Json::object({
          "error": "Unable to determine config directory".to_json(),
        }),
      )
  }
  let agents_dir = @path.Path::join(
    @path.Path(config_dir),
    @path.Path("agents"),
  ).to_string()
  let soul_path = @path.Path::join(
    @path.Path(agents_dir),
    @path.Path("SOUL.md"),
  ).to_string()
  if !@fs.path_exists(soul_path) {
    // Ensure nested directories exist (create_dir only creates one level).
    if !@fs.path_exists(config_dir) {
      @fs.create_dir(config_dir) catch {
        e =>
          return @core.HttpResponse::internal_server_error().json_value(
            Json::object({
              "error": "Failed to create config directory".to_json(),
              "detail": e.to_string().to_json(),
            }),
          )
      }
    }
    if !@fs.path_exists(agents_dir) {
      @fs.create_dir(agents_dir) catch {
        e =>
          return @core.HttpResponse::internal_server_error().json_value(
            Json::object({
              "error": "Failed to create agents directory".to_json(),
              "detail": e.to_string().to_json(),
            }),
          )
      }
    }
    @fs.write_string_to_file(soul_path, content) catch {
      e =>
        return @core.HttpResponse::internal_server_error().json_value(
          Json::object({
            "error": "Failed to write SOUL.md".to_json(),
            "detail": e.to_string().to_json(),
          }),
        )
    }
  }
  @core.HttpResponse::ok().json_value(
    Json::object({ "ok": true.to_json(), "path": soul_path.to_json() }),
  )
}
