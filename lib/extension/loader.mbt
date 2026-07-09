///| Extension loader: three-level source scanning and merging.
/// Scans builtin (assets/extensions), installed (~/.clacky/extensions),
/// and local (./extensions) sources, then merges with priority ordering.

use @clacky.extension.types.{
  Extension,
  ExtensionManifest,
  ExtensionSource,
  ExtensionContribution,
  ExtensionContributionType,
}
use @path.Path
use @fs
use @utils
use @json

///|
/// Load extensions from all three sources and merge with priority.
/// Priority: Local > Installed > Builtin
pub(all) fn load_all_extensions() -> Array[Extension] {
  let builtin = load_extensions_from_source(ExtensionSource::Builtin)
  let installed = load_extensions_from_source(ExtensionSource::Installed)
  let local = load_extensions_from_source(ExtensionSource::Local)
  
  merge_extensions_with_priority(builtin, installed, local)
}

///|
/// Load extensions from a specific source.
pub(all) fn load_extensions_from_source(source : ExtensionSource) -> Array[Extension] {
  let dir = get_source_directory(source)
  if !fs.path_exists(dir) {
    return []
  }
  
  let extensions : Array[Extension] = []
  let entries = fs.read_dir(dir) catch { _ => return [] }
  
  for entry in entries {
    let full_path = Path::join(dir, Path(entry)).to_string()
    if fs.is_dir(full_path) {
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
pub(all) fn get_source_directory(source : ExtensionSource) -> String {
  match source {
    ExtensionSource::Builtin =>
      Path::join(utils.get_project_root(), Path("assets/extensions")).to_string()
    ExtensionSource::Installed =>
      match utils.home_dir() {
        Some(home) => Path::join(home, Path(".clacky/extensions")).to_string()
        None => ".clacky/extensions"
      }
    ExtensionSource::Local => "./extensions"
  }
}

///|
/// Load a single extension from a directory.
pub(all) fn load_single_extension(
  dir_path : String,
  source : ExtensionSource,
) -> Extension? {
  let manifest_path = Path::join(dir_path, Path("ext.yml")).to_string()
  if !fs.path_exists(manifest_path) {
    // Try ext.yaml as fallback
    let yaml_path = Path::join(dir_path, Path("ext.yaml")).to_string()
    if !fs.path_exists(yaml_path) {
      return None
    }
  }
  
  let manifest = load_manifest(dir_path) catch { _ => return None }
  let enabled = manifest.enabled_by_default
  let loaded_at = @sys.time_now_ms()
  
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
/// Priority: Local > Installed > Builtin
fn merge_extensions_with_priority(
  builtin : Array[Extension],
  installed : Array[Extension],
  local : Array[Extension],
) -> Array[Extension] {
  let seen : Map[String, Bool] = {}
  let result : Array[Extension] = []
  
  // Local extensions (highest priority)
  for ext in local {
    let id = ext.manifest.id
    if !seen.contains_key(id) {
      seen[id] = true
      result.push(ext)
    }
  }
  
  // Installed extensions
  for ext in installed {
    let id = ext.manifest.id
    if !seen.contains_key(id) {
      seen[id] = true
      result.push(ext)
    }
  }
  
  // Builtin extensions (lowest priority)
  for ext in builtin {
    let id = ext.manifest.id
    if !seen.contains_key(id) {
      seen[id] = true
      result.push(ext)
    }
  }
  
  result
}

///|
/// Load extension manifest from ext.yml or ext.yaml.
fn load_manifest(dir_path : String) -> Result[ExtensionManifest, String] {
  let yml_path = Path::join(dir_path, Path("ext.yml")).to_string()
  let yaml_path = Path::join(dir_path, Path("ext.yaml")).to_string()
  
  let content = if fs.path_exists(yml_path) {
    fs.read_file_to_string(yml_path) catch { e => Err(e.to_string())? }
  } else if fs.path_exists(yaml_path) {
    fs.read_file_to_string(yaml_path) catch { e => Err(e.to_string())? }
  } else {
    Err("ext.yml or ext.yaml not found")?
  }
  
  // For MVP, we use JSON-like parsing (we can implement proper YAML later)
  // For now, let's support a simple JSON format in ext.yml
  parse_manifest_json(content)
}

///|
/// Parse manifest from JSON content.
fn parse_manifest_json(content : String) -> Result[ExtensionManifest, String] {
  let json = json.parse(content) catch { e => Err(e.to_string())? }
  
  match json {
    Object(obj) => {
      let id = get_required_string(obj, "id")?
      let name = get_required_string(obj, "name")?
      let version = get_required_string(obj, "version")?
      let description = get_required_string(obj, "description")?
      let author = get_required_string(obj, "author")?
      let license = get_required_string(obj, "license")?
      
      let homepage = get_optional_string(obj, "homepage")
      let repository = get_optional_string(obj, "repository")
      
      let keywords = get_string_array(obj, "keywords")
      let dependencies = get_string_map(obj, "dependencies")
      let contributions = parse_contributions(obj, "contributions")?
      
      let enabled_by_default = match obj.get("enabled_by_default") {
        Some(False) => false
        _ => true
      }
      
      Ok({
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
    _ => Err("manifest must be a JSON object")
  }
}

///|
/// Parse contributions from manifest.
fn parse_contributions(
  obj : Map[String, Json],
  key : String,
) -> Result[Array[ExtensionContribution], String] {
  match obj.get(key) {
    Some(Array(arr)) => {
      let contributions : Array[ExtensionContribution] = []
      for item in arr {
        match item {
          Object(cobj) => {
            let type_str = get_required_string(cobj, "type")?
            let type_ = parse_contribution_type(type_str)?
            let id = get_required_string(cobj, "id")?
            let name = get_required_string(cobj, "name")?
            let description = get_required_string(cobj, "description")?
            let path = get_required_string(cobj, "path")?
            let config = get_string_map(cobj, "config")
            
            contributions.push({
              type_,
              id,
              name,
              description,
              path,
              config,
            })
          }
          _ => Err("contribution must be an object")?
        }
      }
      Ok(contributions)
    }
    _ => Ok([])
  }
}

///|
/// Parse contribution type from string.
fn parse_contribution_type(s : String) -> Result[ExtensionContributionType, String] {
  match s.to_lower() {
    "panel" => Ok(ExtensionContributionType::Panel)
    "skill" => Ok(ExtensionContributionType::Skill)
    "agent" => Ok(ExtensionContributionType::Agent)
    "api" => Ok(ExtensionContributionType::Api)
    "hook" => Ok(ExtensionContributionType::Hook)
    "patch" => Ok(ExtensionContributionType::Patch)
    _ => Err("invalid contribution type: \{s}")
  }
}

///|
/// Get required string field from JSON object.
fn get_required_string(obj : Map[String, Json], key : String) -> Result[String, String] {
  match obj.get(key) {
    Some(String(s)) => Ok(s)
    _ => Err("missing or invalid required field: \{key}")
  }
}

///|
/// Get optional string field from JSON object.
fn get_optional_string(obj : Map[String, Json], key : String) -> String? {
  match obj.get(key) {
    Some(String(s)) => Some(s)
    _ => None
  }
}

///|
/// Get string array from JSON object.
fn get_string_array(obj : Map[String, Json], key : String) -> Array[String] {
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
/// Get string map from JSON object.
fn get_string_map(obj : Map[String, Json], key : String) -> Map[String, String] {
  match obj.get(key) {
    Some(Object(m)) => {
      let result : Map[String, String] = {}
      for (k, v) in m {
        match v {
          String(s) => result[k] = s
          _ => ()
        }
      }
      result
    }
    _ => {}
  }
}

///|
/// Filter extensions to only those that are enabled.
pub(all) fn enabled_extensions(extensions : Array[Extension]) -> Array[Extension] {
  let result : Array[Extension] = []
  for ext in extensions {
    if ext.enabled {
      result.push(ext)
    }
  }
  result
}
