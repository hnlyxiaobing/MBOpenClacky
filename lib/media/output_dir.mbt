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
pub fn MediaOutputDir::ensure_exists(
  self : MediaOutputDir,
) -> Result[Unit, String] {
  let path = self.get_path()
  @utils.ensure_dir(path)
  // ensure_dir swallows creation errors internally; verify the result so
  // callers get an honest failure instead of a later confusing write error.
  let created = @fs.is_dir(path) catch { _ => false }
  if created {
    Ok(())
  } else {
    Err("Failed to create output directory: " + path)
  }
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
pub fn MediaOutputDir::list_files(
  self : MediaOutputDir,
  ext? : String?,
) -> Array[String] {
  let path = self.get_path()
  if !@fs.path_exists(path) {
    return []
  }
  let entries = @fs.read_dir(path) catch { _ => return [] }
  let result : Array[String] = []
  for entry in entries {
    let full_path = path + "/" + entry
    let is_f = @fs.is_file(full_path) catch { _ => false }
    if is_f {
      match ext {
        Some(Some(e)) => if entry.has_suffix(e) { result.push(full_path) }
        _ => result.push(full_path)
      }
    }
  }
  result
}

///|
/// Cleanup old files, keeping at most `max_files` entries.
/// Returns number of files removed.
///
/// Note: @fs (moonbitlang/x/fs) exposes no file modification time, so
/// "oldest" cannot be determined by mtime. Files are sorted by name;
/// with the counter-based filenames produced by generate_filename this
/// approximates creation order (media_2.png sorts before media_10.png
/// only within the same digit count - good enough for a best-effort cap).
pub fn MediaOutputDir::cleanup(self : MediaOutputDir, max_files : Int) -> Int {
  let files = self.list_files()
  let max_count = if max_files > 0 { max_files } else { 100 }
  if files.length() <= max_count {
    return 0
  }
  // Sort by filename ascending, remove from the front (oldest by
  // counter order).
  files.sort_by(fn(a, b) { a.compare(b) })
  let mut removed = 0
  let to_remove = files.length() - max_count
  let mut i = 0
  while i < to_remove {
    @fs.remove_file(files[i]) catch {
      _ => ()
    }
    removed = removed + 1
    i = i + 1
  }
  removed
}

///|
/// Get total size of output directory in bytes
pub fn MediaOutputDir::total_size(self : MediaOutputDir) -> Int64 {
  let files = self.list_files()
  let mut total = 0L
  for file in files {
    // Read raw bytes: media output is binary (png/jpg/mp4); counting
    // UTF-8 code units of a string read would be wrong and fail outright
    // on invalid UTF-8.
    let bytes = @fs.read_file_to_bytes(file) catch { _ => continue }
    total = total + bytes.length().to_int64()
  }
  total
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
