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
  @core.HttpResponse::ok().json_value(Json(status))
}

///|
/// POST /api/browser/start — Start the browser daemon.
pub async fn handle_browser_start(
  server_ref : Ref[WebServer],
  _event : @crescent.Event,
) -> @core.HttpResponse {
  match server_ref.val.browser_manager.start() {
    Ok(_) =>
      @core.HttpResponse::ok().json_value(
        Json::object({
          "status": Json("started"),
          "message": Json("Browser daemon started"),
        }),
      )
    Err(e) =>
      @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": Json(e) }),
      )
  }
}

///|
/// POST /api/browser/stop — Stop the browser daemon.
pub async fn handle_browser_stop(
  server_ref : Ref[WebServer],
  _event : @crescent.Event,
) -> @core.HttpResponse {
  match server_ref.val.browser_manager.stop() {
    Ok(_) =>
      @core.HttpResponse::ok().json_value(
        Json::object({
          "status": Json("stopped"),
          "message": Json("Browser daemon stopped"),
        }),
      )
    Err(e) =>
      @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": Json(e) }),
      )
  }
}

///|
/// POST /api/browser/navigate — Navigate browser to a URL via MCP.
pub async fn handle_browser_navigate(
  server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let body : Json = event.req.body() catch {
    _ =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": Json("Request body is required") }),
      )
  }
  match server_ref.val.browser_manager.mcp_call("navigate_page", body) {
    Ok(result) => @core.HttpResponse::ok().json_value(result)
    Err(e) =>
      @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": Json(e) }),
      )
  }
}

///|
/// POST /api/browser/screenshot — Take a screenshot of the current page via MCP.
pub async fn handle_browser_screenshot(
  server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let body : Json = event.req.body() catch { _ => Json::object(Map([])) }
  match server_ref.val.browser_manager.mcp_call("take_screenshot", body) {
    Ok(result) => @core.HttpResponse::ok().json_value(result)
    Err(e) =>
      @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": Json(e) }),
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
        Json::object({ "error": Json("Request body is required") }),
      )
  }
  let chrome_version = match body {
    { "chrome_version": String(v), .. } => v
    _ =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({
          "error": Json("Missing or invalid 'chrome_version' field"),
        }),
      )
  }
  match server_ref.val.browser_manager.configure(chrome_version) {
    Ok(_) =>
      @core.HttpResponse::ok().json_value(
        Json::object({
          "status": Json("configured"),
          "chrome_version": Json(chrome_version),
        }),
      )
    Err(e) =>
      @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": Json(e) }),
      )
  }
}

///|
/// POST /api/browser/reload — Reload the browser daemon (stop + reload config + start).
pub async fn handle_browser_reload(
  server_ref : Ref[WebServer],
  _event : @crescent.Event,
) -> @core.HttpResponse {
  match server_ref.val.browser_manager.reload() {
    Ok(_) =>
      @core.HttpResponse::ok().json_value(
        Json::object({
          "status": Json("reloaded"),
          "message": Json("Browser daemon reloaded"),
        }),
      )
    Err(e) =>
      @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": Json(e) }),
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
    Json::object({ "enabled": Json(new_state) }),
  )
}

///|
/// POST /api/tool/browser — Proxy an arbitrary MCP tool call to the browser daemon.
/// Expected body: { "tool": "<tool_name>", "arguments": { ... } }
pub async fn handle_browser_tool_call(
  server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let body : Json = event.req.body() catch {
    _ =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": Json("Request body is required") }),
      )
  }
  let tool_name = match body {
    { "tool": String(v), .. } => v
    _ =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": Json("Missing or invalid 'tool' field") }),
      )
  }
  let arguments = match body {
    { "arguments": args, .. } => args
    _ => Json::object(Map([]))
  }
  match server_ref.val.browser_manager.mcp_call(tool_name, arguments) {
    Ok(result) => @core.HttpResponse::ok().json_value(result)
    Err(e) =>
      @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": Json(e) }),
      )
  }
}
