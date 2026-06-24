///|
/// Media output directory manager
pub(all) struct MediaOutputDir {
  base_path : String
  prefix : String
  mut counter : Int
}

///|
/// Create a new MediaOutputDir with default prefix "media"
pub fn MediaOutputDir::new(base_path : String) -> MediaOutputDir {
  { base_path, prefix: "media", counter: 0 }
}

///|
/// Create with custom prefix
pub fn MediaOutputDir::with_prefix(
  base_path : String,
  prefix : String,
) -> MediaOutputDir {
  { base_path, prefix, counter: 0 }
}

///|
/// Get the full output directory path
pub fn MediaOutputDir::get_path(self : MediaOutputDir) -> String {
  "\{self.base_path}/\{self.prefix}"
}

///|
/// Ensure the output directory exists (creates if needed)
/// TODO: FFI needed for filesystem operations
pub fn MediaOutputDir::ensure_exists(
  self : MediaOutputDir,
) -> Result[Unit, String] {
  let _ = self
  // TODO: FFI needed for actual filesystem mkdir
  Ok(())
}

///|
/// Generate a unique filename with counter-based naming
pub fn MediaOutputDir::generate_filename(
  self : MediaOutputDir,
  prefix : String,
  ext : String,
) -> String {
  self.counter = self.counter + 1
  let sanitized = sanitize_filename(prefix)
  "\{sanitized}_\{self.counter}.\{ext}"
}

///|
/// Generate filename with subdirectory
pub fn MediaOutputDir::generate_path(
  self : MediaOutputDir,
  sub_dir : String,
  prefix : String,
  ext : String,
) -> String {
  let filename = self.generate_filename(prefix, ext)
  "\{self.get_path()}/\{sub_dir}/\{filename}"
}

///|
/// List files in output directory
/// TODO: FFI needed for filesystem operations
pub fn MediaOutputDir::list_files(
  self : MediaOutputDir,
  ext? : String?,
) -> Array[String] {
  let _ = ext
  let _ = self
  // TODO: FFI needed for actual filesystem listing
  []
}

///|
/// Cleanup old files beyond max age
/// TODO: FFI needed for filesystem operations
pub fn MediaOutputDir::cleanup(
  self : MediaOutputDir,
  max_age_hours : Int,
) -> Int {
  let _ = max_age_hours
  let _ = self
  // TODO: FFI needed for actual filesystem cleanup
  0
}

///|
/// Get total size of output directory
/// TODO: FFI needed for filesystem operations
pub fn MediaOutputDir::total_size(self : MediaOutputDir) -> Int64 {
  let _ = self
  // TODO: FFI needed for actual filesystem size calculation
  0L
}

///|
/// Sanitize a filename by replacing illegal characters with underscores
pub fn sanitize_filename(name : String) -> String {
  let illegal = ['/', '\\', ':', '*', '?', '"', '<', '>', '|', ' ']
  let mut result : String = ""
  for ch in name.iter() {
    if illegal.iter().any(fn(c) { c == ch }) {
      result = result + "_"
    } else {
      result = result + ch.to_string()
    }
  }
  if result.length() == 0 {
    "unnamed"
  } else {
    result
  }
}
