///| API Extension types and loading logic.
/// Extensions are loaded from descriptor files (.json / .toml) in a
/// configurable directory (default: ~/.clacky/api_extensions).

///|
/// A single route defined by an API extension.
pub(all) struct ExtensionRoute {
  /// HTTP method: "GET", "POST", "PUT", "DELETE", etc.
  method : String
  /// Path relative to the /api/ext/<name>/ prefix
  path : String
  /// Logical handler name used for dispatch
  handler_name : String
  /// Human-readable description
  description : String
  /// Per-route execution timeout in milliseconds (default 30 000)
  timeout_ms : Int
} derive(Show)

///|
/// API extension loaded from an extension descriptor file.
pub(all) struct ApiExtension {
  /// Unique extension name
  name : String
  /// Semantic version string
  version : String
  /// Routes provided by this extension
  routes : Array[ExtensionRoute]
  /// Whether this extension is active
  enabled : Bool
} derive(Show)

///|
/// Default extension execution timeout in milliseconds (30 seconds).
pub let default_ext_timeout_ms : Int = 30000

///|
/// Load API extensions from a directory.
/// Scans for .json or .toml extension descriptor files.
/// Returns only extensions that pass validation (non-empty name).
pub fn load_api_extensions(ext_dir? : String? = None) -> Array[ApiExtension] {
  let dir = match ext_dir {
    Some(d) => d
    None =>
      match @utils.home_dir() {
        Some(home) =>
          @path.Path::join(home, @path.Path(".clacky/api_extensions")).to_string()
        None => ".clacky/api_extensions"
      }
  }
  if !@fs.path_exists(dir) {
    return []
  }
  let filenames = @fs.read_dir(dir) catch { _ => return [] }
  let extensions : Array[ApiExtension] = []
  for fname in filenames {
    let is_json = fname.has_suffix(".json")
    let is_toml = fname.has_suffix(".toml")
    if !is_json && !is_toml {
      continue
    }
    let full_path = @path.Path::join(dir, @path.Path(fname)).to_string()
    let content = @fs.read_file_to_string(full_path) catch { _ => continue }
    let ext = if is_json {
      parse_ext_json(content)
    } else {
      parse_ext_simple(content, fname)
    }
    match ext {
      Some(e) => extensions.push(e)
      None => ()
    }
  }
  extensions
}

///|
/// Filter extensions to only those that are enabled.
pub fn enabled_extensions(
  extensions : Array[ApiExtension],
) -> Array[ApiExtension] {
  let result : Array[ApiExtension] = []
  for ext in extensions {
    if ext.enabled {
      result.push(ext)
    }
  }
  result
}

// ── Internal parsers ────────────────────────────────────────────

///|
/// Parse a JSON extension descriptor.
fn parse_ext_json(content : String) -> ApiExtension? {
  let json = @json.parse(content) catch { _ => return None }
  match json {
    Object(obj) => {
      let get_str = fn(key : String) -> String {
        match obj.get(key) {
          Some(String(s)) => s
          _ => ""
        }
      }
      let name = get_str("name")
      if name.is_empty() {
        return None
      }
      let routes : Array[ExtensionRoute] = []
      match obj.get("routes") {
        Some(Array(arr)) =>
          for item in arr {
            match item {
              Object(r) => {
                let rget = fn(key : String) -> String {
                  match r.get(key) {
                    Some(String(s)) => s
                    _ => ""
                  }
                }
                let timeout = match r.get("timeout_ms") {
                  Some(Number(n, ..)) => n.to_int()
                  _ => default_ext_timeout_ms
                }
                routes.push({
                  method: rget("method"),
                  path: rget("path"),
                  handler_name: rget("handler_name"),
                  description: rget("description"),
                  timeout_ms: timeout,
                })
              }
              _ => ()
            }
          }
        _ => ()
      }
      let enabled = match obj.get("enabled") {
        Some(False) => false
        _ => true
      }
      Some({ name, version: get_str("version"), routes, enabled })
    }
    _ => None
  }
}

///|
/// Parse a simple TOML-like extension descriptor (key = "value" lines).
fn parse_ext_simple(content : String, filename : String) -> ApiExtension? {
  let fields : Map[String, String] = {}
  let lines = content.split("\n")
  for line in lines {
    let trimmed = line.trim().to_owned()
    if trimmed.is_empty() || trimmed.has_prefix("#") || trimmed.has_prefix("[") {
      continue
    }
    match trimmed.find("=") {
      Some(pos) => {
        let key = trimmed[0:pos].trim().to_owned()
        let mut value = trimmed[pos + 1:].trim().to_owned()
        if value.has_prefix("\"") &&
          value.has_suffix("\"") &&
          value.length() >= 2 {
          value = value[1:value.length() - 1].to_owned()
        }
        fields[key] = value
      }
      None => ()
    }
  }
  let name = match fields.get("name") {
    Some(n) if !n.is_empty() => n
    _ =>
      if filename.has_suffix(".toml") {
        filename[0:filename.length() - 5].to_owned()
      } else {
        filename
      }
  }
  Some({
    name,
    version: fields.get("version").unwrap_or("0.0.0"),
    routes: [],
    enabled: match fields.get("enabled") {
      Some("false") => false
      _ => true
    },
  })
}
