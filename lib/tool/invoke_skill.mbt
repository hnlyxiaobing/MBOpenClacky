///| InvokeSkill tool: invokes a registered skill by name with optional arguments.

///|
/// The actual execution is intercepted and handled in the agent context
/// (lib/agent/tool_executor.mbt). This stub returns a placeholder message.
pub(all) struct InvokeSkill {} derive(Eq, Debug)

///|
pub extend InvokeSkill with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend InvokeSkill with Eq::{not_equal, equal}

///|
impl Tool for InvokeSkill with fn name(_) -> String {
  "invoke_skill"
}

///|
impl Tool for InvokeSkill with fn description(_) -> String {
  "Invoke a registered skill by name with optional arguments"
}

///|
impl Tool for InvokeSkill with fn parameters(_) -> Json {
  Json::object({
    "type": "object".to_json(),
    "properties": Json::object({
      "skill_name": Json::object({
        "type": "string".to_json(),
        "description": "The name of the skill to invoke".to_json(),
      }),
      "arguments": Json::object({
        "type": "string".to_json(),
        "description": "Optional arguments string to pass to the skill".to_json(),
      }),
    }),
    "required": ["skill_name".to_json()],
  })
}

///|
impl Tool for InvokeSkill with fn category(_) -> ToolCategory {
  Agent
}

///|
impl Tool for InvokeSkill with fn execute(_, _args : Map[String, Json]) -> ToolResult {
  ToolResult::success("Skill invocation must be handled by agent context")
}

///|
impl Tool for InvokeSkill with fn format_call(_, args : Map[String, Json]) -> String {
  match args.get("skill_name") {
    Some(String(name)) => "InvokeSkill(\{name})"
    _ => "InvokeSkill(?)"
  }
}

///|
impl Tool for InvokeSkill with fn format_result(_, result : ToolResult) -> String {
  if result.is_error {
    result.content
  } else {
    "Skill invoked (\{result.content.length()} chars)"
  }
}

///|
impl Tool for InvokeSkill with fn to_function_definition(self) -> FunctionDefinition {
  FunctionDefinition::new(self.name(), self.description(), self.parameters())
}
