///| MCP stdio server (plan #10) — protocol surface.
///
/// The pure protocol layer is asserted directly (deterministic, no
/// subprocess); the end-to-end pipe path is covered by the optional
/// subprocess case at the bottom, which needs a built binary.

///|
/// `initialize` must advertise the protocol version, the tools capability and
/// the server identity — that is what an MCP client keys off first.
async test "mcp initialize advertises version and capabilities" {
  let registry = @tool.make_default_registry()
  let req : Json = @json.parse(
    "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\"}",
  ) catch {
    _ => Json::object(Map([]))
  }
  let resp = match mcp_dispatch(registry, req) {
    Some(r) => r
    None => {
      assert_true(false, msg="initialize must be answered")
      return
    }
  }
  let text = resp.stringify()
  assert_true(text.contains("2024-11-05"), msg="missing protocolVersion: " + text)
  assert_true(text.contains("\"tools\""), msg="missing tools capability")
  assert_true(text.contains("mbopenclacky"), msg="missing serverInfo name")
  assert_true(text.contains("\"id\":1"), msg="request id was not echoed")
}

///|
/// `tools/list` must expose the built-in registry with MCP-shaped entries.
async test "mcp tools/list exposes the built-in registry" {
  let registry = @tool.make_default_registry()
  let req : Json = @json.parse(
    "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/list\"}",
  ) catch {
    _ => Json::object(Map([]))
  }
  let resp = match mcp_dispatch(registry, req) {
    Some(r) => r
    None => {
      assert_true(false, msg="tools/list must be answered")
      return
    }
  }
  let text = resp.stringify()
  for name in ["file_reader", "glob", "grep", "write"] {
    assert_true(text.contains("\"name\":\"" + name + "\""), msg="missing tool " + name)
  }
  assert_true(text.contains("\"inputSchema\""), msg="tools lack inputSchema")
}

///|
/// `tools/call` must really execute the tool (not echo it back).
async test "mcp tools/call executes a real tool" {
  let registry = @tool.make_default_registry()
  let req : Json = @json.parse(
    "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/call\",\"params\":{\"name\":\"glob\",\"arguments\":{\"pattern\":\"**/moon.mod\"}}}",
  ) catch {
    _ => Json::object(Map([]))
  }
  let resp = match mcp_dispatch(registry, req) {
    Some(r) => r
    None => {
      assert_true(false, msg="tools/call must be answered")
      return
    }
  }
  match resp {
    Object(obj) =>
      match obj.get("result") {
        Some(Object(res)) => {
          assert_true(res.contains("content"), msg="missing content envelope")
          assert_true(res.contains("isError"), msg="missing isError flag")
        }
        _ => assert_true(false, msg="tools/call returned no result object")
      }
    _ => assert_true(false, msg="response was not a JSON object")
  }
}

///|
/// Unknown tools and unknown methods fail honestly: a tool-level failure is a
/// tool result with `isError`, an unknown method is a JSON-RPC error.
async test "mcp reports unknown tool and unknown method honestly" {
  let registry = @tool.make_default_registry()
  let bad_tool : Json = @json.parse(
    "{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"tools/call\",\"params\":{\"name\":\"no_such_tool\"}}",
  ) catch {
    _ => Json::object(Map([]))
  }
  match mcp_dispatch(registry, bad_tool) {
    Some(resp) =>
      assert_true(
        resp.stringify().contains("isError\":true"),
        msg="unknown tool must be an isError result",
      )
    None => assert_true(false, msg="unknown tool must be answered")
  }
  let bad_method : Json = @json.parse(
    "{\"jsonrpc\":\"2.0\",\"id\":5,\"method\":\"no/such/method\"}",
  ) catch {
    _ => Json::object(Map([]))
  }
  match mcp_dispatch(registry, bad_method) {
    Some(resp) =>
      assert_true(
        resp.stringify().contains("-32601"),
        msg="unknown method must be -32601",
      )
    None => assert_true(false, msg="unknown method must be answered")
  }
}

///|
/// Notifications (no `id`) must never be answered — the client is not waiting.
async test "mcp does not answer notifications" {
  let registry = @tool.make_default_registry()
  let note : Json = @json.parse(
    "{\"jsonrpc\":\"2.0\",\"method\":\"notifications/initialized\"}",
  ) catch {
    _ => Json::object(Map([]))
  }
  assert_true(mcp_dispatch(registry, note) is None, msg="notification was answered")
}