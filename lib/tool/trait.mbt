///| The Tool trait defines the interface for all tool implementations.

///|
/// Declared as pub(open) so external packages can implement new tools.
pub(open) trait Tool {
  ///| Canonical name of the tool (e.g., "file_reader").
  fn name(Self) -> String

  ///| Human-readable description of what the tool does.
  fn description(Self) -> String

  ///| JSON Schema object describing the tool's parameters.
  fn parameters(Self) -> Json

  ///| Category of the tool for grouping and permission control.
  fn category(Self) -> ToolCategory

  ///| Execute the tool with the given arguments and return a result.
  fn execute(Self, Map[String, Json]) -> ToolResult

  ///| Format a tool call for display in the UI.
  fn format_call(Self, Map[String, Json]) -> String

  ///| Format a tool result for display in the UI.
  fn format_result(Self, ToolResult) -> String

  ///| Convert to OpenAI function definition format for API submission.
  fn to_function_definition(Self) -> FunctionDefinition
}
