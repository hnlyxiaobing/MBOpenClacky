///| Extension loader: three-level source scanning and merging.
/// Scans builtin (assets/extensions), installed (~/.clacky/extensions),
/// and local (./extensions) sources, then merges with priority ordering.

///|
/// Load extensions from all three sources and merge with priority.
/// Priority: Local > Installed > Builtin.
pub fn load_all_extensions() -> Array[Extension] {
  let builtin = load_extensions_from_source(ExtensionSource::Builtin)
  let installed = load_extensions_from_source(ExtensionSource::Installed)
  let local = load_extensions_from_source(ExtensionSource::Local)
  merge_extensions_with_priority(builtin, installed, local)
}

///|
/// Load extensions from a specific source.
pub fn load_extensions_from_source(
  source : ExtensionSource,
) -> Array[Extension] {
  let dir = get_source_directory(source)
  if !@fs.path_exists(dir) {
    return []
  }
  let extensions : Array[Extension] = []
  let entries = @fs.read_dir(dir) catch { _ => return [] }
  for entry in entries {
    let full_path = @path.Path::join(dir, @path.Path(entry)).to_string()
    let is_directory = @fs.is_dir(full_path) catch { _ => false }
    if is_directory {
      match load_single_extension(full_path, source) {
        Some(ext) => extensions.push(ext)
        None => ()
      }
    }
  }
  extensions
}

///|
/// Get the directory path for a specific source.
pub fn get_source_directory(source : ExtensionSource) -> String {
  match source {
    ExtensionSource::Builtin =>
      @path.Path::join(@utils.current_dir(), @path.Path("assets/extensions")).to_string()
    ExtensionSource::Installed =>
      match @utils.home_dir() {
        Some(home) =>
          @path.Path::join(home, @path.Path(".clacky/extensions")).to_string()
        None => ".clacky/extensions"
      }
    ExtensionSource::Local => "./extensions"
  }
}

///|
/// Load a single extension from a directory.
/// Returns None if ext.yml (or ext.yaml) is missing or malformed.
pub fn load_single_extension(
  dir_path : String,
  source : ExtensionSource,
) -> Extension? {
  let manifest = match load_manifest(dir_path) {
    Some(m) => m
    None => return None
  }
  let enabled = manifest.enabled_by_default
  let loaded_at = @agent.current_time_ms()
  Some({
    manifest,
    source,
    root_path: dir_path,
    enabled,
    loaded_at,
    sha256: None,
  })
}

///|
/// Merge extensions from three sources with priority ordering.
/// Priority: Local > Installed > Builtin.
fn merge_extensions_with_priority(
  builtin : Array[Extension],
  installed : Array[Extension],
  local : Array[Extension],
) -> Array[Extension] {
  let seen : Map[String, Bool] = {}
  let result : Array[Extension] = []
  for ext in local {
    if !seen.contains(ext.manifest.id) {
      seen[ext.manifest.id] = true
      result.push(ext)
    }
  }
  for ext in installed {
    if !seen.contains(ext.manifest.id) {
      seen[ext.manifest.id] = true
      result.push(ext)
    }
  }
  for ext in builtin {
    if !seen.contains(ext.manifest.id) {
      seen[ext.manifest.id] = true
      result.push(ext)
    }
  }
  result
}

///|
/// Load extension manifest from ext.yml or ext.yaml.
fn load_manifest(dir_path : String) -> ExtensionManifest? {
  let yml_path = @path.Path::join(dir_path, @path.Path("ext.yml")).to_string()
  let yaml_path = @path.Path::join(dir_path, @path.Path("ext.yaml")).to_string()
  let content = if @fs.path_exists(yml_path) {
    @fs.read_file_to_string(yml_path) catch {
      _ => return None
    }
  } else if @fs.path_exists(yaml_path) {
    @fs.read_file_to_string(yaml_path) catch {
      _ => return None
    }
  } else {
    return None
  }
  parse_manifest_json(content)
}

///|
/// Parse manifest from JSON content.
/// ext.yml is treated as JSON for MVP simplicity.
fn parse_manifest_json(content : String) -> ExtensionManifest? {
  let json = @json.parse(content) catch { _ => return None }
  match json {
    Object(obj) =>
      match build_manifest_from_obj(obj) {
        Some(m) => Some(m)
        None => None
      }
    _ => None
  }
}

///|
/// Build an ExtensionManifest from a JSON object map.
fn build_manifest_from_obj(obj : Map[String, Json]) -> ExtensionManifest? {
  let id = match obj.get("id") {
    Some(String(s)) => s
    _ => return None
  }
  if id.is_empty() {
    return None
  }
  let name = match obj.get("name") {
    Some(String(s)) => s
    _ => return None
  }
  let version = match obj.get("version") {
    Some(String(s)) => s
    _ => return None
  }
  let description = match obj.get("description") {
    Some(String(s)) => s
    _ => return None
  }
  let author = match obj.get("author") {
    Some(String(s)) => s
    _ => return None
  }
  let license = match obj.get("license") {
    Some(String(s)) => s
    _ => return None
  }
  let homepage = match obj.get("homepage") {
    Some(String(s)) => Some(s)
    _ => None
  }
  let repository = match obj.get("repository") {
    Some(String(s)) => Some(s)
    _ => None
  }
  let keywords = parse_string_array(obj, "keywords")
  let dependencies = parse_string_map(obj, "dependencies")
  let contributions = match parse_contributions(obj, "contributions") {
    Some(arr) => arr
    None => return None
  }
  let enabled_by_default = match obj.get("enabled_by_default") {
    Some(False) => false
    _ => true
  }
  Some({
    id,
    name,
    version,
    description,
    author,
    license,
    homepage,
    repository,
    keywords,
    dependencies,
    contributions,
    enabled_by_default,
  })
}

///|
/// Parse contributions array from a manifest object.
fn parse_contributions(
  obj : Map[String, Json],
  key : String,
) -> Array[ExtensionContribution]? {
  match obj.get(key) {
    Some(Array(arr)) => {
      let contributions : Array[ExtensionContribution] = []
      for item in arr {
        match item {
          Object(cobj) =>
            match build_contribution_from_obj(cobj) {
              Some(c) => contributions.push(c)
              None => ()
            }
          _ => ()
        }
      }
      Some(contributions)
    }
    _ => Some([])
  }
}

///|
/// Build a single ExtensionContribution from a JSON object.
fn build_contribution_from_obj(
  cobj : Map[String, Json],
) -> ExtensionContribution? {
  let type_str = match cobj.get("type") {
    Some(String(s)) => s
    _ => return None
  }
  let type_ = match parse_contribution_type(type_str) {
    Some(t) => t
    None => return None
  }
  let id = match cobj.get("id") {
    Some(String(s)) => s
    _ => return None
  }
  if id.is_empty() {
    return None
  }
  let name = match cobj.get("name") {
    Some(String(s)) => s
    _ => return None
  }
  let description = match cobj.get("description") {
    Some(String(s)) => s
    _ => return None
  }
  let path = match cobj.get("path") {
    Some(String(s)) => s
    _ => return None
  }
  let config = parse_string_map(cobj, "config")
  Some({ type_, id, name, description, path, config })
}

///|
/// Parse contribution type from string.
fn parse_contribution_type(s : String) -> ExtensionContributionType? {
  let lower = s.to_lower()
  match lower {
    "panel" => Some(ExtensionContributionType::Panel)
    "skill" => Some(ExtensionContributionType::Skill)
    "agent" => Some(ExtensionContributionType::Agent)
    "api" => Some(ExtensionContributionType::Api)
    "hook" => Some(ExtensionContributionType::Hook)
    "patch" => Some(ExtensionContributionType::Patch)
    _ => None
  }
}

///|
/// Parse a string array field from a JSON object.
fn parse_string_array(obj : Map[String, Json], key : String) -> Array[String] {
  match obj.get(key) {
    Some(Array(arr)) => {
      let result : Array[String] = []
      for item in arr {
        match item {
          String(s) => result.push(s)
          _ => ()
        }
      }
      result
    }
    _ => []
  }
}

///|
/// Parse a string map field from a JSON object.
fn parse_string_map(
  obj : Map[String, Json],
  key : String,
) -> Map[String, String] {
  match obj.get(key) {
    Some(Object(m)) => {
      let result : Map[String, String] = {}
      m.each(fn(k, v) {
        match v {
          String(s) => result[k] = s
          _ => ()
        }
      })
      result
    }
    _ => {}
  }
}

///|
/// Filter extensions to only those that are currently enabled.
pub fn enabled_extensions(extensions : Array[Extension]) -> Array[Extension] {
  let result : Array[Extension] = []
  for ext in extensions {
    if ext.enabled {
      result.push(ext)
    }
  }
  result
}
