///|
/// Identity module — manages device binding and identity persistence.
///
/// Stores identity in `~/.clacky/identity.json` (JSON format, 0o600 on Unix).
/// Used by RFC 8628 device authorization flow and publish verification chain.

///|
/// Represents a bound device identity.
pub(all) struct Identity {
  device_token : String
  user_id : String
  bound_at : Int64
  device_info : DeviceInfo
} derive(Eq, Debug, ToJson)

///|
pub extend Identity with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend Identity with Eq::{not_equal, equal}

///|
pub extend Identity with ToJson::{to_json}

///|
/// Construct an Identity from device-authorization result.
pub fn create_identity(
  device_token : String,
  user_id : String,
  bound_at : Int64,
  device_info : DeviceInfo,
) -> Identity {
  { device_token, user_id, bound_at, device_info }
}

// ── Persistence ────────────────────────────────────────────────────

///|
/// Returns the path to `~/.clacky/identity.json` or `None` when home is unavailable.
fn identity_path() -> String? {
  match @utils.home_dir() {
    Some(home) =>
      Some(
        @path.Path::join(home, @path.Path(".clacky/identity.json")).to_string(),
      )
    None => None
  }
}

///|
/// Load identity from disk. Returns `None` when not bound or when the file is
/// missing / unreadable / malformed.
pub fn load_identity() -> Identity? {
  match identity_path() {
    Some(path) => {
      if !@fs.path_exists(path) {
        return None
      }
      let content = @fs.read_file_to_string(path) catch { _ => return None }
      if content.is_empty() {
        return None
      }
      let json = @json.parse(content) catch { _ => return None }
      parse_identity(json)
    }
    None => None
  }
}

///|
/// Parse an `Identity` from a JSON value. Public so white-box tests can
/// exercise round-trip without touching the filesystem.
pub fn parse_identity(json : Json) -> Identity? {
  match json {
    Object(obj) => {
      let device_token = match obj.get("device_token") {
        Some(String(s)) => s
        _ => return None
      }
      let user_id = match obj.get("user_id") {
        Some(String(s)) => s
        _ => return None
      }
      let bound_at = match obj.get("bound_at") {
        Some(Number(n, ..)) => n.to_int64()
        // derive(ToJson) serializes Int64 as a JSON string (JS precision
        // guard), so a save-then-load round-trip arrives as String.
        Some(String(s)) => @string.parse_int64(s) catch { _ => return None }
        _ => return None
      }
      let device_info = match obj.get("device_info") {
        Some(Object(di_obj)) =>
          match parse_device_info_json(di_obj) {
            Some(di) => di
            None => return None
          }
        _ => return None
      }
      Some({ device_token, user_id, bound_at, device_info })
    }
    _ => None
  }
}

///|
/// Parse `DeviceInfo` from a JSON object map.
fn parse_device_info_json(obj : Map[String, Json]) -> DeviceInfo? {
  let device_id = match obj.get("device_id") {
    Some(String(s)) => s
    _ => return None
  }
  let hostname = match obj.get("hostname") {
    Some(String(s)) => s
    _ => return None
  }
  let username = match obj.get("username") {
    Some(String(s)) => s
    _ => return None
  }
  let platform = match obj.get("platform") {
    Some(String(s)) => s
    _ => return None
  }
  Some({ device_id, hostname, username, platform })
}

///|
/// Save identity to disk. Parent directory is created automatically.
/// Errors (e.g. permission denied) are silently swallowed (best-effort).
pub fn save_identity(identity : Identity) -> Unit {
  match identity_path() {
    Some(path) => {
      let parent = @path.Path::dirname(@path.Path(path)).to_string()
      @utils.ensure_dir(parent)
      @fs.write_string_to_file(path, identity.to_json().stringify()) catch {
        _ => ()
      }
    }
    None => ()
  }
}

// ── Query helpers ──────────────────────────────────────────────────

///|
/// Check whether the device has been bound. A mere file on disk is not
/// enough (p6 decision 8, Ruby identity.rb): the stored identity must load
/// and carry a non-empty device_token.
pub fn is_bound() -> Bool {
  match load_identity() {
    Some(identity) => !identity.device_token.is_empty()
    None => false
  }
}

///|
/// Verify a device token against the stored identity.
pub fn verify_token(token : String) -> Bool {
  match load_identity() {
    Some(identity) => identity.device_token == token
    None => false
  }
}

// ── Binding management ─────────────────────────────────────────────

///|
/// Bind the device to a user by persisting a fresh identity.
/// Generates a new device_info snapshot, stamps bound_at with the current
/// epoch time (ms), and writes the identity file (best-effort).
/// Returns Err when the token is empty.
pub fn bind_identity(
  device_token : String,
  user_id : String,
) -> Result[Unit, String] {
  if device_token.is_empty() {
    return Err("device token must not be empty")
  }
  let identity = create_identity(
    device_token,
    user_id,
    @env.now().reinterpret_as_int64(),
    generate_device_id(),
  )
  save_identity(identity)
  Ok(())
}

///|
/// Unbind the device by removing the identity file.
/// Errors (e.g. file missing, permission denied) are silently swallowed
/// (best-effort) so clearing is always safe to call.
pub fn clear_identity() -> Unit {
  match identity_path() {
    Some(path) => @fs.remove_file(path) catch { _ => () }
    None => ()
  }
}
