///| Permission mode for tool execution.

///|
/// Controls how the agent asks for user confirmation before running tools.
pub(all) enum PermissionMode {
  AutoApprove
  ConfirmSafes
  ConfirmAll
} derive(Eq, Compare, Debug)

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
impl ToJson for PermissionMode with to_json(self) {
  self.to_string_value().to_json()
}

///|
impl FromJson for PermissionMode with from_json(json, path) {
  match json {
    String(s) =>
      match PermissionMode::from_string(s) {
        Some(mode) => mode
        None => raise JsonDecodeError((path, "invalid permission_mode: \{s}"))
      }
    _ => raise JsonDecodeError((path, "expected string for permission_mode"))
  }
}
