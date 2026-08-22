///|
/// StdioTransport rejects an empty command synchronously (spec: start
/// validates before creating any pipes or processes).
async test "StdioTransport start rejects empty command" {
  let spec = McpServerSpec::stdio("test", "")
  let t = StdioTransport::new(spec)
  assert_false(t.alive())
  @debug.assert_eq(t.command, "")
  @debug.assert_eq(t.args.length(), 0)
  let started : Result[Unit, String] = t.start() catch {
    _ => Err("Transport start was cancelled")
  }
  match started {
    Ok(_) => assert_true(false)
    Err(e) => @debug.assert_eq(e, "stdio transport has no command configured")
  }
  assert_false(t.alive())
  // stop on a never-started transport must be a safe no-op
  t.stop()
  assert_false(t.alive())
}

///|
/// StdioTransport requires the global MCP task group before spawning so
/// the read loop has a scheduler to run on.
async test "StdioTransport start without task group errors" {
  let spec = McpServerSpec::stdio("test", "node", args=Some(["server.js"]))
  let t = StdioTransport::new(spec)
  @debug.assert_eq(t.command, "node")
  @debug.assert_eq(t.args.length(), 1)
  let saved = mcp_task_group.val
  clear_mcp_task_group()
  let started : Result[Unit, String] = t.start() catch {
    _ => Err("Transport start was cancelled")
  }
  match started {
    Ok(_) => assert_true(false)
    Err(e) => assert_true(e.contains("task group"))
  }
  assert_false(t.alive())
  match saved {
    Some(g) => set_mcp_task_group(g)
    None => ()
  }
}

///|
test "HttpTransport session_id and build_headers" {
  let spec = McpServerSpec::http(
    "api",
    "http://localhost:3000",
    headers=Some({ "Authorization": "Bearer tok" }),
  )
  let t = HttpTransport::new(spec)
  assert_true(t.get_session_id() is None)
  t.set_session_id("sess-123")
  @debug.assert_eq(t.get_session_id(), Some("sess-123"))
  let headers = t.build_headers()
  @debug.assert_eq(headers["Content-Type"], "application/json")
  @debug.assert_eq(headers["Mcp-Session-Id"], "sess-123")
  @debug.assert_eq(headers["Authorization"], "Bearer tok")
}

///|
test "build_jsonrpc_request ID format" {
  let req_str = build_jsonrpc_request(42, "tools/call", None)
  let json : Json = @json.parse(req_str) catch { _ => return }
  match json {
    { "jsonrpc": String(ver), "id": Number(id, ..), "method": String(m), .. } => {
      @debug.assert_eq(ver, "2.0")
      @debug.assert_eq(id.to_int(), 42)
      @debug.assert_eq(m, "tools/call")
    }
    _ => assert_true(false)
  }
}

///|
async test "HttpTransport start returns honest not-implemented error" {
  let spec = McpServerSpec::http("api", "http://localhost:9/mcp")
  let t = HttpTransport::new(spec)
  let started : Result[Unit, String] = t.start() catch {
    _ => Err("Transport start was cancelled")
  }
  match started {
    Ok(_) => assert_true(false)
    Err(e) => assert_true(e.contains("not implemented"))
  }
  assert_false(t.alive())
}
