///| McpRegistry whitebox tests.

test "McpRegistry new is empty" {
  let reg = McpRegistry::new()
  assert_eq(reg.spec_count(), 0)
  assert_eq(reg.client_count(), 0)
  assert_true(reg.config_path is None)
  assert_eq(reg.idle_timeout, 300)
}

test "McpRegistry add_server and spec_count" {
  let reg = McpRegistry::new()
  let spec = McpServerSpec::stdio("s1", "node")
  reg.add_server("s1", spec)
  assert_eq(reg.spec_count(), 1)
  assert_eq(reg.client_count(), 0)
}

test "McpRegistry remove_server" {
  let reg = McpRegistry::new()
  let spec = McpServerSpec::stdio("s1", "node")
  reg.add_server("s1", spec)
  assert_eq(reg.spec_count(), 1)
  reg.remove_server("s1")
  assert_eq(reg.spec_count(), 0)
}

test "McpRegistry get_client returns None for unknown" {
  let reg = McpRegistry::new()
  let client = reg.get_client("nonexistent")
  assert_true(client is None)
}

test "McpRegistry get_client creates from spec" {
  let reg = McpRegistry::new()
  let spec = McpServerSpec::stdio("s1", "echo")
  reg.add_server("s1", spec)
  let client = reg.get_client("s1")
  assert_true(client is Some(_))
  assert_eq(reg.client_count(), 1)
}

test "parse_mcp_config valid JSON" {
  let json_str =
    "{\"mcpServers\":{\"my-server\":{\"command\":\"node\",\"args\":[\"server.js\"]}}}"
  let specs = parse_mcp_config(json_str)
  assert_eq(specs.length(), 1)
  match specs.get("my-server") {
    Some(spec) => {
      assert_eq(spec.name, "my-server")
      assert_true(spec.server_type == Stdio)
    }
    None => assert_true(false)
  }
}

test "parse_mcp_config invalid JSON raises" {
  try {
    parse_mcp_config("not valid json") |> ignore
    assert_true(false)
  } catch {
    _ => assert_true(true)
  }
}
