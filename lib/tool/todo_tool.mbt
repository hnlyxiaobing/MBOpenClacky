///| TodoTool: manage task items within the agent context.

///|
/// The actual execution is intercepted and handled in the agent context
/// (lib/agent/tool_executor.mbt). This stub returns a placeholder message.
pub(all) struct TodoTool {} derive(Eq, Debug)

///|
impl Tool for TodoTool with fn name(_) -> String {
  "todo_manager"
}

///|
impl Tool for TodoTool with fn description(_) -> String {
  "Manage task items - add, update status, list, remove, or set dependencies"
}

///|
impl Tool for TodoTool with fn parameters(_) -> Json {
  Json::object({
    "type": "object".to_json(),
    "properties": Json::object({
      "action": Json::object({
        "type": "string".to_json(),
        "description": "The action to perform: add, update, list, remove, or set_deps".to_json(),
        "enum": [
          "add".to_json(),
          "update".to_json(),
          "list".to_json(),
          "remove".to_json(),
          "set_deps".to_json(),
        ],
      }),
      "title": Json::object({
        "type": "string".to_json(),
        "description": "Task title (for add action)".to_json(),
      }),
      "description": Json::object({
        "type": "string".to_json(),
        "description": "Task description (for add action)".to_json(),
      }),
      "id": Json::object({
        "type": "string".to_json(),
        "description": "Task ID (for update/remove/set_deps actions)".to_json(),
      }),
      "status": Json::object({
        "type": "string".to_json(),
        "description": "New status: pending, in_progress, completed, cancelled, or failed (for update action)".to_json(),
      }),
      "deps": Json::object({
        "type": "array".to_json(),
        "description": "Array of task IDs this task depends on (for set_deps action)".to_json(),
        "items": Json::object({ "type": "string".to_json() }),
      }),
    }),
    "required": ["action".to_json()],
  })
}

///|
impl Tool for TodoTool with fn category(_) -> ToolCategory {
  Agent
}

///|
impl Tool for TodoTool with fn execute(_, _args : Map[String, Json]) -> ToolResult {
  ToolResult::success("Todo operations must be handled by agent context")
}

///|
impl Tool for TodoTool with fn format_call(_, args : Map[String, Json]) -> String {
  match args.get("action") {
    Some(String(action)) => "Todo(\{action})"
    _ => "Todo(?)"
  }
}

///|
impl Tool for TodoTool with fn format_result(_, result : ToolResult) -> String {
  if result.is_error {
    result.content
  } else {
    "Todo operation completed (\{result.content.length()} chars)"
  }
}

///|
impl Tool for TodoTool with fn to_function_definition(self) -> FunctionDefinition {
  FunctionDefinition::new(self.name(), self.description(), self.parameters())
}
