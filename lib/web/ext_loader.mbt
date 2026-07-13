///| API Extension types and loading logic.
/// Extensions are loaded from descriptor files (.json / .toml) in a
/// configurable directory (default: ~/.clacky/api_extensions).

///|
/// A single route defined by an API extension.
pub(all) struct ExtensionRoute {
  /// HTTP method: "GET", "POST", "PUT", "DELETE", etc.
  http_method : String
  /// Path relative to the /api/ext/<name>/ prefix
  path : String
  /// Logical handler name used for dispatch
  handler_name : String
  /// Shell command to execute for this route (empty = stub fallback)
  command : String
  /// Human-readable description
  description : String
  /// Per-route execution timeout in milliseconds (default 30 000)
  timeout_ms : Int
} derive(Debug)

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
} derive(Debug)

///|
/// Default extension execution timeout in milliseconds (30 seconds).
pub let default_ext_timeout_ms : Int = 30000

///|
/// Maximum extension execution timeout in milliseconds (10 minutes). Routes
/// declaring a `timeout_ms` greater than this (or non-positive) fall back
/// to `default_ext_timeout_ms`. This prevents a single extension from
/// claiming an unbounded execution budget.
pub let max_ext_timeout_ms : Int = 600000

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
/// Load API extensions from a list of (extension_id, file_path) pairs
/// produced by the extension framework's `collect_api_contribution_paths`.
/// This is the bridge that turns `ext.yml` `api` contributions into
/// `ApiExtension` values ready for `ExtensionDispatcher` registration.
///
/// Each file is parsed as JSON (`.json` suffix) or the simple TOML-like
/// format (`.toml` or other). When the parsed descriptor's `name` is
/// empty, the extension id is used as a fallback. Parse failures and
/// missing files are logged and skipped — a single bad extension must
/// not prevent the rest of the dispatcher from loading.
pub fn load_extensions_from_paths(
  paths : Array[(String, String)],
) -> Array[ApiExtension] {
  let result : Array[ApiExtension] = []
  for pair in paths {
    let (ext_id, file_path) = pair
    if !@fs.path_exists(file_path) {
      println(
        "[ext_loader] api contribution file not found, skipping: " +
        file_path +
        " (ext=" +
        ext_id +
        ")",
      )
      continue
    }
    let content = @fs.read_file_to_string(file_path) catch {
      _ => {
        println(
          "[ext_loader] failed to read api contribution file, skipping: " +
          file_path,
        )
        continue
      }
    }
    let is_json = file_path.has_suffix(".json")
    let parsed = if is_json {
      parse_ext_json(content)
    } else {
      parse_ext_simple(content, file_path)
    }
    match parsed {
      Some(e) => {
        // Prefer the descriptor's own `name`; fall back to ext_id
        let name = if e.name.is_empty() { ext_id } else { e.name }
        result.push({ ..e, name, })
      }
      None =>
        println(
          "[ext_loader] failed to parse api contribution descriptor: " +
          file_path,
        )
    }
  }
  result
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

///|
/// Merge two arrays of `ApiExtension` by name. Entries in `b` override
/// entries in `a` on name clash — this lets ext.yml `api` contributions
/// win over standalone descriptor files for the same extension name,
/// so the unified (contribution-driven) flow is authoritative.
pub fn merge_api_extensions(
  a : Array[ApiExtension],
  b : Array[ApiExtension],
) -> Array[ApiExtension] {
  let seen : Map[String, Bool] = {}
  let result : Array[ApiExtension] = []
  for ext in b {
    if !seen.contains(ext.name) {
      seen[ext.name] = true
      result.push(ext)
    }
  }
  for ext in a {
    if !seen.contains(ext.name) {
      seen[ext.name] = true
      result.push(ext)
    }
  }
  result
}

// ── Internal helpers ────────────────────────────────────────────

///|
/// Expand a leading `~` to the user's home directory.
/// Only expands when `~` appears at the start of the string.
fn expand_tilde(path : String) -> String {
  if path.has_prefix("~/") {
    match @utils.home_dir() {
      Some(home) => home + path[1:].to_owned()
      None => path
    }
  } else if path == "~" {
    match @utils.home_dir() {
      Some(home) => home
      None => path
    }
  } else {
    path
  }
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
                let raw_command = rget("command")
                let command = expand_tilde(raw_command)
                routes.push({
                  http_method: rget("method"),
                  path: rget("path"),
                  handler_name: rget("handler_name"),
                  command,
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
