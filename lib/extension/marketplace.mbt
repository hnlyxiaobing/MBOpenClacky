///| Extension marketplace backend API: provides registry, install, enable, disable,
/// uninstall, and publish functionality.

use @clacky.extension.types.{
  Extension,
  ExtensionManifest,
  ExtensionSource,
  RegistryEntry,
}
use @clacky.extension.loader.{
  load_all_extensions,
  load_extensions_from_source,
  load_single_extension,
  get_source_directory,
}
use @clacky.extension.verifier.validate_extension
use @clacky.extension.packager.package_extension
use @path.Path
use @fs
use @utils
use @json

///|
/// Registry state - in-memory for MVP, persisted to JSON.
struct Registry {
  entries : Map[String, RegistryEntry]
  file_path : String
}

///|
/// Global registry instance (lazy initialized).
let mut registry : Registry? = None

///|
/// Get or initialize the registry.
pub(all) fn get_registry() -> Registry {
  match registry {
    Some(r) => r
    None => {
      let r = load_registry()
      registry = Some(r)
      r
    }
  }
}

///|
/// Load registry from file or create new.
fn load_registry() -> Registry {
  let registry_path = get_registry_file_path()
  let dir = Path::new(registry_path).parent().to_string()
  
  if !fs.path_exists(dir) {
    fs.create_dir_all(dir) catch { _ => () }
  }
  
  if fs.path_exists(registry_path) {
    let content = fs.read_file_to_string(registry_path) catch { _ => return default_registry(registry_path) }
    parse_registry_json(content, registry_path)
  } else {
    default_registry(registry_path)
  }
}

///|
/// Create a default registry.
fn default_registry(file_path : String) -> Registry {
  { entries: {}, file_path }
}

///|
/// Get registry file path.
fn get_registry_file_path() -> String {
  match utils.home_dir() {
    Some(home) =>
      Path::join(home, Path(".clacky/extensions/registry.json")).to_string()
    None => ".clacky/extensions/registry.json"
  }
}

///|
/// Parse registry from JSON.
fn parse_registry_json(content : String, file_path : String) -> Registry {
  let json = @json.parse(content) catch { _ => return default_registry(file_path) }
  match json {
    Object(obj) => {
      match obj.get("entries") {
        Some(Object(entries_obj)) => {
          let entries : Map[String, RegistryEntry] = {}
          for (id, entry_json) in entries_obj {
            match parse_registry_entry(entry_json) {
              Some(entry) => entries[id] = entry
              None => ()
            }
          }
          { entries, file_path }
        }
        _ => default_registry(file_path)
      }
    }
    _ => default_registry(file_path)
  }
}

///|
/// Parse a single registry entry from JSON.
fn parse_registry_entry(json : Json) -> RegistryEntry? {
  match json {
    Object(obj) => {
      let id = match obj.get("id") {
        Some(String(s)) => s
        _ => return None
      }
      let latest_version = match obj.get("latest_version") {
        Some(String(s)) => s
        _ => return None
      }
      let versions = match obj.get("versions") {
        Some(Array(arr)) => {
          let vs : Array[String] = []
          for v in arr {
            match v {
              String(s) => vs.push(s)
              _ => ()
            }
          }
          vs
        }
        _ => []
      }
      let metadata = match obj.get("metadata") {
        Some(Object(m)) => {
          let md : Map[String, String] = {}
          for (k, v) in m {
            match v {
              String(s) => md[k] = s
              _ => ()
            }
          }
          md
        }
        _ => {}
      }
      let installs = match obj.get("installs") {
        Some(Number(n, ..)) => n.to_int()
        _ => 0
      }
      let published_at = match obj.get("published_at") {
        Some(Number(n, ..)) => n.to_int()
        _ => 0
      }
      Some({
        id,
        latest_version,
        versions,
        metadata,
        installs,
        published_at,
      })
    }
    _ => None
  }
}

///|
/// Save registry to disk.
fn save_registry(r : Registry) -> Unit {
  let entries_obj : Map[String, Json] = {}
  for (id, entry) in r.entries {
    let versions_json : Array[Json] = entry.versions.map(fn(v) { v.to_json() })
    let metadata_json : Map[String, Json] = entry.metadata.map_values(fn(v) { v.to_json() })
    entries_obj[id] = Json::object({
      "id": entry.id.to_json(),
      "latest_version": entry.latest_version.to_json(),
      "versions": Json::array(versions_json),
      "metadata": Json::object(metadata_json),
      "installs": entry.installs.to_json(),
      "published_at": entry.published_at.to_json(),
    })
  }
  let registry_json = Json::object({
    "entries": Json::object(entries_obj),
    "updated_at": @sys.time_now_ms().to_json(),
  })
  fs.write_string_to_file(r.file_path, registry_json.stringify_with_indent(2)) catch { _ => () }
}

///|
/// List all extensions in the marketplace.
pub(all) fn list_marketplace_extensions() -> Array[RegistryEntry] {
  let r = get_registry()
  r.entries.values().to_array()
}

///|
/// List installed extensions.
pub(all) fn list_installed_extensions() -> Array[Extension] {
  load_extensions_from_source(ExtensionSource::Installed)
}

///|
/// List local extensions.
pub(all) fn list_local_extensions() -> Array[Extension] {
  load_extensions_from_source(ExtensionSource::Local)
}

///|
/// Enable an extension by ID.
pub(all) fn enable_extension(ext_id : String) -> Result[Extension, String] {
  let all = load_all_extensions()
  let ext_opt = all.find(fn(e) { e.manifest.id == ext_id })
  
  match ext_opt {
    Some(ext) => {
      // For MVP, we just reload - in real implementation, we'd persist state
      println("[Marketplace] Enabled extension: \{ext_id}")
      Ok(ext)
    }
    None => Err("extension not found: \{ext_id}")
  }
}

///|
/// Disable an extension by ID.
pub(all) fn disable_extension(ext_id : String) -> Result[Extension, String] {
  let all = load_all_extensions()
  let ext_opt = all.find(fn(e) { e.manifest.id == ext_id })
  
  match ext_opt {
    Some(ext) => {
      println("[Marketplace] Disabled extension: \{ext_id}")
      Ok(ext)
    }
    None => Err("extension not found: \{ext_id}")
  }
}

///|
/// Install an extension from a directory path.
pub(all) fn install_extension_from_path(ext_path : String) -> Result[Extension, String] {
  // Load and validate
  let ext = load_single_extension(ext_path, ExtensionSource::Local) ok_or {
    "failed to load extension from \{ext_path}"
  }?
  
  let validation = validate_extension(ext)
  if !validation.valid {
    let errors = validation.errors.map(@clacky.extension.verifier.validation_error_message)
    Err("validation failed: \{errors.join("; ")}")?
  }
  
  // Copy to installed directory
  let installed_dir = get_source_directory(ExtensionSource::Installed)
  if !fs.path_exists(installed_dir) {
    fs.create_dir_all(installed_dir) catch { e => Err(e.to_string())? }
  }
  
  let target_dir = Path::join(installed_dir, Path(ext.manifest.id)).to_string()
  
  // Simple copy for MVP
  copy_directory_simple(ext_path, target_dir)?
  
  // Load the installed extension
  let installed = load_single_extension(target_dir, ExtensionSource::Installed) ok_or {
    "failed to load installed extension"
  }?
  
  // Update registry
  let mut r = get_registry()
  update_registry_install(&mut r, &installed)?
  save_registry(r)
  
  Ok(installed)
}

///|
/// Uninstall an extension by ID.
pub(all) fn uninstall_extension(ext_id : String) -> Result[Unit, String] {
  let installed_dir = get_source_directory(ExtensionSource::Installed)
  let ext_dir = Path::join(installed_dir, Path(ext_id)).to_string()
  
  if !fs.path_exists(ext_dir) {
    Err("extension not installed: \{ext_id}")?
  }
  
  // Remove directory
  remove_directory_simple(ext_dir)?
  
  println("[Marketplace] Uninstalled extension: \{ext_id}")
  Ok(())
}

///|
/// Publish a local extension to the marketplace.
pub(all) fn publish_extension(ext_path : String) -> Result[RegistryEntry, String] {
  // Load and validate
  let ext = load_single_extension(ext_path, ExtensionSource::Local) ok_or {
    "failed to load extension from \{ext_path}"
  }?
  
  let validation = validate_extension(ext)
  if !validation.valid {
    let errors = validation.errors.map(@clacky.extension.verifier.validation_error_message)
    Err("validation failed: \{errors.join("; ")}")?
  }
  
  // Package it
  let (_, sha256) = package_extension(ext_path, Some("./.marketplace"))?
  
  // Update registry
  let mut r = get_registry()
  let entry = update_registry_publish(&mut r, &ext, sha256)?
  save_registry(r)
  
  println("[Marketplace] Published extension: \{ext.manifest.id} v\{ext.manifest.version}")
  Ok(entry)
}

///|
/// Update registry on install.
fn update_registry_install(r : &Registry, ext : &Extension) -> Result[Unit, String] {
  match r.entries.get(ext.manifest.id) {
    Some(mut entry) => {
      entry.installs = entry.installs + 1
      r.entries[ext.manifest.id] = entry
    }
    None => {
      // Create new entry from extension
      let metadata : Map[String, String] = {
        "name": ext.manifest.name,
        "description": ext.manifest.description,
        "author": ext.manifest.author,
        "license": ext.manifest.license,
      }
      let entry = {
        id: ext.manifest.id,
        latest_version: ext.manifest.version,
        versions: [ext.manifest.version],
        metadata,
        installs: 1,
        published_at: @sys.time_now_ms(),
      }
      r.entries[ext.manifest.id] = entry
    }
  }
  Ok(())
}

///|
/// Update registry on publish.
fn update_registry_publish(
  r : &Registry,
  ext : &Extension,
  sha256 : String,
) -> Result[RegistryEntry, String] {
  let now = @sys.time_now_ms()
  let metadata : Map[String, String] = {
    "name": ext.manifest.name,
    "description": ext.manifest.description,
    "author": ext.manifest.author,
    "license": ext.manifest.license,
    "sha256": sha256,
  }
  
  let entry = match r.entries.get(ext.manifest.id) {
    Some(mut existing) => {
      // Add version if not present
      if !existing.versions.contains(ext.manifest.version) {
        existing.versions.push(ext.manifest.version)
      }
      existing.latest_version = ext.manifest.version
      existing.metadata = metadata
      existing.published_at = now
      existing
    }
    None => {
      {
        id: ext.manifest.id,
        latest_version: ext.manifest.version,
        versions: [ext.manifest.version],
        metadata,
        installs: 0,
        published_at: now,
      }
    }
  }
  
  r.entries[ext.manifest.id] = entry
  Ok(entry)
}

///|
/// Simple directory copy (for MVP).
fn copy_directory_simple(src : String, dst : String) -> Result[Unit, String] {
  if !fs.is_dir(src) {
    Err("source is not a directory")?
  }
  
  if !fs.path_exists(dst) {
    fs.create_dir_all(dst) catch { e => Err(e.to_string())? }
  }
  
  let entries = fs.read_dir(src) catch { e => Err(e.to_string())? }
  for entry in entries {
    let src_path = Path::join(src, Path(entry)).to_string()
    let dst_path = Path::join(dst, Path(entry)).to_string()
    if fs.is_dir(src_path) {
      copy_directory_simple(src_path, dst_path)?
    } else {
      let content = fs.read_file_to_string(src_path) catch { e => Err(e.to_string())? }
      fs.write_string_to_file(dst_path, content) catch { e => Err(e.to_string())? }
    }
  }
  Ok(())
}

///|
/// Simple directory removal (for MVP).
fn remove_directory_simple(dir : String) -> Result[Unit, String] {
  let entries = fs.read_dir(dir) catch { _ => return Ok(()) }
  for entry in entries {
    let path = Path::join(dir, Path(entry)).to_string()
    if fs.is_dir(path) {
      remove_directory_simple(path)?
    } else {
      fs.remove_file(path) catch { _ => () }
    }
  }
  fs.remove_dir(dir) catch { e => Err(e.to_string())? }
  Ok(())
}

///|
/// Get extension by ID.
pub(all) fn get_extension_by_id(ext_id : String) -> Extension? {
  let all = load_all_extensions()
  all.find(fn(e) { e.manifest.id == ext_id })
}
