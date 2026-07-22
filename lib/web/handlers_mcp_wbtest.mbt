///| White-box tests for MCP REST API handlers (spec-06).
///  Tests all 8 spec endpoints + 2 legacy endpoints directly against
///  a fresh McpRegistry, verifying JSON response structure and status codes.

// ── Helpers ──────────────────────────────────────────────────────────

///|
fn mcp_parse(body : String) -> Json {
  @json.parse(body) catch {
    _ => Json::empty_object()
  }
}

///|
fn mcp_get_str(j : Json, key : String) -> String {
  match j {
    Object(m) =>
      match m.get(key) {
        Some(String(v)) => v
        _ => abort("expected string at key: " + key)
      }
    _ => abort("expected object")
  }
}

///|
fn mcp_get_bool(j : Json, key : String) -> Bool {
  match j {
    Object(m) =>
      match m.get(key) {
        Some(True) => true
        Some(False) => false
        _ => abort("expected bool at key: " + key)
      }
    _ => abort("expected object")
  }
}

///|
fn mcp_has_key(j : Json, key : String) -> Bool {
  match j {
    Object(m) => m.contains(key)
    _ => false
  }
}

///| Get a string value from a Map[String, Json] directly (for nested objects).
fn map_get_str(m : Map[String, Json], key : String) -> String {
  match m.get(key) {
    Some(String(v)) => v
    _ => abort("expected string at key: " + key)
  }
}

///| Get a bool value from a Map[String, Json] directly.
fn map_get_bool(m : Map[String, Json], key : String) -> Bool {
  match m.get(key) {
    Some(True) => true
    Some(False) => false
    _ => abort("expected bool at key: " + key)
  }
}

///| Build an HttpRequest with optional name param and body.
fn mcp_req(
  m : HttpMethod,
  path : String,
  name? : String = "",
  body? : String = "",
) -> HttpRequest {
  let params : Array[(String, String)] = if name != "" {
    [("name", name)]
  } else {
    []
  }
  { http_method: m, path, params, body, headers: [] }
}

// ── GET /api/mcp (list servers) ──────────────────────────────────────

///|
test "mcp_list_servers: empty registry returns empty servers array" {
  let reg = @mcp.McpRegistry::new()
  let resp = handle_mcp_list_servers(reg, mcp_req(GET, "/api/mcp"))
  @debug.assert_eq(resp.status, 200)
  let j = mcp_parse(resp.body)
  @debug.assert_eq(mcp_get_bool(j, "configured"), false)
  @debug.assert_eq(mcp_get_bool(j, "config_exists"), false)
  match j {
    Object(m) =>
      match m.get("servers") {
        Some(Array(arr)) => @debug.assert_eq(arr.length(), 0)
        _ => abort("expected servers array")
      }
    _ => abort("expected object")
  }
}

///|
test "mcp_list_servers: shows registered server after add" {
  let reg = @mcp.McpRegistry::new()
  reg.add_server("test-srv", @mcp.McpServerSpec::stdio("test-srv", "node"))
  let resp = handle_mcp_list_servers(reg, mcp_req(GET, "/api/mcp"))
  @debug.assert_eq(resp.status, 200)
  let j = mcp_parse(resp.body)
  @debug.assert_eq(mcp_get_bool(j, "configured"), true)
  match j {
    Object(m) =>
      match m.get("servers") {
        Some(Array(arr)) => {
          @debug.assert_eq(arr.length(), 1)
          match arr[0] {
            Object(srv) => {
              @debug.assert_eq(map_get_str(srv, "name"), "test-srv")
              @debug.assert_eq(map_get_str(srv, "type"), "stdio")
              @debug.assert_eq(map_get_bool(srv, "disabled"), false)
            }
            _ => abort("expected server object")
          }
        }
        _ => abort("expected servers array")
      }
    _ => abort("expected object")
  }
}

// ── POST /api/mcp (add server) ───────────────────────────────────────

///|
test "mcp_add_server: stdio server with valid body" {
  let reg = @mcp.McpRegistry::new()
  let resp = handle_mcp_add_server(
    reg,
    mcp_req(
      POST,
      "/api/mcp",
      body=
        "{\"name\":\"my-server\",\"command\":\"node\",\"args\":[\"server.js\"],\"description\":\"Test server\"}",
    ),
  )
  @debug.assert_eq(resp.status, 201)
  let j = mcp_parse(resp.body)
  @debug.assert_eq(mcp_get_str(j, "name"), "my-server")
  @debug.assert_eq(mcp_get_bool(j, "ok"), true)
  @debug.assert_eq(reg.spec_count(), 1)
}

///|
test "mcp_add_server: http server with url" {
  let reg = @mcp.McpRegistry::new()
  let resp = handle_mcp_add_server(
    reg,
    mcp_req(
      POST,
      "/api/mcp",
      body=
        "{\"name\":\"api-server\",\"transport\":\"http\",\"url\":\"http://localhost:3000\"}",
    ),
  )
  @debug.assert_eq(resp.status, 201)
  let j = mcp_parse(resp.body)
  @debug.assert_eq(mcp_get_str(j, "name"), "api-server")
  @debug.assert_eq(mcp_get_str(j, "type"), "http")
}

///|
test "mcp_add_server: missing name returns 400" {
  let reg = @mcp.McpRegistry::new()
  let resp = handle_mcp_add_server(
    reg,
    mcp_req(POST, "/api/mcp", body="{\"command\":\"node\"}"),
  )
  @debug.assert_eq(resp.status, 400)
}

///|
test "mcp_add_server: missing command for stdio returns 400" {
  let reg = @mcp.McpRegistry::new()
  let resp = handle_mcp_add_server(
    reg,
    mcp_req(POST, "/api/mcp", body="{\"name\":\"no-cmd\"}"),
  )
  @debug.assert_eq(resp.status, 400)
}

///|
test "mcp_add_server: empty body returns 400" {
  let reg = @mcp.McpRegistry::new()
  let resp = handle_mcp_add_server(reg, mcp_req(POST, "/api/mcp"))
  @debug.assert_eq(resp.status, 400)
}

// ── PATCH /api/mcp/:name/enabled (toggle) ───────────────────────────

///|
test "mcp_toggle_server: disable existing server" {
  let reg = @mcp.McpRegistry::new()
  reg.add_server("srv1", @mcp.McpServerSpec::stdio("srv1", "node"))
  let resp = handle_mcp_toggle_server(
    reg,
    mcp_req(
      PUT,
      "/api/mcp/srv1/enabled",
      name="srv1",
      body="{\"enabled\":false}",
    ),
  )
  @debug.assert_eq(resp.status, 200)
  let j = mcp_parse(resp.body)
  @debug.assert_eq(mcp_get_bool(j, "ok"), true)
  @debug.assert_eq(reg.is_enabled("srv1"), false)
}

///|
test "mcp_toggle_server: enable existing server" {
  let reg = @mcp.McpRegistry::new()
  reg.add_server("srv1", @mcp.McpServerSpec::stdio("srv1", "node"))
  reg.set_enabled("srv1", false)
  let resp = handle_mcp_toggle_server(
    reg,
    mcp_req(
      PUT,
      "/api/mcp/srv1/enabled",
      name="srv1",
      body="{\"enabled\":true}",
    ),
  )
  @debug.assert_eq(resp.status, 200)
  @debug.assert_eq(reg.is_enabled("srv1"), true)
}

///|
test "mcp_toggle_server: non-existent server returns 404" {
  let reg = @mcp.McpRegistry::new()
  let resp = handle_mcp_toggle_server(
    reg,
    mcp_req(
      PUT,
      "/api/mcp/ghost/enabled",
      name="ghost",
      body="{\"enabled\":true}",
    ),
  )
  @debug.assert_eq(resp.status, 404)
}

///|
test "mcp_toggle_server: missing enabled field returns 400" {
  let reg = @mcp.McpRegistry::new()
  reg.add_server("srv1", @mcp.McpServerSpec::stdio("srv1", "node"))
  let resp = handle_mcp_toggle_server(
    reg,
    mcp_req(PUT, "/api/mcp/srv1/enabled", name="srv1", body="{\"foo\":true}"),
  )
  @debug.assert_eq(resp.status, 400)
}

// ── DELETE /api/mcp/:name (remove) ───────────────────────────────────

///|
test "mcp_remove_server: existing server removed" {
  let reg = @mcp.McpRegistry::new()
  reg.add_server(
    "to-remove",
    @mcp.McpServerSpec::stdio("to-remove", "node"),
  )
  @debug.assert_eq(reg.spec_count(), 1)
  let resp = handle_mcp_remove_server(
    reg,
    mcp_req(DELETE, "/api/mcp/to-remove", name="to-remove"),
  )
  @debug.assert_eq(resp.status, 200)
  let j = mcp_parse(resp.body)
  @debug.assert_eq(mcp_get_bool(j, "ok"), true)
  @debug.assert_eq(reg.spec_count(), 0)
}

///|
test "mcp_remove_server: non-existent returns 404" {
  let reg = @mcp.McpRegistry::new()
  let resp = handle_mcp_remove_server(
    reg,
    mcp_req(DELETE, "/api/mcp/ghost", name="ghost"),
  )
  @debug.assert_eq(resp.status, 404)
}

// ── PUT /api/mcp/:name (update) ──────────────────────────────────────

///|
test "mcp_update_server: update stdio config" {
  let reg = @mcp.McpRegistry::new()
  reg.add_server("srv1", @mcp.McpServerSpec::stdio("srv1", "node"))
  let resp = handle_mcp_update_server(
    reg,
    mcp_req(
      PUT,
      "/api/mcp/srv1",
      name="srv1",
      body="{\"command\":\"python\",\"args\":[\"-m\",\"server\"]}",
    ),
  )
  @debug.assert_eq(resp.status, 200)
  let j = mcp_parse(resp.body)
  @debug.assert_eq(mcp_get_bool(j, "ok"), true)
  match reg.specs.get("srv1") {
    Some(spec) =>
      match spec.command {
        Some(cmd) => @debug.assert_eq(cmd, "python")
        None => abort("expected command to be updated")
      }
    None => abort("expected spec to exist")
  }
}

///|
test "mcp_update_server: non-existent returns 404" {
  let reg = @mcp.McpRegistry::new()
  let resp = handle_mcp_update_server(
    reg,
    mcp_req(PUT, "/api/mcp/ghost", name="ghost", body="{\"command\":\"node\"}"),
  )
  @debug.assert_eq(resp.status, 404)
}

///|
test "mcp_update_server: preserves enabled state" {
  let reg = @mcp.McpRegistry::new()
  reg.add_server("srv1", @mcp.McpServerSpec::stdio("srv1", "node"))
  reg.set_enabled("srv1", false)
  let _ = handle_mcp_update_server(
    reg,
    mcp_req(PUT, "/api/mcp/srv1", name="srv1", body="{\"command\":\"python\"}"),
  )
  @debug.assert_eq(reg.is_enabled("srv1"), false)
}

// ── POST /api/mcp/:name/probe (probe) ───────────────────────────────

///|
test "mcp_probe_server: non-existent returns 404" {
  let reg = @mcp.McpRegistry::new()
  let resp = handle_mcp_probe_server(
    reg,
    mcp_req(POST, "/api/mcp/ghost/probe", name="ghost"),
  )
  @debug.assert_eq(resp.status, 404)
}

///|
test "mcp_probe_server: existing server returns ok or not-connected" {
  let reg = @mcp.McpRegistry::new()
  reg.add_server(
    "srv1",
    @mcp.McpServerSpec::stdio("srv1", "nonexistent-command-xyz"),
  )
  let resp = handle_mcp_probe_server(
    reg,
    mcp_req(POST, "/api/mcp/srv1/probe", name="srv1"),
  )
  @debug.assert_eq(resp.status, 200)
  let j = mcp_parse(resp.body)
  match j {
    Object(m) =>
      match m.get("ok") {
        Some(True) => ()
        Some(False) => assert_true(mcp_has_key(j, "error"))
        _ => abort("expected ok field")
      }
    _ => abort("expected object")
  }
}

// ── GET /api/mcp/:name/tools (list tools) ───────────────────────────

///|
test "mcp_list_server_tools: non-existent returns 404" {
  let reg = @mcp.McpRegistry::new()
  let resp = handle_mcp_list_server_tools(
    reg,
    mcp_req(GET, "/api/mcp/ghost/tools", name="ghost"),
  )
  @debug.assert_eq(resp.status, 404)
}

///|
test "mcp_list_server_tools: existing server returns tools array" {
  let reg = @mcp.McpRegistry::new()
  reg.add_server("srv1", @mcp.McpServerSpec::stdio("srv1", "node"))
  let resp = handle_mcp_list_server_tools(
    reg,
    mcp_req(GET, "/api/mcp/srv1/tools", name="srv1"),
  )
  @debug.assert_eq(resp.status, 200)
  let j = mcp_parse(resp.body)
  @debug.assert_eq(mcp_get_str(j, "server"), "srv1")
  match j {
    Object(m) =>
      match m.get("tools") {
        Some(Array(_)) => ()
        _ => abort("expected tools array")
      }
    _ => abort("expected object")
  }
}

// ── POST /api/mcp/:name/call (call tool) ─────────────────────────────

///|
test "mcp_call_server_tool: non-existent server returns 404" {
  let reg = @mcp.McpRegistry::new()
  let resp = handle_mcp_call_server_tool(
    reg,
    mcp_req(
      POST,
      "/api/mcp/ghost/call",
      name="ghost",
      body="{\"tool_name\":\"search\",\"arguments\":{}}",
    ),
  )
  @debug.assert_eq(resp.status, 404)
}

///|
test "mcp_call_server_tool: missing tool_name returns 400" {
  let reg = @mcp.McpRegistry::new()
  reg.add_server("srv1", @mcp.McpServerSpec::stdio("srv1", "node"))
  let resp = handle_mcp_call_server_tool(
    reg,
    mcp_req(
      POST,
      "/api/mcp/srv1/call",
      name="srv1",
      body="{\"arguments\":{}}",
    ),
  )
  @debug.assert_eq(resp.status, 400)
}

///|
test "mcp_call_server_tool: empty body returns 400" {
  let reg = @mcp.McpRegistry::new()
  reg.add_server("srv1", @mcp.McpServerSpec::stdio("srv1", "node"))
  let resp = handle_mcp_call_server_tool(
    reg,
    mcp_req(POST, "/api/mcp/srv1/call", name="srv1"),
  )
  @debug.assert_eq(resp.status, 400)
}

// ── Legacy endpoints ──────────────────────────────────────────────────

///|
test "mcp_list_tools: lists tools across all servers" {
  let reg = @mcp.McpRegistry::new()
  reg.add_server("srv1", @mcp.McpServerSpec::stdio("srv1", "node"))
  let resp = handle_mcp_list_tools(reg, mcp_req(GET, "/api/mcp/tools"))
  @debug.assert_eq(resp.status, 200)
  let j = mcp_parse(resp.body)
  match j {
    Object(m) =>
      match m.get("tools") {
        Some(Array(_)) => ()
        _ => abort("expected tools array")
      }
    _ => abort("expected object")
  }
}

///|
test "mcp_execute_tool: tool not found returns 404" {
  let reg = @mcp.McpRegistry::new()
  let resp = handle_mcp_execute_tool(
    reg,
    mcp_req(
      POST,
      "/api/mcp/tools/ghost-tool/execute",
      name="ghost-tool",
      body="{\"arguments\":{}}",
    ),
  )
  @debug.assert_eq(resp.status, 404)
}

///|
test "mcp_execute_tool: empty body returns 400" {
  let reg = @mcp.McpRegistry::new()
  reg.add_server("srv1", @mcp.McpServerSpec::stdio("srv1", "node"))
  let resp = handle_mcp_execute_tool(
    reg,
    mcp_req(POST, "/api/mcp/tools/some-tool/execute", name="some-tool"),
  )
  @debug.assert_eq(resp.status, 400)
}
