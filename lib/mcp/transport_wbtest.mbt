///|
/// Transport layer whitebox tests.
test "StdioTransport lifecycle" {
  let spec = McpServerSpec::stdio("test", "node", args=Some(["server.js"]))
  let t = StdioTransport::new(spec)
  assert_false(t.alive())
  @debug.assert_eq(t.command, "node")
  @debug.assert_eq(t.args.length(), 1)
  t.start()
  assert_true(t.alive())
  t.stop()
  assert_false(t.alive())
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
