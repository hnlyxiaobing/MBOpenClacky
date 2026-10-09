///| MemoryTool: manage persistent memory entries within the agent context.

///|
/// The actual execution is intercepted and handled in the agent context
/// (lib/agent/tool_executor.mbt). This stub returns a placeholder message.
pub(all) struct MemoryTool {} derive(Eq, Debug)

///|
pub extend MemoryTool with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend MemoryTool with Eq::{not_equal, equal}

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
    "type": Json("object"),
    "properties": Json::object({
      "action": Json::object({
        "type": Json("string"),
        "description": Json(
          "The action to perform: create, search, update, delete, or list",
        ),
        "enum": [
          Json("create"),
          Json("search"),
          Json("update"),
          Json("delete"),
          Json("list"),
        ],
      }),
      "title": Json::object({
        "type": Json("string"),
        "description": Json("Title of the memory entry (for create/update)"),
      }),
      "content": Json::object({
        "type": Json("string"),
        "description": Json("Content of the memory entry (for create/update)"),
      }),
      "category": Json::object({
        "type": Json("string"),
        "description": Json(
          "Category: user_preference, project_info, task_summary, expert_knowledge, or learned_skill",
        ),
      }),
      "query": Json::object({
        "type": Json("string"),
        "description": Json("Search query string (for search action)"),
      }),
      "id": Json::object({
        "type": Json("string"),
        "description": Json("Memory entry ID (for update/delete)"),
      }),
    }),
    "required": [Json("action")],
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
