///|
/// A function call within a tool call.
pub(all) struct FunctionCall {
  name : String
  arguments : String
} derive(Eq, Debug, ToJson)

///|
pub extend FunctionCall with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend FunctionCall with Eq::{not_equal, equal}

///|
pub extend FunctionCall with ToJson::{to_json}

///| A tool call from the assistant.

///|
/// The `type_` field (trailing underscore avoids keyword collision) defaults to "function".
/// `extra_content` preserves provider-specific per-call metadata (e.g. Vertex
/// Gemini's `thought_signature` via OpenRouter) that must be echoed back on
/// the next turn to avoid a 400.
pub(all) struct ToolCall {
  id : String
  type_ : String
  function : FunctionCall
  extra_content : Json?
} derive(Eq, Debug)

///|
pub extend ToolCall with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ToolCall with Eq::{not_equal, equal}

///|
pub impl ToJson for ToolCall with fn to_json(self) {
  let obj : Map[String, Json] = {
    "id": self.id.to_json(),
    "type": self.type_.to_json(),
    "function": self.function.to_json(),
  }
  match self.extra_content {
    Some(ec) => obj["extra_content"] = ec
    None => ()
  }
  Json::object(obj)
}

///|
/// Create a ToolCall with the default type "function".
pub fn ToolCall::new(
  id : String,
  name : String,
  arguments : String,
  extra_content? : Json? = None,
) -> ToolCall {
  {
    id,
    type_: "function",
    function: FunctionCall::{ name, arguments },
    extra_content,
  }
}

///|
impl FromJson for FunctionCall with fn from_json(json, path) {
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
impl FromJson for ToolCall with fn from_json(json, path) {
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
        Some(f) => FromJson::from_json(f, path.add_key("function"))
        _ => raise JsonDecodeError((path, "ToolCall: missing 'function'"))
      }
      let extra_content = match map.get("extra_content") {
        Some(ec) => Some(ec)
        _ => None
      }
      { id, type_, function, extra_content }
    }
    _ => raise JsonDecodeError((path, "ToolCall: expected object"))
  }
}
