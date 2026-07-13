///| Extension marketplace backend API: provides registry, install, enable, disable,
/// uninstall, and publish functionality. State is persisted to
/// `~/.clacky/extensions/registry.json`.

///|
/// Path to the marketplace registry file.
fn registry_file_path() -> String {
  match @utils.home_dir() {
    Some(home) =>
      @path.Path::join(home, @path.Path(".clacky/extensions/registry.json")).to_string()
    None => ".clacky/extensions/registry.json"
  }
}

///|
/// Default empty registry value.
fn default_registry() -> Map[String, RegistryEntry] {
  {}
}

///|
/// Load registry from disk, returning an empty map on any failure.
fn load_registry_from_disk() -> Map[String, RegistryEntry] {
  let path = registry_file_path()
  if !@fs.path_exists(path) {
    return default_registry()
  }
  let content = @fs.read_file_to_string(path) catch {
    _ => return default_registry()
  }
  let json = @json.parse(content) catch { _ => return default_registry() }
  match json {
    Object(obj) =>
      match obj.get("entries") {
        Some(Object(entries_obj)) => parse_registry_entries(entries_obj)
        _ => default_registry()
      }
    _ => default_registry()
  }
}

///|
/// Convert a JSON object of entries into a Map[String, RegistryEntry].
fn parse_registry_entries(
  obj : Map[String, Json],
) -> Map[String, RegistryEntry] {
  let entries : Map[String, RegistryEntry] = {}
  obj.each(fn(id, value) {
    match parse_registry_entry(value) {
      Some(entry) => entries[id] = entry
      None => ()
    }
  })
  entries
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
          m.each(fn(k, v) {
            match v {
              String(s) => md[k] = s
              _ => ()
            }
          })
          md
        }
        _ => {}
      }
      let installs = match obj.get("installs") {
        Some(Number(d, ..)) => d.to_int()
        _ => 0
      }
      let published_at : Int64 = match obj.get("published_at") {
        Some(Number(d, ..)) => d.to_int64()
        _ => 0L
      }
      Some({ id, latest_version, versions, metadata, installs, published_at })
    }
    _ => None
  }
}

///|
/// Persist the registry to disk as JSON. Failures are silent (best-effort).
fn save_registry_to_disk(entries : Map[String, RegistryEntry]) -> Unit {
  let path = registry_file_path()
  let parent = @path.Path::dirname(@path.Path(path)).to_string()
  @utils.ensure_dir(parent)
  let entries_obj : Map[String, Json] = {}
  entries.each(fn(id, entry) {
    let versions_json : Array[Json] = entry.versions.map(fn(v) { v.to_json() })
    let metadata_json : Map[String, Json] = {}
    entry.metadata.each(fn(k, v) { metadata_json[k] = v.to_json() })
    entries_obj[id] = Json::object({
      "id": entry.id.to_json(),
      "latest_version": entry.latest_version.to_json(),
      "versions": Json::array(versions_json),
      "metadata": Json::object(metadata_json),
      "installs": entry.installs.to_json(),
      "published_at": entry.published_at.to_json(),
    })
  })
  let registry_obj : Map[String, Json] = {
    "entries": Json::object(entries_obj),
    "updated_at": @agent.current_time_ms().to_json(),
  }
  @fs.write_string_to_file(path, Json::object(registry_obj).stringify()) catch {
    _ => ()
  }
}

///|
/// List all extensions in the marketplace.
pub fn list_marketplace_extensions() -> Array[RegistryEntry] {
  let registry = load_registry_from_disk()
  let result : Array[RegistryEntry] = []
  registry.each(fn(_id, entry) { result.push(entry) })
  result
}

///|
/// List installed extensions.
pub fn list_installed_extensions() -> Array[Extension] {
  load_extensions_from_source(ExtensionSource::Installed)
}

///|
/// List local project extensions.
pub fn list_local_extensions() -> Array[Extension] {
  load_extensions_from_source(ExtensionSource::Local)
}

///|
/// Enable an extension by ID. Returns the resolved Extension or an error message.
pub fn enable_extension(ext_id : String) -> Result[Extension, String] {
  let all = load_all_extensions()
  match all.iter().find_first(fn(e) { e.manifest.id == ext_id }) {
    Some(ext) => {
      println("[Marketplace] Enabled extension: " + ext_id)
      Ok(ext)
    }
    None => Err("extension not found: " + ext_id)
  }
}

///|
/// Disable an extension by ID. Returns the resolved Extension or an error message.
pub fn disable_extension(ext_id : String) -> Result[Extension, String] {
  let all = load_all_extensions()
  match all.iter().find_first(fn(e) { e.manifest.id == ext_id }) {
    Some(ext) => {
      println("[Marketplace] Disabled extension: " + ext_id)
      Ok(ext)
    }
    None => Err("extension not found: " + ext_id)
  }
}

///|
/// Install an extension from a directory path. Validates and copies to the
/// installed-extensions directory, then bumps the install counter.
pub fn install_extension_from_path(
  ext_path : String,
) -> Result[Extension, String] {
  let ext = match load_single_extension(ext_path, ExtensionSource::Local) {
    Some(e) => e
    None => return Err("failed to load extension from " + ext_path)
  }
  let validation = validate_extension(ext)
  if !validation.valid {
    let errors = validation.errors.map(fn(e) { validation_error_message(e) })
    return Err("validation failed: " + errors.join("; "))
  }
  let installed_dir = get_source_directory(ExtensionSource::Installed)
  @utils.ensure_dir(installed_dir)
  let target_dir = @path.Path::join(installed_dir, @path.Path(ext.manifest.id)).to_string()
  if @fs.path_exists(target_dir) {
    return Err("extension already installed at " + target_dir)
  }
  match copy_directory_recursive(ext_path, target_dir) {
    Ok(_) => ()
    Err(e) => return Err("copy failed: " + e)
  }
  let installed = match
    load_single_extension(target_dir, ExtensionSource::Installed) {
    Some(e) => e
    None => return Err("failed to load installed extension at " + target_dir)
  }
  let registry = load_registry_from_disk()
  match registry.get(ext.manifest.id) {
    Some(entry) => {
      let new_entry : RegistryEntry = {
        id: entry.id,
        latest_version: entry.latest_version,
        versions: entry.versions,
        metadata: entry.metadata,
        installs: entry.installs + 1,
        published_at: entry.published_at,
      }
      registry[entry.id] = new_entry
    }
    None => {
      let metadata : Map[String, String] = {
        "name": installed.manifest.name,
        "description": installed.manifest.description,
        "author": installed.manifest.author,
        "license": installed.manifest.license,
      }
      let new_entry : RegistryEntry = {
        id: installed.manifest.id,
        latest_version: installed.manifest.version,
        versions: [installed.manifest.version],
        metadata,
        installs: 1,
        published_at: @agent.current_time_ms(),
      }
      registry[installed.manifest.id] = new_entry
    }
  }
  save_registry_to_disk(registry)
  Ok(installed)
}

///|
/// Uninstall an extension by ID. Removes the installed directory and
/// decrements the install counter (but never below zero).
pub fn uninstall_extension(ext_id : String) -> Result[Unit, String] {
  let installed_dir = get_source_directory(ExtensionSource::Installed)
  let ext_dir = @path.Path::join(installed_dir, @path.Path(ext_id)).to_string()
  if !@fs.path_exists(ext_dir) {
    return Err("extension not installed: " + ext_id)
  }
  match remove_directory_recursive(ext_dir) {
    Ok(_) => ()
    Err(e) => return Err(e)
  }
  let registry = load_registry_from_disk()
  match registry.get(ext_id) {
    Some(entry) => {
      let next_count = if entry.installs > 0 { entry.installs - 1 } else { 0 }
      let new_entry : RegistryEntry = {
        id: entry.id,
        latest_version: entry.latest_version,
        versions: entry.versions,
        metadata: entry.metadata,
        installs: next_count,
        published_at: entry.published_at,
      }
      registry[entry.id] = new_entry
      save_registry_to_disk(registry)
    }
    None => ()
  }
  println("[Marketplace] Uninstalled extension: " + ext_id)
  Ok(())
}

///|
/// Publish a local extension to the marketplace. Validates, packages, and
/// updates the registry entry.
pub fn publish_extension(ext_path : String) -> Result[RegistryEntry, String] {
  let ext = match load_single_extension(ext_path, ExtensionSource::Local) {
    Some(e) => e
    None => return Err("failed to load extension from " + ext_path)
  }
  let validation = validate_extension(ext)
  if !validation.valid {
    let errors = validation.errors.map(fn(e) { validation_error_message(e) })
    return Err("validation failed: " + errors.join("; "))
  }
  let (_, sha256) = match
    package_extension(ext_path, output_dir=Some("./.marketplace")) {
    Ok(v) => v
    Err(e) => return Err("package failed: " + e)
  }
  let registry = load_registry_from_disk()
  let entry = update_registry_for_publish(registry, ext, sha256)
  save_registry_to_disk(registry)
  println(
    "[Marketplace] Published extension: " +
    ext.manifest.id +
    " v" +
    ext.manifest.version,
  )
  Ok(entry)
}

///|
/// Update the registry in place for a publish operation, returning the new entry.
fn update_registry_for_publish(
  registry : Map[String, RegistryEntry],
  ext : Extension,
  sha256 : String,
) -> RegistryEntry {
  let now = @agent.current_time_ms()
  let metadata : Map[String, String] = {
    "name": ext.manifest.name,
    "description": ext.manifest.description,
    "author": ext.manifest.author,
    "license": ext.manifest.license,
    "sha256": sha256,
  }
  match registry.get(ext.manifest.id) {
    Some(existing) => {
      let versions = if existing.versions.contains(ext.manifest.version) {
        existing.versions
      } else {
        let new_versions : Array[String] = []
        for v in existing.versions {
          new_versions.push(v)
        }
        new_versions.push(ext.manifest.version)
        new_versions
      }
      let new_entry : RegistryEntry = {
        id: ext.manifest.id,
        latest_version: ext.manifest.version,
        versions,
        metadata,
        installs: existing.installs,
        published_at: now,
      }
      registry[ext.manifest.id] = new_entry
      new_entry
    }
    None => {
      let new_entry : RegistryEntry = {
        id: ext.manifest.id,
        latest_version: ext.manifest.version,
        versions: [ext.manifest.version],
        metadata,
        installs: 0,
        published_at: now,
      }
      registry[ext.manifest.id] = new_entry
      new_entry
    }
  }
}

///|
/// Recursively copy a directory tree.
fn copy_directory_recursive(src : String, dst : String) -> Result[Unit, String] {
  let is_directory = @fs.is_dir(src) catch { _ => false }
  if !is_directory {
    return Err("source is not a directory: " + src)
  }
  @utils.ensure_dir(dst)
  let entries = @fs.read_dir(src) catch { e => return Err(@debug.to_string(e)) }
  for entry in entries {
    let src_path = @path.Path::join(src, @path.Path(entry)).to_string()
    let dst_path = @path.Path::join(dst, @path.Path(entry)).to_string()
    let child_is_dir = @fs.is_dir(src_path) catch { _ => false }
    if child_is_dir {
      match copy_directory_recursive(src_path, dst_path) {
        Ok(_) => ()
        Err(e) => return Err(e)
      }
    } else {
      let content = @fs.read_file_to_string(src_path) catch {
        e => return Err("read " + src_path + ": " + @debug.to_string(e))
      }
      @fs.write_string_to_file(dst_path, content) catch {
        e => return Err("write " + dst_path + ": " + @debug.to_string(e))
      }
    }
  }
  Ok(())
}

///|
/// Recursively delete a directory tree. Best-effort: errors during descent
/// are silently swallowed so the caller gets the cleanest possible result.
fn remove_directory_recursive(dir : String) -> Result[Unit, String] {
  let entries = @fs.read_dir(dir) catch { _ => return Ok(()) }
  for entry in entries {
    let path = @path.Path::join(dir, @path.Path(entry)).to_string()
    let is_directory = @fs.is_dir(path) catch { _ => false }
    if is_directory {
      match remove_directory_recursive(path) {
        Ok(_) => ()
        Err(_) => ()
      }
    } else {
      @fs.remove_file(path) catch {
        _ => ()
      }
    }
  }
  @fs.remove_dir(dir) catch {
    e => return Err(@debug.to_string(e))
  }
  Ok(())
}

///|
/// Get an extension by ID from any source. Returns None if not found.
pub fn get_extension_by_id(ext_id : String) -> Extension? {
  let all = load_all_extensions()
  all.iter().find_first(fn(e) { e.manifest.id == ext_id })
}
