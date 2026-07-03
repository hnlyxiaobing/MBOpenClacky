///| VirtualSkill: wraps MCP server tools as agent-invocable skills.
/// See SkillProvider for file-system-based skill discovery.

///|
/// A virtual skill backed by MCP server tools.
/// Maps MCP tools to the agent's skill invocation system.
pub(all) struct VirtualSkill {
  name : String
  description : String
  mcp_server_name : String
  mcp_tools : Array[McpTool]
  fork_agent : Bool // always true for MCP skills
} derive(Eq, Debug, ToJson)

///|
/// Create a VirtualSkill from an MCP server's tools.
pub fn VirtualSkill::from_mcp_server(
  server_name : String,
  tools : Array[McpTool],
) -> VirtualSkill {
  let desc = if tools.length() > 0 {
    let tool_names : Array[String] = []
    for tool in tools {
      tool_names.push(tool.name)
    }
    "MCP server '" + server_name + "' providing tools: " + tool_names.join(", ")
  } else {
    "MCP server '" + server_name + "' (no tools discovered yet)"
  }
  {
    name: "mcp-" + server_name,
    description: desc,
    mcp_server_name: server_name,
    mcp_tools: tools,
    fork_agent: true,
  }
}

///|
/// Generate a system prompt section describing this virtual skill's tools.
pub fn VirtualSkill::to_system_prompt_section(self : VirtualSkill) -> String {
  let buf = StringBuilder::new()
  buf.write_string("## MCP Skill: ")
  buf.write_string(self.name)
  buf.write_string("\n\n")
  buf.write_string("Server: ")
  buf.write_string(self.mcp_server_name)
  buf.write_string("\n")
  buf.write_string("Description: ")
  buf.write_string(self.description)
  buf.write_string("\n\n")
  if self.mcp_tools.length() > 0 {
    buf.write_string("Available tools:\n")
    for tool in self.mcp_tools {
      buf.write_string("- **")
      buf.write_string(tool.name)
      buf.write_string("**: ")
      buf.write_string(tool.description)
      buf.write_string("\n")
      // Add input schema if not null
      match tool.input_schema {
        Null => ()
        schema => {
          buf.write_string("  Input schema: ")
          buf.write_string(schema.stringify())
          buf.write_string("\n")
        }
      }
    }
  } else {
    buf.write_string(
      "No tools available yet. Call tools_list to discover tools.\n",
    )
  }
  buf.to_string()
}

///|
/// Build a tool call instruction for a specific tool.
pub fn VirtualSkill::build_tool_call_instruction(
  self : VirtualSkill,
  tool_name : String,
) -> String {
  let buf = StringBuilder::new()
  buf.write_string("To call tool '")
  buf.write_string(tool_name)
  buf.write_string("' on MCP server '")
  buf.write_string(self.mcp_server_name)
  buf.write_string("':\n")
  // Find the tool
  let mut found = false
  for tool in self.mcp_tools {
    if tool.name == tool_name {
      found = true
      buf.write_string("Description: ")
      buf.write_string(tool.description)
      buf.write_string("\n")
      match tool.input_schema {
        Null => ()
        schema => {
          buf.write_string("Input schema: ")
          buf.write_string(schema.stringify())
          buf.write_string("\n")
        }
      }
      break
    }
  }
  if !found {
    buf.write_string("(Tool not found in this skill's tool list)\n")
  }
  buf.to_string()
}

///|
/// Get the number of tools in this virtual skill.
pub fn VirtualSkill::tool_count(self : VirtualSkill) -> Int {
  self.mcp_tools.length()
}

///|
/// Check if this virtual skill has a specific tool.
pub fn VirtualSkill::has_tool(self : VirtualSkill, tool_name : String) -> Bool {
  for tool in self.mcp_tools {
    if tool.name == tool_name {
      return true
    }
  }
  false
}

///|
/// Create a VirtualSkill from a SkillInfo discovered by SkillProvider.
/// See SkillProvider for file-system-based skill discovery.
pub fn VirtualSkill::from_skill_info(info : SkillInfo) -> VirtualSkill {
  {
    name: info.name,
    description: info.description,
    mcp_server_name: "skill-provider",
    mcp_tools: [],
    fork_agent: true,
  }
}
