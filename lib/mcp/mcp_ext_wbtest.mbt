///| Extended MCP tests: registry management, client lookup, virtual skills.

// ── McpRegistry::new Tests ────────────────────────────────────────────────────

///|
test "ext_mcp_registry_new" {
  let reg = McpRegistry::new()
  assert_true(reg.config_path is None)
  assert_eq(reg.idle_timeout, 300)
}

///|
test "ext_mcp_registry_get_client_not_found" {
  let reg = McpRegistry::new()
  assert_true(reg.get_client("nonexistent") is None)
}

///|
test "ext_mcp_registry_remove_nonexistent" {
  let reg = McpRegistry::new()
  reg.remove_server("nonexistent")
  assert_true(reg.get_client("nonexistent") is None)
}

///|
test "ext_mcp_registry_load_from_file" {
  let reg = McpRegistry::load_from_file("/path/to/mcp.json")
  assert_true(reg.config_path is Some(_))
}

///|
test "ext_mcp_registry_load_from_file_stores_path" {
  let reg = McpRegistry::load_from_file("/custom/path.json")
  match reg.config_path {
    Some(p) => assert_eq(p, "/custom/path.json")
    None => assert_true(false)
  }
}

///|
test "ext_mcp_registry_load_default" {
  let reg = McpRegistry::load_default()
  assert_true(reg.get_client("any") is None)
}

///|
test "ext_mcp_registry_virtual_skills_empty" {
  let reg = McpRegistry::new()
  let skills = reg.virtual_skills()
  assert_eq(skills.length(), 0)
}

///|
test "ext_mcp_registry_idle_timeout" {
  let reg = McpRegistry::new()
  assert_eq(reg.idle_timeout, 300)
}

///|
test "ext_mcp_registry_remove_after_add" {
  let reg = McpRegistry::new()
  let spec : McpServerSpec = {
    name: "test-server",
    server_type: TransportType::Stdio,
    command: Some("echo"),
    url: None,
    args: Some([]),
    env: Some(Map([])),
    cwd: None,
    description: None,
    headers: None,
  }
  reg.add_server("test", spec)
  reg.remove_server("test")
  assert_true(reg.get_client("test") is None)
}

///|
test "ext_mcp_registry_multiple_registries" {
  let reg1 = McpRegistry::new()
  let reg2 = McpRegistry::new()
  assert_eq(reg1.idle_timeout, reg2.idle_timeout)
}

///|
test "ext_mcp_registry_load_from_file_empty_path" {
  let reg = McpRegistry::load_from_file("")
  match reg.config_path {
    Some(p) => assert_eq(p, "")
    None => assert_true(false)
  }
}

///|
test "ext_mcp_registry_shutdown_empty" {
  let reg = McpRegistry::new()
  reg.shutdown()
  assert_true(reg.get_client("any") is None)
}

///|
test "ext_mcp_registry_add_and_remove_multiple" {
  let reg = McpRegistry::new()
  let spec : McpServerSpec = {
    name: "s1",
    server_type: TransportType::Stdio,
    command: Some("echo"),
    url: None,
    args: Some([]),
    env: Some(Map([])),
    cwd: None,
    description: None,
    headers: None,
  }
  reg.add_server("s1", spec)
  reg.add_server("s2", spec)
  reg.add_server("s3", spec)
  reg.remove_server("s2")
  assert_true(reg.get_client("s2") is None)
}
