///| Role of a message in a conversation.

///|
/// Maps to OpenAI-compatible role strings for JSON serialization.
pub(all) enum Role {
  User
  Assistant
  System
  Tool
} derive(Eq, Compare, Debug)

///|
pub extend Role with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend Role with Compare::{op_lt, op_le, op_ge, compare, op_gt}

///|
pub extend Role with Eq::{not_equal, equal}

///|
/// Convert Role to OpenAI-compatible lowercase string.
pub fn Role::to_string_value(self : Role) -> String {
  match self {
    User => "user"
    Assistant => "assistant"
    System => "system"
    Tool => "tool"
  }
}

///| Parse a Role from an OpenAI-compatible lowercase string.

///|
/// Returns None if the string is not a valid role.
pub fn Role::from_string(s : String) -> Role? {
  match s {
    "user" => Some(User)
    "assistant" => Some(Assistant)
    "system" => Some(System)
    "tool" => Some(Tool)
    _ => None
  }
}

///|
impl ToJson for Role with fn to_json(self) {
  self.to_string_value().to_json()
}

///|
impl FromJson for Role with fn from_json(json, path) {
  match json {
    String(s) =>
      match Role::from_string(s) {
        Some(role) => role
        None => raise JsonDecodeError((path, "invalid role: \{s}"))
      }
    _ => raise JsonDecodeError((path, "expected string for role"))
  }
}
