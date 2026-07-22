///|
/// White-box tests for REST API router, handlers, and static server.

// ══════════════════════════════════════════════════════════════════
// Router Path Matching Tests
// ══════════════════════════════════════════════════════════════════

test "router: exact path match GET" {
  let router = @web.Router::new().add_route(
    @web.GET,
    "/api/skills",
    "handle_skills_list",
  )
  let result = router.match_route(@web.GET, "/api/skills")
  match result {
    Ok((route, params)) => {
      assert_eq(route.handler_name, "handle_skills_list")
      assert_eq(params.length(), 0)
    }
    Err(_) => panic()
  }
}

///|
test "router: path with parameter extraction" {
  let router = @web.Router::new().add_route(
    @web.DELETE,
    "/api/channels/:id",
    "handle_channels_delete",
  )
  let result = router.match_route(@web.DELETE, "/api/channels/ch-123")
  match result {
    Ok((route, params)) => {
      assert_eq(route.handler_name, "handle_channels_delete")
      assert_eq(params.length(), 1)
      assert_eq(params[0].0, "id")
      assert_eq(params[0].1, "ch-123")
    }
    Err(_) => panic()
  }
}

///|
test "router: multiple parameters in path" {
  let router = @web.Router::new().add_route(
    @web.POST,
    "/api/mcp/tools/:name/execute",
    "handle_mcp_execute_tool",
  )
  let result = router.match_route(
    @web.POST,
    "/api/mcp/tools/web_search/execute",
  )
  match result {
    Ok((route, params)) => {
      assert_eq(route.handler_name, "handle_mcp_execute_tool")
      assert_eq(params[0].0, "name")
      assert_eq(params[0].1, "web_search")
    }
    Err(_) => panic()
  }
}

///|
test "router: 404 no matching route" {
  let router = @web.Router::new().add_route(
    @web.GET,
    "/api/skills",
    "handle_skills_list",
  )
  let result = router.match_route(@web.GET, "/api/unknown")
  match result {
    Ok(_) => panic()
    Err(msg) => assert_true(msg.contains("No route found"))
  }
}

///|
test "router: method mismatch returns error" {
  let router = @web.Router::new().add_route(
    @web.GET,
    "/api/skills",
    "handle_skills_list",
  )
  let result = router.match_route(@web.POST, "/api/skills")
  match result {
    Ok(_) => panic()
    Err(msg) => assert_true(msg.contains("No route found"))
  }
}

///|
test "router: register_all_routes populates routes" {
  let router = @web.register_all_routes(@web.Router::new())
  // Should have many routes registered
  assert_true(router.routes.length() >= 35)
}

///|
test "router: path segment count mismatch" {
  let router = @web.Router::new().add_route(
    @web.GET,
    "/api/channels/:id",
    "handle_channels_status",
  )
  let result = router.match_route(@web.GET, "/api/channels/123/extra/path")
  match result {
    Ok(_) => panic()
    Err(_) => () // expected
  }
}

// ══════════════════════════════════════════════════════════════════
// HttpRequest / HttpResponse Helper Tests
// ══════════════════════════════════════════════════════════════════

///|
test "http_response: ok status 200" {
  let resp = @web.HttpResponse::ok("{\"data\":true}")
  assert_eq(resp.status, 200)
  assert_eq(resp.content_type, "application/json")
}

///|
test "http_response: created status 201" {
  let resp = @web.HttpResponse::created("{\"id\":\"new\"}")
  assert_eq(resp.status, 201)
}

///|
test "http_response: not_found status 404" {
  let resp = @web.HttpResponse::not_found("Item not found")
  assert_eq(resp.status, 404)
  assert_true(resp.body.contains("Item not found"))
}

///|
test "http_response: bad_request status 400" {
  let resp = @web.HttpResponse::bad_request("Invalid input")
  assert_eq(resp.status, 400)
  assert_true(resp.body.contains("Invalid input"))
}

///|
test "http_response: no_content status 204" {
  let resp = @web.HttpResponse::no_content()
  assert_eq(resp.status, 204)
  assert_eq(resp.body, "")
}

///|
test "http_response: json helper" {
  let resp = @web.HttpResponse::json("{\"key\":\"value\"}")
  assert_eq(resp.status, 200)
  assert_eq(resp.content_type, "application/json")
}

///|
test "http_response: with_content_type" {
  let resp = @web.HttpResponse::ok("data").with_content_type("text/plain")
  assert_eq(resp.content_type, "text/plain")
}

///|
test "http_request: get_param returns value" {
  let req : @web.HttpRequest = {
    http_method: @web.GET,
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
  let req : @web.HttpRequest = {
    http_method: @web.GET,
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
  let req = @web.HttpRequest::new(@web.GET, "/api/mcp/servers")
  let resp = @web.handle_mcp_list_servers(registry, req)
  assert_eq(resp.status, 200)
  assert_true(resp.body.contains("servers"))
}

///|
test "handler: mcp register server requires body" {
  let registry = @mcp.McpRegistry::new()
  let req = @web.HttpRequest::new(@web.POST, "/api/mcp/servers")
  let resp = @web.handle_mcp_register_server(registry, req)
  assert_eq(resp.status, 400)
}

///|
test "handler: mcp register server with body returns 201" {
  let registry = @mcp.McpRegistry::new()
  let req = @web.HttpRequest::new(
    @web.POST,
    "/api/mcp/servers",
    body="{\"name\":\"test\",\"command\":\"echo\"}",
  )
  let resp = @web.handle_mcp_register_server(registry, req)
  assert_eq(resp.status, 201)
}

///|
test "handler: channels list returns 200" {
  let req = @web.HttpRequest::new(@web.GET, "/api/channels")
  let resp = @web.handle_channels_list(req)
  assert_eq(resp.status, 200)
  assert_true(resp.body.contains("["))
}

///|
test "handler: channels delete requires id param" {
  let req : @web.HttpRequest = {
    http_method: @web.DELETE,
    path: "/api/channels/",
    params: [],
    body: "",
    headers: [],
  }
  let resp = @web.handle_channels_delete(req)
  assert_eq(resp.status, 400)
}

///|
test "handler: schedules list returns 200" {
  let req = @web.HttpRequest::new(@web.GET, "/api/schedules")
  let resp = @web.handle_schedules_list(req)
  assert_eq(resp.status, 200)
}

///|
test "handler: backup create returns 201" {
  let req = @web.HttpRequest::new(@web.POST, "/api/backups")
  let resp = @web.handle_backups_create(req)
  assert_eq(resp.status, 201)
}

///|
test "handler: billing status returns 200" {
  let req = @web.HttpRequest::new(@web.GET, "/api/billing/status")
  let resp = @web.handle_billing_status(req)
  assert_eq(resp.status, 200)
  assert_true(resp.body.contains("plan"))
}

///|
test "handler: skills list returns 200" {
  let req = @web.HttpRequest::new(@web.GET, "/api/skills")
  let resp = @web.handle_skills_list(req)
  assert_eq(resp.status, 200)
}

// Browser handler tests removed: handlers now require Ref[WebServer] + crescent.Event.
// Integration tests should be added via the browser_manager test suite.

///|
test "handler: trash list returns 200" {
  let req = @web.HttpRequest::new(@web.GET, "/api/trash")
  let resp = @web.handle_trash_list(req)
  assert_eq(resp.status, 200)
}

///|
test "handler: trash empty returns 200" {
  let req = @web.HttpRequest::new(@web.DELETE, "/api/trash")
  let resp = @web.handle_trash_empty(req)
  assert_eq(resp.status, 200)
  assert_true(resp.body.contains("emptied"))
}

// ══════════════════════════════════════════════════════════════════
// Static Server Tests
// ══════════════════════════════════════════════════════════════════

///|
test "static_server: mime type html" {
  assert_eq(@web.get_mime_type("index.html"), "text/html")
}

///|
test "static_server: mime type css" {
  assert_eq(@web.get_mime_type("style.css"), "text/css")
}

///|
test "static_server: mime type js" {
  assert_eq(@web.get_mime_type("app.js"), "application/javascript")
}

///|
test "static_server: mime type json" {
  assert_eq(@web.get_mime_type("data.json"), "application/json")
}

///|
test "static_server: mime type png" {
  assert_eq(@web.get_mime_type("logo.png"), "image/png")
}

///|
test "static_server: mime type svg" {
  assert_eq(@web.get_mime_type("icon.svg"), "image/svg+xml")
}

///|
test "static_server: mime type unknown fallback" {
  assert_eq(@web.get_mime_type("file.xyz"), "application/octet-stream")
}

///|
test "static_server: spa fallback for non-asset path" {
  let server = @web.StaticServer::new("./web")
  let resp = server.serve("/dashboard")
  assert_eq(resp.status, 200)
  assert_eq(resp.content_type, "text/html")
  assert_true(resp.body.contains("app"))
}

///|
test "static_server: serves known static asset" {
  let server = @web.StaticServer::new("./web")
  let resp = server.serve("/app.css")
  assert_eq(resp.status, 200)
  assert_eq(resp.content_type, "text/css")
}

///|
test "static_server: directory traversal blocked" {
  let server = @web.StaticServer::new("./web")
  let resp = server.serve("/../../../etc/passwd")
  assert_eq(resp.status, 400)
}

///|
test "static_server: root path serves index" {
  let server = @web.StaticServer::new("./web")
  let resp = server.serve("/")
  assert_eq(resp.status, 200)
  assert_eq(resp.content_type, "text/html")
}
