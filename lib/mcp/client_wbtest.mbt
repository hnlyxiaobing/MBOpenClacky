///|
/// McpClient whitebox tests.
test "McpClient from_spec stdio" {
  let spec = McpServerSpec::stdio(
    "test-server",
    "node",
    args=Some(["server.js"]),
  )
  let client = McpClient::from_spec(spec)
  @debug.assert_eq(client.name, "test-server")
  assert_true(client.tools.length() == 0)
  assert_true(client.server_info is None)
  assert_true(client.started_at is None)
  assert_true(client.last_used_at is None)
  @debug.assert_eq(client.next_id, 1)
}

///|
test "McpClient from_spec http" {
  let spec = McpServerSpec::http("api-server", "http://localhost:3000")
  let client = McpClient::from_spec(spec)
  @debug.assert_eq(client.name, "api-server")
  assert_true(client.tools.length() == 0)
  @debug.assert_eq(client.next_id, 1)
}

///|
test "McpClient protocol_version and timeouts" {
  let spec = McpServerSpec::stdio("test", "echo")
  let client = McpClient::from_spec(spec)
  @debug.assert_eq(client.protocol_version(), "2024-11-05")
  @debug.assert_eq(client.default_timeout(), 30)
  @debug.assert_eq(client.init_timeout(), 60)
}

///|
test "McpClient send_request_with_response success" {
  let spec = McpServerSpec::stdio("test", "echo")
  let client = McpClient::from_spec(spec)
  let response = "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"value\":42}}"
  let result = client.send_request_with_response("test_method", None, response)
  match result {
    { "value": Number(n, ..), .. } => @debug.assert_eq(n.to_int(), 42)
    _ => assert_true(false)
  }
  @debug.assert_eq(client.next_id, 2)
}

///|
test "McpClient send_request_with_response error raises" {
  let spec = McpServerSpec::stdio("test", "echo")
  let client = McpClient::from_spec(spec)
  let error_response = "{\"jsonrpc\":\"2.0\",\"id\":1,\"error\":{\"code\":-32601,\"message\":\"Method not found\"}}"
  try {
    client.send_request_with_response("bad_method", None, error_response)
    |> ignore
    assert_true(false)
  } catch {
    _ => assert_true(true)
  }
}

///|
test "McpClient disconnect clears state" {
  let spec = McpServerSpec::stdio("test", "echo")
  let client = McpClient::from_spec(spec)
  client.server_info = Some({
    name: "srv",
    version: "1",
    capabilities: { tools: true, prompts: false, resources: false },
  })
  client.tools = [{ name: "t", description: "d", input_schema: Json::null() }]
  client.disconnect()
  assert_false(client.is_connected())
  assert_true(client.server_info is None)
  assert_true(client.tools.length() == 0)
}
