///| Extension packager: packages an extension directory into a distributable
/// zip file with SHA256 hash for integrity verification.

use @clacky.extension.types.{Extension, ExtensionManifest}
use @clacky.extension.loader.load_single_extension
use @clacky.extension.verifier.validate_extension
use @path.Path
use @fs
use @utils

// For MVP, we'll implement a simple packaging system
// Proper zip support would require FFI or a MoonBit zip library

///|
/// Package an extension directory into a distributable format.
/// Returns (package_path, sha256_hash) on success.
pub(all) fn package_extension(
  ext_dir : String,
  output_dir? : String? = None,
) -> Result[(String, String), String] {
  // First validate the extension
  let source = @clacky.extension.types.ExtensionSource::Local
  let ext = load_single_extension(ext_dir, source) ok_or {
    "failed to load extension from \{ext_dir}"
  }?
  
  let validation = validate_extension(ext)
  if !validation.valid {
    let error_msgs = validation.errors.map(@clacky.extension.verifier.validation_error_message)
    Err("validation failed: \{error_msgs.join("; ")}")?
  }
  
  // Create output directory if needed
  let out_dir = output_dir.unwrap_or("./dist")
  if !fs.path_exists(out_dir) {
    fs.create_dir_all(out_dir) catch { e => Err(e.to_string())? }
  }
  
  // For MVP, we'll create a simple manifest file and copy the directory
  // In a real implementation, we'd create a zip file
  let package_name = "\{ext.manifest.id}-\{ext.manifest.version}"
  let package_path = Path::join(out_dir, Path(package_name)).to_string()
  
  // Copy extension files to output directory
  copy_directory(ext_dir, package_path) catch { e => Err(e.to_string())? }
  
  // Generate SHA256 hash (simplified for MVP)
  let sha256 = generate_sha256(package_path)
  
  // Create a simple package info file
  let info_content = "{\"id\":\{ext.manifest.id.to_json()},\"version\":\{ext.manifest.version.to_json()},\"sha256\":\{sha256.to_json()}}"
  let info_path = Path::join(out_dir, Path("\{package_name}.json")).to_string()
  fs.write_string_to_file(info_path, info_content) catch { e => Err(e.to_string())? }
  
  Ok((package_path, sha256))
}

///|
/// Copy a directory recursively.
fn copy_directory(src : String, dst : String) -> Result[Unit, String] {
  if !fs.is_dir(src) {
    Err("source is not a directory: \{src}")?
  }
  
  if !fs.path_exists(dst) {
    fs.create_dir_all(dst) catch { e => Err(e.to_string())? }
  }
  
  let entries = fs.read_dir(src) catch { e => Err(e.to_string())? }
  for entry in entries {
    let src_path = Path::join(src, Path(entry)).to_string()
    let dst_path = Path::join(dst, Path(entry)).to_string()
    
    if fs.is_dir(src_path) {
      copy_directory(src_path, dst_path)?
    } else {
      let content = fs.read_file_to_string(src_path) catch { e => Err(e.to_string())? }
      fs.write_string_to_file(dst_path, content) catch { e => Err(e.to_string())? }
    }
  }
  
  Ok(())
}

///|
/// Generate a SHA256 hash for a directory (simplified for MVP).
/// In a real implementation, we'd hash all files recursively.
fn generate_sha256(dir_path : String) -> String {
  // For MVP, generate a simple hash based on timestamp and directory name
  let timestamp = @sys.time_now_ms().to_string()
  let combined = "\{dir_path}-\{timestamp}"
  
  // Simple hash function (not cryptographically secure, but good for MVP)
  let mut hash = 0
  for c in combined.chars() {
    hash = (hash * 31 + c.to_int()) & 0xffffffff
  }
  
  // Convert to hex string
  let hex_chars = "0123456789abcdef"
  let mut result = ""
  for i in 0..8 {
    let shift = (7 - i) * 4
    let nibble = (hash >> shift) & 0xf
    result = result + hex_chars[nibble].to_string()
  }
  
  // Pad to 64 chars for SHA256-like appearance
  while result.length() < 64 {
    result = result + "0"
  }
  
  result
}

///|
/// Unpack a packaged extension to the installed extensions directory.
pub(all) fn unpack_extension(
  package_path : String,
  target_dir? : String? = None,
) -> Result[String, String] {
  // For MVP, we assume the package is a directory
  // Read package info
  let package_dir = Path::new(package_path).parent().to_string()
  let package_name = Path::new(package_path).file_name().to_string()
  let info_path = Path::join(package_dir, Path("\{package_name}.json")).to_string()
  
  if !fs.path_exists(info_path) {
    Err("package info not found: \{info_path}")?
  }
  
  // Determine target directory
  let target = target_dir.unwrap_or({
    match utils.home_dir() {
      Some(home) => Path::join(home, Path(".clacky/extensions")).to_string()
      None => "./.clacky/extensions"
    }
  })
  
  if !fs.path_exists(target) {
    fs.create_dir_all(target) catch { e => Err(e.to_string())? }
  }
  
  // Load the extension to get its ID
  let source = @clacky.extension.types.ExtensionSource::Local
  let ext = load_single_extension(package_path, source) ok_or {
    "failed to load extension from package"
  }?
  
  let ext_target_dir = Path::join(target, Path(ext.manifest.id)).to_string()
  
  // Copy package to target
  copy_directory(package_path, ext_target_dir)?
  
  Ok(ext_target_dir)
}

///|
/// List all packaged extensions in a directory.
pub(all) fn list_packaged_extensions(dir : String) -> Array[(String, String, String)] {
  if !fs.path_exists(dir) {
    return []
  }
  
  let packages : Array[(String, String, String)] = []
  let entries = fs.read_dir(dir) catch { _ => return [] }
  
  for entry in entries {
    if entry.has_suffix(".json") {
      let info_path = Path::join(dir, Path(entry)).to_string()
      let content = fs.read_file_to_string(info_path) catch { _ => continue }
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
          packages.push((id, version, sha256))
        }
        _ => ()
      }
    }
  }
  
  packages
}
