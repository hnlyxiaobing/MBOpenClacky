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
  match @env.get_env_var("COMPUTERNAME") {
    Some(h) if !h.is_empty() => h
    _ =>
      match @env.get_env_var("HOSTNAME") {
        Some(h) if !h.is_empty() => h
        _ => "unknown-host"
      }
  }
}

///|
/// Get current username.
/// TODO: Replace with FFI to GetUserNameW / getpwuid().
fn get_username() -> String {
  match @env.get_env_var("USERNAME") {
    Some(u) if !u.is_empty() => u
    _ =>
      match @env.get_env_var("USER") {
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
/// Deterministic hash using SHA-256, truncated to 16 hex characters.
/// Produces a stable, cryptographically-derived hash suitable for device IDs
/// and non-security-critical identifiers.
pub fn simple_hash(input : String) -> String {
  let full = sha256_hex(input)
  full[:16].to_owned()
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
