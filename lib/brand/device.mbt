///|
/// Device identification for license binding
pub(all) struct DeviceInfo {
  device_id : String
  hostname : String
  username : String
  platform : String
} derive(Eq, Debug, ToJson)

///|
/// Generate a stable device identifier based on system properties.
/// Uses hostname + username + platform to create a deterministic hash.
pub fn generate_device_id() -> DeviceInfo {
  let hostname = get_hostname()
  let username = get_username()
  let platform = get_platform()
  let raw = hostname + ":" + username + ":" + platform
  let device_id = simple_hash(raw)
  { device_id, hostname, username, platform }
}

///|
/// Get system hostname.
/// TODO: Replace with FFI to GetComputerNameW / gethostname().
fn get_hostname() -> String {
  match @sys.get_env_var("COMPUTERNAME") {
    Some(h) if !h.is_empty() => h
    _ =>
      match @sys.get_env_var("HOSTNAME") {
        Some(h) if !h.is_empty() => h
        _ => "unknown-host"
      }
  }
}

///|
/// Get current username.
/// TODO: Replace with FFI to GetUserNameW / getpwuid().
fn get_username() -> String {
  match @sys.get_env_var("USERNAME") {
    Some(u) if !u.is_empty() => u
    _ =>
      match @sys.get_env_var("USER") {
        Some(u) if !u.is_empty() => u
        _ => "unknown-user"
      }
  }
}

///|
/// Get platform identifier
fn get_platform() -> String {
  "windows"
}

///|
/// Simple deterministic hash (placeholder for SHA256).
/// Produces a 16-character hex string from the input.
pub fn simple_hash(input : String) -> String {
  let mut hash : UInt = 0
  for c in input {
    hash = hash * 31 + c.to_int().reinterpret_as_uint()
  }
  let hex_chars = "0123456789abcdef"
  let mut result = ""
  let mut h = hash
  for i = 0; i < 16; i = i + 1 {
    let idx = (h & 0xF).reinterpret_as_int()
    result = result + hex_chars[idx].to_string()
    h = h >> 4
  }
  result
}

///|
/// Ensure device_id exists in config (generate if missing).
pub fn ensure_device_id(config : BrandConfig) -> String {
  match config.device_id {
    Some(id) if id.length() > 0 => id
    _ => {
      let info = generate_device_id()
      config.device_id = Some(info.device_id)
      info.device_id
    }
  }
}
