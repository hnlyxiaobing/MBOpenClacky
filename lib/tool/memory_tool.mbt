///| MemoryTool: manage persistent memory entries within the agent context.

///|
/// The actual execution is intercepted and handled in the agent context
/// (lib/agent/tool_executor.mbt). This stub returns a placeholder message.
pub(all) struct MemoryTool {} derive(Eq, Debug)

///|
impl Tool for MemoryTool with fn name(_) -> String {
  "memory"
}

///|
impl Tool for MemoryTool with fn description(_) -> String {
  "Manage persistent memory entries - create, search, update, delete, or list memories"
}

///|
impl Tool for MemoryTool with fn parameters(_) -> Json {
  Json::object({
    "type": "object".to_json(),
    "properties": Json::object({
      "action": Json::object({
        "type": "string".to_json(),
        "description": "The action to perform: create, search, update, delete, or list".to_json(),
        "enum": [
          "create".to_json(),
          "search".to_json(),
          "update".to_json(),
          "delete".to_json(),
          "list".to_json(),
        ],
      }),
      "title": Json::object({
        "type": "string".to_json(),
        "description": "Title of the memory entry (for create/update)".to_json(),
      }),
      "content": Json::object({
        "type": "string".to_json(),
        "description": "Content of the memory entry (for create/update)".to_json(),
      }),
      "category": Json::object({
        "type": "string".to_json(),
        "description": "Category: user_preference, project_info, task_summary, expert_knowledge, or learned_skill".to_json(),
      }),
      "query": Json::object({
        "type": "string".to_json(),
        "description": "Search query string (for search action)".to_json(),
      }),
      "id": Json::object({
        "type": "string".to_json(),
        "description": "Memory entry ID (for update/delete)".to_json(),
      }),
    }),
    "required": ["action".to_json()],
  })
}

///|
impl Tool for MemoryTool with fn category(_) -> ToolCategory {
  Agent
}

///|
impl Tool for MemoryTool with fn execute(_, _args : Map[String, Json]) -> ToolResult {
  ToolResult::success("Memory operations must be handled by agent context")
}

///|
impl Tool for MemoryTool with fn format_call(_, args : Map[String, Json]) -> String {
  match args.get("action") {
    Some(String(action)) => "Memory(\{action})"
    _ => "Memory(?)"
  }
}

///|
impl Tool for MemoryTool with fn format_result(_, result : ToolResult) -> String {
  if result.is_error {
    result.content
  } else {
    "Memory operation completed (\{result.content.length()} chars)"
  }
}

///|
impl Tool for MemoryTool with fn to_function_definition(self) -> FunctionDefinition {
  FunctionDefinition::new(self.name(), self.description(), self.parameters())
}
