///| Extension packager: packages an extension directory into a distributable
/// package (with checksum) for installation and publish flows.
///
/// MVP note: the package is a directory copy plus a `package.json` sidecar
/// containing the SHA256-like checksum. A real ZIP-based distribution can be
/// layered on top later without changing the public API.

///|
/// Package an extension directory into a distributable format.
/// Returns (package_dir, sha256_hash) on success.
pub fn package_extension(
  ext_dir : String,
  output_dir? : String? = None,
) -> Result[(String, String), String] {
  // Treat the source as a local extension for validation.
  let ext = match load_single_extension(ext_dir, ExtensionSource::Local) {
    Some(e) => e
    None => return Err("failed to load extension from " + ext_dir)
  }
  let validation = validate_extension(ext)
  if !validation.valid {
    let error_msgs = validation.errors.map(fn(e) { validation_error_message(e) })
    return Err("validation failed: " + error_msgs.join("; "))
  }
  // Resolve and create the output directory.
  let out_dir = match output_dir {
    Some(d) => d
    None => "./dist"
  }
  @utils.ensure_dir(out_dir)
  // Compute destination path.
  let package_name = ext.manifest.id + "-" + ext.manifest.version
  let package_path = @path.Path::join(out_dir, @path.Path(package_name)).to_string()
  // Avoid clobbering an existing package.
  if @fs.path_exists(package_path) {
    return Err("package already exists at " + package_path)
  }
  @utils.ensure_dir(package_path)
  // Copy all files from the source into the package dir.
  match copy_directory(ext_dir, package_path) {
    Ok(_) => ()
    Err(e) => return Err("failed to copy extension: " + e)
  }
  // Compute checksum over the manifest id+version+root_path for traceability.
  let sha256 = compute_checksum(ext.manifest.id, ext.manifest.version, ext_dir)
  // Write sidecar metadata.
  let info_obj : Map[String, Json] = {}
  info_obj["id"] = ext.manifest.id.to_json()
  info_obj["version"] = ext.manifest.version.to_json()
  info_obj["sha256"] = sha256.to_json()
  info_obj["root_path"] = ext_dir.to_json()
  info_obj["packaged_at"] = @agent.current_time_ms().to_json()
  let info_path = @path.Path::join(out_dir, @path.Path(package_name + ".json")).to_string()
  @fs.write_string_to_file(info_path, Json::object(info_obj).stringify()) catch {
    e => return Err("failed to write package info: " + @debug.to_string(e))
  }
  Ok((package_path, sha256))
}

///|
/// Recursively copy a directory tree.
fn copy_directory(src : String, dst : String) -> Result[Unit, String] {
  let src_is_dir = @fs.is_dir(src) catch { _ => false }
  if !src_is_dir {
    return Err("source is not a directory: " + src)
  }
  @utils.ensure_dir(dst)
  let entries = @fs.read_dir(src) catch { e => return Err(@debug.to_string(e)) }
  for entry in entries {
    let src_path = @path.Path::join(src, @path.Path(entry)).to_string()
    let dst_path = @path.Path::join(dst, @path.Path(entry)).to_string()
    let is_directory = @fs.is_dir(src_path) catch { _ => false }
    if is_directory {
      match copy_directory(src_path, dst_path) {
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
/// Compute a stable 16-character hex checksum over the inputs.
/// Note: this is a non-cryptographic FNV-1a 64-bit hash formatted as 16 hex chars.
/// Real SHA256 support can replace this without changing the public signature.
fn compute_checksum(id : String, version : String, path : String) -> String {
  let mut hash : Int64 = 0xcbf29ce484222325L
  for c in id + ":" + version + ":" + path {
    hash = (hash ^ c.to_int().to_int64()) * 0x100000001b3L
  }
  // Format as 16 hex chars (lowercase).
  let hex_chars = "0123456789abcdef"
  let chars : Array[Char] = []
  let mut value = hash
  for _i = 0; _i < 16; _i = _i + 1 {
    let nibble = (value & 0xFL).to_int()
    chars.push(Int::unsafe_to_char(hex_chars[nibble].to_int()))
    value = value >> 4
  }
  chars.iter().fold(init="", fn(acc, c) { acc + c.to_string() })
}

///|
/// Unpack a packaged extension into the installed-extensions directory.
pub fn unpack_extension(
  package_path : String,
  target_dir? : String? = None,
) -> Result[String, String] {
  // Determine target directory: ~/.clacky/extensions by default.
  let target = match target_dir {
    Some(d) => d
    None =>
      match @utils.home_dir() {
        Some(home) =>
          @path.Path::join(home, @path.Path(".clacky/extensions")).to_string()
        None => "./.clacky/extensions"
      }
  }
  // Load the package to discover its id.
  let ext = match load_single_extension(package_path, ExtensionSource::Local) {
    Some(e) => e
    None => return Err("failed to load extension from package " + package_path)
  }
  let ext_target_dir = @path.Path::join(target, @path.Path(ext.manifest.id)).to_string()
  if @fs.path_exists(ext_target_dir) {
    return Err("extension already installed at " + ext_target_dir)
  }
  @utils.ensure_dir(ext_target_dir)
  match copy_directory(package_path, ext_target_dir) {
    Ok(_) => Ok(ext_target_dir)
    Err(e) => Err(e)
  }
}

///|
/// List all packaged extensions in a directory.
/// Each entry is (id, version, sha256, info_path).
pub fn list_packaged_extensions(
  dir : String,
) -> Array[(String, String, String, String)] {
  if !@fs.path_exists(dir) {
    return []
  }
  let packages : Array[(String, String, String, String)] = []
  let entries = @fs.read_dir(dir) catch { _ => return [] }
  for entry in entries {
    if !entry.has_suffix(".json") {
      continue
    }
    let info_path = @path.Path::join(dir, @path.Path(entry)).to_string()
    let content = @fs.read_file_to_string(info_path) catch { _ => continue }
    let json = @json.parse(content) catch { _ => continue }
    match json {
      Object(obj) => {
        let id = match obj.get("id") {
          Some(String(s)) => s
          _ => continue
        }
        let version = match obj.get("version") {
          Some(String(s)) => s
          _ => continue
        }
        let sha256 = match obj.get("sha256") {
          Some(String(s)) => s
          _ => continue
        }
        packages.push((id, version, sha256, info_path))
      }
      _ => ()
    }
  }
  packages
}
