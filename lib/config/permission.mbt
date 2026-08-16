///| Permission mode for tool execution.

///|
/// Controls how the agent asks for user confirmation before running tools.
pub(all) enum PermissionMode {
  AutoApprove
  ConfirmSafes
  ConfirmAll
} derive(Eq, Compare, Debug)

///|
pub extend PermissionMode with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend PermissionMode with @moonbitlang/core/json.FromJson::{from_json}

///|
pub extend PermissionMode with Compare::{op_lt, op_le, op_ge, compare, op_gt}

///|
pub extend PermissionMode with Eq::{not_equal, equal}

///|
/// Convert PermissionMode to a string for JSON/TOML serialization.
pub fn PermissionMode::to_string_value(self : PermissionMode) -> String {
  match self {
    AutoApprove => "auto_approve"
    ConfirmSafes => "confirm_safes"
    ConfirmAll => "confirm_all"
  }
}

///|
/// Parse a PermissionMode from a string.
pub fn PermissionMode::from_string(s : String) -> PermissionMode? {
  match s {
    "auto_approve" => Some(AutoApprove)
    "confirm_safes" => Some(ConfirmSafes)
    "confirm_all" => Some(ConfirmAll)
    _ => None
  }
}

///|
impl ToJson for PermissionMode with fn to_json(self) {
  self.to_string_value().to_json()
}

///|
pub impl FromJson for PermissionMode with fn from_json(json, path) {
  match json {
    String(s) =>
      match PermissionMode::from_string(s) {
        Some(mode) => mode
        None => raise JsonDecodeError((path, "invalid permission_mode: \{s}"))
      }
    _ => raise JsonDecodeError((path, "expected string for permission_mode"))
  }
}
