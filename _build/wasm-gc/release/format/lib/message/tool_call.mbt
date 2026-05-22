///|
/// A function call within a tool call.
pub(all) struct FunctionCall {
  name : String
  arguments : String
} derive(Eq, Debug, ToJson)

///| A tool call from the assistant.

///|
/// The `type_` field (trailing underscore avoids keyword collision) defaults to "function".
pub(all) struct ToolCall {
  id : String
  type_ : String
  function : FunctionCall
} derive(Eq, Debug, ToJson)

///|
/// Create a ToolCall with the default type "function".
pub fn ToolCall::new(
  id : String,
  name : String,
  arguments : String,
) -> ToolCall {
  { id, type_: "function", function: FunctionCall::{ name, arguments } }
}
