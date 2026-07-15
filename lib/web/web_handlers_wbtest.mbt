///|
/// White-box tests for REST API router, handlers, and static server.

// ══════════════════════════════════════════════════════════════════
// Router Path Matching Tests
// ══════════════════════════════════════════════════════════════════

test "router: exact path match GET" {
  let router = Router::new().add_route(GET, "/api/skills", "handle_skills_list")
  let result = router.match_route(GET, "/api/skills")
  match result {
    Ok((route, params)) => {
      @debug.assert_eq(route.handler_name, "handle_skills_list")
      @debug.assert_eq(params.length(), 0)
    }
    Err(_) => panic()
  }
}

///|
test "router: path with parameter extraction" {
  let router = Router::new().add_route(
    DELETE,
    "/api/channels/:id",
    "handle_channels_delete",
  )
  let result = router.match_route(DELETE, "/api/channels/ch-123")
  match result {
    Ok((route, params)) => {
      @debug.assert_eq(route.handler_name, "handle_channels_delete")
      @debug.assert_eq(params.length(), 1)
      @debug.assert_eq(params[0].0, "id")
      @debug.assert_eq(params[0].1, "ch-123")
    }
    Err(_) => panic()
  }
}

///|
test "router: multiple parameters in path" {
  let router = Router::new().add_route(
    POST,
    "/api/mcp/tools/:name/execute",
    "handle_mcp_execute_tool",
  )
  let result = router.match_route(POST, "/api/mcp/tools/web_search/execute")
  match result {
    Ok((route, params)) => {
      @debug.assert_eq(route.handler_name, "handle_mcp_execute_tool")
      @debug.assert_eq(params[0].0, "name")
      @debug.assert_eq(params[0].1, "web_search")
    }
    Err(_) => panic()
  }
}

///|
test "router: 404 no matching route" {
  let router = Router::new().add_route(GET, "/api/skills", "handle_skills_list")
  let result = router.match_route(GET, "/api/unknown")
  match result {
    Ok(_) => panic()
    Err(msg) => assert_true(msg.contains("No route found"))
  }
}

///|
test "router: method mismatch returns error" {
  let router = Router::new().add_route(GET, "/api/skills", "handle_skills_list")
  let result = router.match_route(POST, "/api/skills")
  match result {
    Ok(_) => panic()
    Err(msg) => assert_true(msg.contains("No route found"))
  }
}

///|
test "router: register_all_routes populates routes" {
  let router = register_all_routes(Router::new())
  assert_true(router.routes.length() >= 35)
}

///|
test "router: path segment count mismatch" {
  let router = Router::new().add_route(
    GET,
    "/api/channels/:id",
    "handle_channels_status",
  )
  let result = router.match_route(GET, "/api/channels/123/extra/path")
  match result {
    Ok(_) => panic()
    Err(_) => ()
  }
}

// ══════════════════════════════════════════════════════════════════
// HttpRequest / HttpResponse Helper Tests
// ══════════════════════════════════════════════════════════════════

///|
test "http_response: ok status 200" {
  let resp = HttpResponse::ok("{\"data\":true}")
  @debug.assert_eq(resp.status, 200)
  @debug.assert_eq(resp.content_type, "application/json")
}

///|
test "http_response: created status 201" {
  let resp = HttpResponse::created("{\"id\":\"new\"}")
  @debug.assert_eq(resp.status, 201)
}

///|
test "http_response: not_found status 404" {
  let resp = HttpResponse::not_found("Item not found")
  @debug.assert_eq(resp.status, 404)
  assert_true(resp.body.contains("Item not found"))
}

///|
test "http_response: bad_request status 400" {
  let resp = HttpResponse::bad_request("Invalid input")
  @debug.assert_eq(resp.status, 400)
  assert_true(resp.body.contains("Invalid input"))
}

///|
test "http_response: no_content status 204" {
  let resp = HttpResponse::no_content()
  @debug.assert_eq(resp.status, 204)
  @debug.assert_eq(resp.body, "")
}

///|
test "http_response: json helper" {
  let resp = HttpResponse::json("{\"key\":\"value\"}")
  @debug.assert_eq(resp.status, 200)
  @debug.assert_eq(resp.content_type, "application/json")
}

///|
test "http_response: with_content_type" {
  let resp = HttpResponse::ok("data").with_content_type("text/plain")
  @debug.assert_eq(resp.content_type, "text/plain")
}

///|
test "http_request: get_param returns value" {
  let req : HttpRequest = {
    http_method: GET,
    path: "/api/channels/ch-1",
    params: [("id", "ch-1")],
    body: "",
    headers: [],
  }
  @debug.assert_eq(req.get_param("id"), Some("ch-1"))
  @debug.assert_eq(req.get_param("missing"), None)
}

///|
test "http_request: get_header case insensitive" {
  let req : HttpRequest = {
    http_method: GET,
    path: "/",
    params: [],
    body: "",
    headers: [
      ("Content-Type", "application/json"),
      ("Authorization", "Bearer token"),
    ],
  }
  @debug.assert_eq(req.get_header("content-type"), Some("application/json"))
  @debug.assert_eq(req.get_header("AUTHORIZATION"), Some("Bearer token"))
  @debug.assert_eq(req.get_header("X-Missing"), None)
}

// ══════════════════════════════════════════════════════════════════
// Handler Basic Response Tests
// ══════════════════════════════════════════════════════════════════

///|
test "handler: mcp list servers returns 200" {
  let registry = @mcp.McpRegistry::new()
  let req = HttpRequest::new(GET, "/api/mcp/servers")
  let resp = handle_mcp_list_servers(registry, req)
  @debug.assert_eq(resp.status, 200)
  assert_true(resp.body.contains("servers"))
}

///|
test "handler: mcp register server requires body" {
  let registry = @mcp.McpRegistry::new()
  let req = HttpRequest::new(POST, "/api/mcp/servers")
  let resp = handle_mcp_register_server(registry, req)
  @debug.assert_eq(resp.status, 400)
}

///|
test "handler: mcp register server with body returns 201" {
  let registry = @mcp.McpRegistry::new()
  let req = HttpRequest::new(
    POST,
    "/api/mcp/servers",
    body="{\"name\":\"test\",\"command\":\"echo hi\"}",
  )
  let resp = handle_mcp_register_server(registry, req)
  @debug.assert_eq(resp.status, 201)
}

///|
test "handler: channels list returns 200" {
  let req = HttpRequest::new(GET, "/api/channels")
  let resp = handle_channels_list(req)
  @debug.assert_eq(resp.status, 200)
  // The store may be empty in tests; assert a well-formed JSON array is returned.
  let trimmed = resp.body.trim()
  assert_true(trimmed.starts_with("["))
  assert_true(trimmed.ends_with("]"))
}

///|
test "handler: channels delete returns 204 for an existing channel" {
  // Create a channel first so the delete target exists, then delete it.
  let create_req = HttpRequest::new(
    POST,
    "/api/channels",
    body="{\"platform\":\"telegram\",\"name\":\"wbtest-ch\"}",
  )
  let create_resp = handle_channels_create(create_req)
  @debug.assert_eq(create_resp.status, 201)
  let created_id = match @json.parse(create_resp.body) {
    Object(obj) =>
      match obj.get("id") {
        Some(String(s)) => s
        _ => panic()
      }
    _ => panic()
  }
  let del_req : HttpRequest = {
    http_method: DELETE,
    path: "/api/channels/" + created_id,
    params: [("id", created_id)],
    body: "",
    headers: [],
  }
  let resp = handle_channels_delete(del_req)
  @debug.assert_eq(resp.status, 204)
}

///|
test "handler: schedules list returns 200" {
  let req = HttpRequest::new(GET, "/api/schedules")
  let resp = handle_schedules_list(req)
  @debug.assert_eq(resp.status, 200)
}

///|
test "handler: backup create returns 201" {
  let req = HttpRequest::new(POST, "/api/backups")
  let resp = handle_backups_create(req)
  @debug.assert_eq(resp.status, 201)
}

///|
test "handler: billing status returns 200" {
  let req = HttpRequest::new(GET, "/api/billing/status")
  let resp = handle_billing_status(req)
  @debug.assert_eq(resp.status, 200)
  // The status payload exposes activation/plan state, not a "license_type" key.
  assert_true(resp.body.contains("plan"))
}

///|
test "handler: skills list returns 200" {
  let req = HttpRequest::new(GET, "/api/skills")
  let resp = handle_skills_list(req)
  @debug.assert_eq(resp.status, 200)
}

// Browser handler tests removed: handlers now require Ref[WebServer] + crescent.Event.
// Integration tests should be added via the browser_manager test suite.

///|
test "handler: trash list returns 200" {
  let req = HttpRequest::new(GET, "/api/trash")
  let resp = handle_trash_list(req)
  @debug.assert_eq(resp.status, 200)
}

///|
test "handler: trash empty returns 200" {
  let req = HttpRequest::new(DELETE, "/api/trash")
  let resp = handle_trash_empty(req)
  @debug.assert_eq(resp.status, 200)
  assert_true(resp.body.contains("emptied"))
}

// ══════════════════════════════════════════════════════════════════
// Static Server Tests
// ══════════════════════════════════════════════════════════════════

///|
test "static_server: mime type html" {
  @debug.assert_eq(get_mime_type("index.html"), "text/html")
}

///|
test "static_server: mime type css" {
  @debug.assert_eq(get_mime_type("style.css"), "text/css")
}

///|
test "static_server: mime type js" {
  @debug.assert_eq(get_mime_type("app.js"), "application/javascript")
}

///|
test "static_server: mime type json" {
  @debug.assert_eq(get_mime_type("data.json"), "application/json")
}

///|
test "static_server: mime type png" {
  @debug.assert_eq(get_mime_type("logo.png"), "image/png")
}

///|
test "static_server: mime type svg" {
  @debug.assert_eq(get_mime_type("icon.svg"), "image/svg+xml")
}

///|
test "static_server: mime type unknown fallback" {
  @debug.assert_eq(get_mime_type("file.xyz"), "application/octet-stream")
}

///|
test "static_server: spa fallback for non-asset path" {
  let server = StaticServer::new("./web")
  let resp = server.serve("/dashboard")
  @debug.assert_eq(resp.status, 200)
  @debug.assert_eq(resp.content_type, "text/html")
  assert_true(resp.body.contains("app"))
}

///|
test "static_server: serves known static asset" {
  let server = StaticServer::new("./web")
  let resp = server.serve("/css/style.css")
  @debug.assert_eq(resp.status, 200)
  @debug.assert_eq(resp.content_type, "text/css")
}

///|
test "static_server: directory traversal blocked" {
  let server = StaticServer::new("./web")
  let resp = server.serve("/../../../etc/passwd")
  @debug.assert_eq(resp.status, 400)
}

///|
test "static_server: root path serves index" {
  let server = StaticServer::new("./web")
  let resp = server.serve("/")
  @debug.assert_eq(resp.status, 200)
  @debug.assert_eq(resp.content_type, "text/html")
}
