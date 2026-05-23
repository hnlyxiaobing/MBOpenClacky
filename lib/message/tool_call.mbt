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

///|
impl FromJson for FunctionCall with from_json(json, path) {
  match json {
    Object(map) => {
      let name = match map.get("name") {
        Some(String(s)) => s
        _ => raise JsonDecodeError((path, "FunctionCall: missing 'name'"))
      }
      let arguments = match map.get("arguments") {
        Some(String(s)) => s
        _ => raise JsonDecodeError((path, "FunctionCall: missing 'arguments'"))
      }
      { name, arguments }
    }
    _ => raise JsonDecodeError((path, "FunctionCall: expected object"))
  }
}

///|
impl FromJson for ToolCall with from_json(json, path) {
  match json {
    Object(map) => {
      let id = match map.get("id") {
        Some(String(s)) => s
        _ => raise JsonDecodeError((path, "ToolCall: missing 'id'"))
      }
      let type_ = match map.get("type") {
        Some(String(s)) => s
        _ => "function"
      }
      let function = match map.get("function") {
        Some(f) => FunctionCall::from_json(f, path.add_key("function"))
        _ => raise JsonDecodeError((path, "ToolCall: missing 'function'"))
      }
      { id, type_, function }
    }
    _ => raise JsonDecodeError((path, "ToolCall: expected object"))
  }
}
