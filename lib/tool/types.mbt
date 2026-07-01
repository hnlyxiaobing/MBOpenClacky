///|
/// Category of a tool, used for grouping and permission control.
pub(all) enum ToolCategory {
  General
  FileSystem
  Execution
  Web
  Agent
} derive(Eq, Compare, Debug)

///|
/// Convert ToolCategory to a string for JSON serialization.
pub fn ToolCategory::to_string_value(self : ToolCategory) -> String {
  match self {
    General => "general"
    FileSystem => "file_system"
    Execution => "execution"
    Web => "web"
    Agent => "agent"
  }
}

///|
/// Parse a ToolCategory from a string.
pub fn ToolCategory::from_string(s : String) -> ToolCategory? {
  match s {
    "general" => Some(General)
    "file_system" => Some(FileSystem)
    "execution" => Some(Execution)
    "web" => Some(Web)
    "agent" => Some(Agent)
    _ => None
  }
}

///|
pub impl ToJson for ToolCategory with fn to_json(self) {
  self.to_string_value().to_json()
}

///|
/// Result of a tool execution.
pub(all) struct ToolResult {
  content : String
  is_error : Bool
} derive(Eq, Debug, ToJson)

///|
/// Create a successful tool result.
pub fn ToolResult::success(content : String) -> ToolResult {
  { content, is_error: false }
}

///|
/// Create an error tool result.
pub fn ToolResult::error(content : String) -> ToolResult {
  { content, is_error: true }
}

///|
/// Function definition structure within a FunctionDefinition.
pub(all) struct FunctionDef {
  name : String
  description : String
  parameters : Json
} derive(Eq, Debug, ToJson)

///|
/// OpenAI-compatible function definition for tool registration.
/// Note: `type_` field (with trailing underscore because `type` is a
/// MoonBit keyword) is manually serialized as `"type"` in JSON via
/// the custom ToJson implementation below.
pub(all) struct FunctionDefinition {
  type_ : String
  function : FunctionDef
} derive(Eq, Debug)

///| Manually implement ToJson so `type_` serializes as `"type"` (not `"type_"`)
/// in the JSON sent to LLM APIs. The OpenAI tools schema requires the key to
/// be exactly `"type"`.
pub impl ToJson for FunctionDefinition with fn to_json(self : FunctionDefinition) -> Json {
  Json::object({
    "type": self.type_.to_json(),
    "function": self.function.to_json(),
  })
}

///|
/// Create a FunctionDefinition with the default type "function".
pub fn FunctionDefinition::new(
  name : String,
  description : String,
  parameters : Json,
) -> FunctionDefinition {
  { type_: "function", function: { name, description, parameters } }
}

///|
/// Concrete enum wrapping all tool implementations for polymorphic storage.
/// Each variant holds a specific tool struct. Implement Tool trait for AnyTool
/// by dispatching to the inner variant.
pub(all) enum AnyTool {
  FileReader(FileReader)
  Write(Write)
  Edit(Edit)
  Grep(Grep)
  Glob(Glob)
  Terminal(Terminal)
  WebSearch(WebSearch)
  WebFetch(WebFetch)
  InvokeSkill(InvokeSkill)
  MemoryTool(MemoryTool)
  TodoTool(TodoTool)
  RequestUserFeedback(RequestUserFeedback)
  TrashManager(TrashManager)
  Browser(Browser)
} derive(Eq, Debug)
