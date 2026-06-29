///| Browser automation REST API handlers.
///  Each handler receives a Ref[WebServer] for access to the BrowserManager
///  and a crescent Event for request/response handling.

// ── Browser Handlers ──────────────────────────────────────────────

///|
/// GET /api/browser/status — Get browser daemon status.
pub fn handle_browser_status(
  server_ref : Ref[WebServer],
  _event : @crescent.Event,
) -> @core.HttpResponse {
  let status = server_ref.val.browser_manager.status()
  @core.HttpResponse::ok().json_value(status.to_json())
}

///|
/// POST /api/browser/start — Start the browser daemon.
pub fn handle_browser_start(
  server_ref : Ref[WebServer],
  _event : @crescent.Event,
) -> @core.HttpResponse {
  match server_ref.val.browser_manager.start() {
    Ok(_) =>
      @core.HttpResponse::ok().json_value(
        Json::object({
          "status": "started".to_json(),
          "message": "Browser daemon started".to_json(),
        }),
      )
    Err(e) =>
      @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": e.to_json() }),
      )
  }
}

///|
/// POST /api/browser/stop — Stop the browser daemon.
pub fn handle_browser_stop(
  server_ref : Ref[WebServer],
  _event : @crescent.Event,
) -> @core.HttpResponse {
  match server_ref.val.browser_manager.stop() {
    Ok(_) =>
      @core.HttpResponse::ok().json_value(
        Json::object({
          "status": "stopped".to_json(),
          "message": "Browser daemon stopped".to_json(),
        }),
      )
    Err(e) =>
      @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": e.to_json() }),
      )
  }
}

///|
/// POST /api/browser/navigate — Navigate browser to a URL via MCP.
pub fn handle_browser_navigate(
  server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let body : Json = event.req.body() catch {
    _ =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": "Request body is required".to_json() }),
      )
  }
  match server_ref.val.browser_manager.mcp_call("navigate_page", body) {
    Ok(result) => @core.HttpResponse::ok().json_value(result)
    Err(e) =>
      @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": e.to_json() }),
      )
  }
}

///|
/// POST /api/browser/screenshot — Take a screenshot of the current page via MCP.
pub fn handle_browser_screenshot(
  server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let body : Json = event.req.body() catch { _ => Json::object({}) }
  match server_ref.val.browser_manager.mcp_call("take_screenshot", body) {
    Ok(result) => @core.HttpResponse::ok().json_value(result)
    Err(e) =>
      @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": e.to_json() }),
      )
  }
}

///|
/// POST /api/browser/configure — Update browser configuration (e.g. chrome version).
pub fn handle_browser_configure(
  server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let body : Json = event.req.body() catch {
    _ =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": "Request body is required".to_json() }),
      )
  }
  let chrome_version = match body {
    { "chrome_version": String(v), .. } => v
    _ =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({
          "error": "Missing or invalid 'chrome_version' field".to_json(),
        }),
      )
  }
  match server_ref.val.browser_manager.configure(chrome_version) {
    Ok(_) =>
      @core.HttpResponse::ok().json_value(
        Json::object({
          "status": "configured".to_json(),
          "chrome_version": chrome_version.to_json(),
        }),
      )
    Err(e) =>
      @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": e.to_json() }),
      )
  }
}

///|
/// POST /api/browser/reload — Reload the browser daemon (stop + reload config + start).
pub fn handle_browser_reload(
  server_ref : Ref[WebServer],
  _event : @crescent.Event,
) -> @core.HttpResponse {
  match server_ref.val.browser_manager.reload() {
    Ok(_) =>
      @core.HttpResponse::ok().json_value(
        Json::object({
          "status": "reloaded".to_json(),
          "message": "Browser daemon reloaded".to_json(),
        }),
      )
    Err(e) =>
      @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": e.to_json() }),
      )
  }
}

///|
/// POST /api/browser/toggle — Toggle browser enabled/disabled state.
pub fn handle_browser_toggle(
  server_ref : Ref[WebServer],
  _event : @crescent.Event,
) -> @core.HttpResponse {
  let new_state = server_ref.val.browser_manager.toggle()
  @core.HttpResponse::ok().json_value(
    Json::object({ "enabled": new_state.to_json() }),
  )
}

///|
/// POST /api/tool/browser — Proxy an arbitrary MCP tool call to the browser daemon.
/// Expected body: { "tool": "<tool_name>", "arguments": { ... } }
pub fn handle_browser_tool_call(
  server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let body : Json = event.req.body() catch {
    _ =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": "Request body is required".to_json() }),
      )
  }
  let tool_name = match body {
    { "tool": String(v), .. } => v
    _ =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": "Missing or invalid 'tool' field".to_json() }),
      )
  }
  let arguments = match body {
    { "arguments": args, .. } => args
    _ => Json::object({})
  }
  match server_ref.val.browser_manager.mcp_call(tool_name, arguments) {
    Ok(result) => @core.HttpResponse::ok().json_value(result)
    Err(e) =>
      @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": e.to_json() }),
      )
  }
}
