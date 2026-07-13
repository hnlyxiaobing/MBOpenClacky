/// @deprecated This standalone Router is kept for unit-test coverage only.
/// The live server uses crescent's built-in routing registered in server.mbt.
/// Do not add new routes here; add them to the crescent App in WebServer::start.

///| REST API Router with path matching and parameter extraction.

// ── Core Types ────────────────────────────────────────────────────

///|
pub(all) enum HttpMethod {
  GET
  POST
  PUT
  DELETE
} derive(Eq, Debug)

///|
pub(all) struct HttpRequest {
  http_method : HttpMethod
  path : String
  params : Array[(String, String)]
  body : String
  headers : Array[(String, String)]
}

///|
pub(all) struct HttpResponse {
  status : Int
  body : String
  content_type : String
  headers : Array[(String, String)]
}

///|
pub(all) struct Route {
  http_method : HttpMethod
  path : String
  handler_name : String
}

///|
pub(all) struct Router {
  routes : Array[Route]
}

// ── HttpRequest helpers ───────────────────────────────────────────

///|
pub fn HttpRequest::new(
  http_method : HttpMethod,
  path : String,
  body? : String = "",
  headers? : Array[(String, String)] = [],
) -> HttpRequest {
  { http_method, path, params: [], body, headers }
}

///|
/// Get a parameter value by name from the extracted params.
pub fn HttpRequest::get_param(self : HttpRequest, name : String) -> String? {
  for pair in self.params {
    if pair.0 == name {
      return Some(pair.1)
    }
  }
  None
}

///|
/// Get a header value by name (case-insensitive).
pub fn HttpRequest::get_header(self : HttpRequest, name : String) -> String? {
  let lower_name = name.to_lower()
  for pair in self.headers {
    if pair.0.to_lower() == lower_name {
      return Some(pair.1)
    }
  }
  None
}

// ── HttpResponse helpers ──────────────────────────────────────────

///|
pub fn HttpResponse::ok(body : String) -> HttpResponse {
  { status: 200, body, content_type: "application/json", headers: [] }
}

///|
pub fn HttpResponse::created(body : String) -> HttpResponse {
  { status: 201, body, content_type: "application/json", headers: [] }
}

///|
pub fn HttpResponse::not_found(message : String) -> HttpResponse {
  let body = "{\"error\":\"\{message}\"}"
  { status: 404, body, content_type: "application/json", headers: [] }
}

///|
pub fn HttpResponse::bad_request(message : String) -> HttpResponse {
  let body = "{\"error\":\"\{message}\"}"
  { status: 400, body, content_type: "application/json", headers: [] }
}

///|
pub fn HttpResponse::no_content() -> HttpResponse {
  { status: 204, body: "", content_type: "application/json", headers: [] }
}

///|
pub fn HttpResponse::json(data : String) -> HttpResponse {
  { status: 200, body: data, content_type: "application/json", headers: [] }
}

///|
pub fn HttpResponse::html(data : String) -> HttpResponse {
  { status: 200, body: data, content_type: "text/html", headers: [] }
}

///|
pub fn HttpResponse::with_content_type(
  self : HttpResponse,
  ct : String,
) -> HttpResponse {
  { ..self, content_type: ct }
}

///|
pub fn HttpResponse::with_status(self : HttpResponse, s : Int) -> HttpResponse {
  { ..self, status: s }
}

// ── Router ────────────────────────────────────────────────────────

///|
pub fn Router::new() -> Router {
  { routes: [] }
}

///|
pub fn Router::add_route(
  self : Router,
  http_method : HttpMethod,
  path : String,
  handler_name : String,
) -> Router {
  self.routes.push({ http_method, path, handler_name })
  self
}

///|
/// Match a route given method + path. Returns the matched Route with
/// extracted parameters set in the request, or an error message.
pub fn Router::match_route(
  self : Router,
  http_method : HttpMethod,
  path : String,
) -> Result[(Route, Array[(String, String)]), String] {
  for route in self.routes {
    if route.http_method == http_method {
      match match_path_pattern(route.path, path) {
        Some(params) => return Ok((route, params))
        None => continue
      }
    }
  }
  Err("No route found for \{http_method.to_repr()} \{path}")
}

///|
/// Match a URL path against a pattern with :param segments.
/// Returns extracted parameters on success.
fn match_path_pattern(
  pattern : String,
  path : String,
) -> Array[(String, String)]? {
  let pattern_parts = split_path(pattern)
  let path_parts = split_path(path)
  if pattern_parts.length() != path_parts.length() {
    return None
  }
  let params : Array[(String, String)] = []
  for i = 0; i < pattern_parts.length(); i = i + 1 {
    let pp = pattern_parts[i]
    let up = path_parts[i]
    if pp.length() > 0 && pp[0] == ':' {
      // Parameter segment
      let param_name = pp[1:].to_owned()
      params.push((param_name, up))
    } else if pp != up {
      return None
    }
  }
  Some(params)
}

///|
/// Split a path by '/' and filter empty segments.
fn split_path(path : String) -> Array[String] {
  let parts : Array[String] = []
  let buf = StringBuilder::new()
  for ch in path {
    if ch == '/' {
      if buf.to_string().length() > 0 {
        parts.push(buf.to_string())
        buf.reset()
      }
    } else {
      buf.write_char(ch)
    }
  }
  if buf.to_string().length() > 0 {
    parts.push(buf.to_string())
  }
  parts
}

// ── Route Registration ────────────────────────────────────────────

///|
/// Register all REST API routes (68 endpoints).
pub fn register_all_routes(router : Router) -> Router {
  // MCP endpoints
  let r = router
    .add_route(GET, "/api/mcp/servers", "handle_mcp_list_servers")
    .add_route(POST, "/api/mcp/servers", "handle_mcp_register_server")
    .add_route(DELETE, "/api/mcp/servers/:id", "handle_mcp_remove_server")
    .add_route(GET, "/api/mcp/tools", "handle_mcp_list_tools")
    .add_route(POST, "/api/mcp/tools/:name/execute", "handle_mcp_execute_tool")
  // Channel endpoints
  let r = r
    .add_route(GET, "/api/channels", "handle_channels_list")
    .add_route(POST, "/api/channels", "handle_channels_create")
    .add_route(PUT, "/api/channels/:id", "handle_channels_update")
    .add_route(DELETE, "/api/channels/:id", "handle_channels_delete")
    .add_route(POST, "/api/channels/:id/test", "handle_channels_test")
    .add_route(GET, "/api/channels/:id/status", "handle_channels_status")
  // Schedule endpoints
  let r = r
    .add_route(GET, "/api/schedules", "handle_schedules_list")
    .add_route(POST, "/api/schedules", "handle_schedules_create")
    .add_route(PUT, "/api/schedules/:id", "handle_schedules_update")
    .add_route(DELETE, "/api/schedules/:id", "handle_schedules_delete")
    .add_route(POST, "/api/schedules/:id/trigger", "handle_schedules_trigger")
    .add_route(GET, "/api/schedules/:id/history", "handle_schedules_history")
  // Backup endpoints
  let r = r
    .add_route(GET, "/api/backups", "handle_backups_list")
    .add_route(POST, "/api/backups", "handle_backups_create")
    .add_route(POST, "/api/backups/:id/restore", "handle_backups_restore")
    .add_route(DELETE, "/api/backups/:id", "handle_backups_delete")
  // Billing endpoints
  let r = r
    .add_route(GET, "/api/billing/status", "handle_billing_status")
    .add_route(POST, "/api/billing/activate", "handle_billing_activate")
    .add_route(GET, "/api/billing/usage", "handle_billing_usage")
  // Skills endpoints
  let r = r
    .add_route(GET, "/api/skills", "handle_skills_list")
    .add_route(POST, "/api/skills", "handle_skills_create")
    .add_route(PUT, "/api/skills/:name", "handle_skills_update")
    .add_route(DELETE, "/api/skills/:name", "handle_skills_delete")
    .add_route(POST, "/api/skills/:name/evolve", "handle_skills_evolve")
    .add_route(
      GET,
      "/api/skills/evolution/history",
      "handle_skills_evolution_history",
    )
  // Browser endpoints
  let r = r
    .add_route(GET, "/api/browser/status", "handle_browser_status")
    .add_route(POST, "/api/browser/start", "handle_browser_start")
    .add_route(POST, "/api/browser/stop", "handle_browser_stop")
    .add_route(POST, "/api/browser/navigate", "handle_browser_navigate")
    .add_route(GET, "/api/browser/screenshot", "handle_browser_screenshot")
  // Trash endpoints
  let r = r
    .add_route(GET, "/api/trash", "handle_trash_list")
    .add_route(GET, "/api/trash/stats", "handle_trash_stats")
    .add_route(POST, "/api/trash/restore-batch", "handle_trash_restore_batch")
    .add_route(POST, "/api/trash/:id/restore", "handle_trash_restore")
    .add_route(DELETE, "/api/trash/:id", "handle_trash_delete")
    .add_route(DELETE, "/api/trash", "handle_trash_empty")
  r
}
