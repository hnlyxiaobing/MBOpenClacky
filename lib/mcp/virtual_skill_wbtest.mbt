///| VirtualSkill whitebox tests.

test "VirtualSkill from_mcp_server with tools" {
  let tools = [
    { name: "read_file", description: "Reads a file", input_schema: Json::null() },
    { name: "write_file", description: "Writes a file", input_schema: Json::null() },
  ]
  let skill = VirtualSkill::from_mcp_server("my-server", tools)
  assert_eq(skill.name, "mcp-my-server")
  assert_eq(skill.mcp_server_name, "my-server")
  assert_true(skill.fork_agent)
  assert_eq(skill.tool_count(), 2)
}

test "VirtualSkill from_mcp_server without tools" {
  let skill = VirtualSkill::from_mcp_server("empty", [])
  assert_eq(skill.tool_count(), 0)
  assert_true(skill.description.contains("(no tools discovered yet)"))
}

test "VirtualSkill has_tool" {
  let tools = [
    { name: "search", description: "Search the web", input_schema: Json::null() },
  ]
  let skill = VirtualSkill::from_mcp_server("web", tools)
  assert_true(skill.has_tool("search"))
  assert_false(skill.has_tool("nonexistent"))
}

test "VirtualSkill tool_count" {
  let tools = [
    { name: "a", description: "A", input_schema: Json::null() },
    { name: "b", description: "B", input_schema: Json::null() },
    { name: "c", description: "C", input_schema: Json::null() },
  ]
  let skill = VirtualSkill::from_mcp_server("multi", tools)
  assert_eq(skill.tool_count(), 3)
}

test "VirtualSkill build_tool_call_instruction found" {
  let tools = [
    { name: "grep", description: "Search files", input_schema: Json::null() },
  ]
  let skill = VirtualSkill::from_mcp_server("code", tools)
  let instruction = skill.build_tool_call_instruction("grep")
  assert_true(instruction.contains("grep"))
  assert_true(instruction.contains("Search files"))
  assert_false(instruction.contains("Tool not found"))
}

test "VirtualSkill build_tool_call_instruction not found" {
  let skill = VirtualSkill::from_mcp_server("empty", [])
  let instruction = skill.build_tool_call_instruction("missing")
  assert_true(instruction.contains("Tool not found"))
}
