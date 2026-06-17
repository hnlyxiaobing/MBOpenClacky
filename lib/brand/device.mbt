///|
/// Device identification for license binding
pub(all) struct DeviceInfo {
  device_id : String
  hostname : String
  username : String
  platform : String
} derive(Eq, Debug, ToJson)

///|
/// Generate a stable device identifier
pub fn generate_device_id() -> DeviceInfo {
  let hostname = get_hostname()
  let username = get_username()
  let platform = get_platform()
  let raw = hostname + ":" + username + ":" + platform
  let device_id = simple_hash(raw)
  { device_id, hostname, username, platform }
}

///|
/// Get system hostname (placeholder)
fn get_hostname() -> String {
  // TODO: FFI to system
  "unknown-host"
}

///|
/// Get current username (placeholder)
fn get_username() -> String {
  // TODO: FFI to system
  "unknown-user"
}

///|
/// Get platform identifier
fn get_platform() -> String {
  // TODO: compile-time detection
  "windows"
}

///|
/// Simple deterministic hash (placeholder for SHA256)
pub fn simple_hash(input : String) -> String {
  let mut hash : UInt = 0
  for c in input {
    hash = hash * 31 + c.to_int().to_uint()
  }
  let hex_chars = "0123456789abcdef"
  let mut result = ""
  let mut h = hash
  for i = 0; i < 16; i = i + 1 {
    let idx = (h & 0xF).to_int()
    result = result + hex_chars[idx].to_string()
    h = h >> 4
  }
  result
}

///|
/// Ensure device_id exists in config (generate if missing)
pub fn ensure_device_id(config : BrandConfig) -> String {
  match config.device_id {
    Some(id) => id
    None => generate_device_id().device_id
  }
}
