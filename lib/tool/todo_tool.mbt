///| TodoTool: manage task items within the agent context.

///|
/// The actual execution is intercepted and handled in the agent context
/// (lib/agent/tool_executor.mbt). The parameters/description/format
/// surface mirrors the Ruby TodoManager tool (schema: action enum with
/// polymorphic `task`/`id` accepting scalar or array).
pub(all) struct TodoTool {} derive(Eq, Debug)

///|
pub extend TodoTool with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend TodoTool with Eq::{not_equal, equal}

///|
impl Tool for TodoTool with fn name(_) -> String {
  "todo_manager"
}

///|
impl Tool for TodoTool with fn description(_) -> String {
  "Plan and track multi-step tasks. Skip for trivial single-step requests.\n\n`task` and `id` accept a single value OR an array — always batch when you can (e.g. `complete id:[1,2,3]` in one call, not three).\n\nOnly `complete` a todo once it's truly done end-to-end, not per sub-step."
}

///|
impl Tool for TodoTool with fn parameters(_) -> Json {
  Json::object({
    "type": Json("object"),
    "properties": Json::object({
      "action": Json::object({
        "type": Json("string"),
        "enum": [
          Json("add"),
          Json("list"),
          Json("complete"),
          Json("remove"),
          Json("clear"),
        ],
        "description": Json("add | list | complete | remove | clear"),
      }),
      "task": Json::object({
        "description": Json(
          "add: task description(s). Accepts a string OR an array of strings for batch add.",
        ),
        "oneOf": [
          Json::object({ "type": Json("string") }),
          Json::object({
            "type": Json("array"),
            "items": Json::object({ "type": Json("string") }),
          }),
        ],
      }),
      "id": Json::object({
        "description": Json(
          "complete/remove: task id(s). Accepts an integer OR an array of integers for batch ops.",
        ),
        "oneOf": [
          Json::object({ "type": Json("integer") }),
          Json::object({
            "type": Json("array"),
            "items": Json::object({ "type": Json("integer") }),
          }),
        ],
      }),
    }),
    "required": [Json("action")],
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
  let action = match args.get("action") {
    Some(String(s)) => s
    _ => return "TodoManager(?)"
  }
  match action {
    "add" => {
      let count = match args.get("task") {
        Some(Array(items)) => items.length()
        Some(_) => 1
        _ => 0
      }
      if count == 1 {
        "TodoManager(add 1 task)"
      } else {
        "TodoManager(add \{count} tasks)"
      }
    }
    "complete" =>
      match args.get("id") {
        Some(Array(items)) if items.length() > 1 => {
          let parts : Array[String] = items.map(fn(item) {
            match item {
              Number(n, ..) => n.to_int().to_string()
              _ => "?"
            }
          })
          "TodoManager(complete \{items.length()} tasks: \{parts.join(", ")})"
        }
        Some(id) => {
          let single = match id {
            Array(items) if items.length() == 1 =>
              match items[0] {
                Number(n, ..) => n.to_int().to_string()
                _ => "?"
              }
            Number(n, ..) => n.to_int().to_string()
            _ => "?"
          }
          "TodoManager(complete #\{single})"
        }
        _ => "TodoManager(complete ?)"
      }
    "remove" =>
      match args.get("id") {
        Some(Array(items)) if items.length() > 1 => {
          let parts : Array[String] = items.map(fn(item) {
            match item {
              Number(n, ..) => n.to_int().to_string()
              _ => "?"
            }
          })
          "TodoManager(remove \{items.length()} tasks: \{parts.join(", ")})"
        }
        Some(id) => {
          let single = match id {
            Array(items) if items.length() == 1 =>
              match items[0] {
                Number(n, ..) => n.to_int().to_string()
                _ => "?"
              }
            Number(n, ..) => n.to_int().to_string()
            _ => "?"
          }
          "TodoManager(remove #\{single})"
        }
        _ => "TodoManager(remove ?)"
      }
    "list" => "TodoManager(list)"
    "clear" => "TodoManager(clear all)"
    _ => "TodoManager(\{action})"
  }
}

///|
impl Tool for TodoTool with fn format_result(_, result : ToolResult) -> String {
  if result.is_error {
    result.content
  } else {
    result.content
  }
}

///|
impl Tool for TodoTool with fn to_function_definition(self) -> FunctionDefinition {
  FunctionDefinition::new(self.name(), self.description(), self.parameters())
}
