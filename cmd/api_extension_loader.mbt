///|
/// API extension route definition.
pub(all) struct ExtensionRoute {
  method : String
  path : String
  handler_name : String
  description : String
} derive(Show)

///|
/// API extension loaded from an extension descriptor file.
pub(all) struct ApiExtension {
  name : String
  version : String
  routes : Array[ExtensionRoute]
  enabled : Bool
} derive(Show)

///|
/// Load API extensions from a directory.
/// Scans for .json or .toml extension descriptor files.
pub fn load_extensions(ext_dir? : String? = None) -> Array[ApiExtension] {
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
      parse_extension_json(content)
    } else {
      parse_extension_simple(content, fname)
    }
    match ext {
      Some(e) => extensions.push(e)
      None => ()
    }
  }
  extensions
}

///|
/// Register extensions to the web server (stub: logs each extension).
pub fn register_extensions(
  extensions : Array[ApiExtension],
) -> Result[Unit, String] {
  for ext in extensions {
    if !ext.enabled {
      continue
    }
    println(
      "[ApiExtension] Registering '\{ext.name}' v\{ext.version} (\{ext.routes.length()} route(s))",
    )
    for route in ext.routes {
      println(
        "[ApiExtension]   \{route.method} \{route.path} -> \{route.handler_name}: \{route.description}",
      )
    }
  }
  Ok(())
}

///|
/// Parse a JSON extension descriptor.
fn parse_extension_json(content : String) -> ApiExtension? {
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
                routes.push({
                  method: rget("method"),
                  path: rget("path"),
                  handler_name: rget("handler_name"),
                  description: rget("description"),
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
/// Parse a simple TOML-like extension descriptor.
fn parse_extension_simple(content : String, filename : String) -> ApiExtension? {
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
