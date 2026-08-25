///| Trash directory management.
/// Move files to trash instead of deleting directly, supporting recovery.

///|
/// Trash entry metadata.
pub struct TrashEntry {
  original_path : String // Original file path
  trash_path : String // Path in trash directory
  deleted_at : String // Deletion time in ISO8601
  size_bytes : Int // File size in bytes
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend TrashEntry with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend TrashEntry with @moonbitlang/core/json.FromJson::{from_json}

///|
pub extend TrashEntry with Eq::{not_equal, equal}

///|
pub extend TrashEntry with ToJson::{to_json}

///|
/// Get the trash directory path: `~/.mbopenclacky/trash/`.
pub fn get_trash_dir() -> String {
  match config_dir() {
    Some(dir) => @path.Path::join(dir, @path.Path("trash")).to_string()
    None => ".mbopenclacky/trash"
  }
}

///|
/// Generate a filename for the trash directory.
/// Appends timestamp to original filename to avoid conflicts.
pub fn trash_filename(original_path : String, timestamp : String) -> String {
  let basename = extract_basename(original_path)
  let ts = strip_timestamp_separators(timestamp)
  if ts.is_empty() {
    basename
  } else {
    // Insert timestamp before extension
    match find_last_dot(basename) {
      Some(dot_pos) => {
        let name = basename[:dot_pos].to_owned()
        let ext = basename[dot_pos:].to_owned()
        "\{name}_\{ts}\{ext}"
      }
      None => "\{basename}_\{ts}"
    }
  }
}

///|
/// Create a trash entry with metadata.
pub fn create_trash_entry(
  original_path : String,
  timestamp? : String = "",
) -> TrashEntry {
  let ts = if timestamp.is_empty() { "1970-01-01T00:00:00Z" } else { timestamp }
  let trash_name = trash_filename(original_path, ts)
  let trash_dir = get_trash_dir()
  let trash_path = @path.Path::join(trash_dir, @path.Path(trash_name)).to_string()
  { original_path, trash_path, deleted_at: ts, size_bytes: 0 }
}

///|
/// Find entries in trash matching a filename substring.
pub fn find_in_trash(
  entries : Array[TrashEntry],
  filename : String,
) -> Array[TrashEntry] {
  let results : Array[TrashEntry] = []
  for entry in entries {
    if entry.original_path.contains(filename) ||
      entry.trash_path.contains(filename) {
      results.push(entry)
    }
  }
  results
}

///|
/// Filter entries older than max_age_days based on simple ISO8601 date prefix comparison.
pub fn expired_entries(
  entries : Array[TrashEntry],
  max_age_days : Int,
  current_date : String,
) -> Array[TrashEntry] {
  // Simple approach: compare date prefixes (YYYY-MM-DD)
  // For a rough filter, subtract max_age_days from current date's day portion
  let cutoff = compute_cutoff_date(current_date, max_age_days)
  let results : Array[TrashEntry] = []
  for entry in entries {
    let entry_date = entry.deleted_at[:10].to_owned()
    if entry_date < cutoff {
      results.push(entry)
    }
  }
  results
}

///|
/// Format a summary of trash entries.
pub fn format_trash_summary(entries : Array[TrashEntry]) -> String {
  if entries.is_empty() {
    return "Trash is empty."
  }
  let total_bytes = entries.fold(init=0, fn(acc, e) { acc + e.size_bytes })
  let count = entries.length()
  "Trash: \{count} item(s), \{total_bytes} bytes total"
}

///|
/// Extract basename from a path string.
fn extract_basename(path : String) -> String {
  let chars = path.to_array()
  let mut last_sep = -1
  for i, c in chars {
    if c == '/' || c == '\\' {
      last_sep = i
    }
  }
  if last_sep < 0 {
    path
  } else {
    path[last_sep + 1:].to_owned()
  }
}

///|
/// Find the last dot position in a filename (for extension splitting).
fn find_last_dot(name : String) -> Int? {
  let chars = name.to_array()
  let mut last_dot = -1
  for i, c in chars {
    if c == '.' {
      last_dot = i
    }
  }
  if last_dot > 0 {
    Some(last_dot)
  } else {
    None
  }
}

///|
/// Strip separators from ISO8601 timestamp for use in filenames.
fn strip_timestamp_separators(timestamp : String) -> String {
  let buf = StringBuilder()
  for c in timestamp {
    if c == '-' || c == ':' {
      continue
    } else if c == 'T' {
      buf.write_char('_')
    } else {
      buf.write_char(c)
    }
  }
  buf.to_string()
}

///|
/// Extract basename from a path string.
pub fn basename_of(path : String) -> String {
  extract_basename(path)
}

///|
/// Compute a cutoff date string by subtracting days from current date.
/// Simple implementation: only adjusts day portion, wraps month roughly.
fn compute_cutoff_date(current_date : String, days : Int) -> String {
  // Parse YYYY-MM-DD
  let date_str = current_date[:10].to_owned()
  let year = parse_int_safe(date_str[:4].to_owned()).unwrap_or(2024)
  let month = parse_int_safe(date_str[5:7].to_owned()).unwrap_or(1)
  let day = parse_int_safe(date_str[8:10].to_owned()).unwrap_or(1)
  // Simple subtraction with month/year rollback
  let mut d = day - days
  let mut m = month
  let mut y = year
  while d < 1 {
    m = m - 1
    if m < 1 {
      m = 12
      y = y - 1
    }
    // Approximate days in previous month
    let days_in_month = match m {
      2 => 28
      4 | 6 | 9 | 11 => 30
      _ => 31
    }
    d = d + days_in_month
  }
  let ms = if m < 10 { "0\{m}" } else { "\{m}" }
  let ds = if d < 10 { "0\{d}" } else { "\{d}" }
  "\{y}-\{ms}-\{ds}"
}

///|
/// Generate a per-project trash sub-directory name, mirroring the Ruby
/// reference: MD5 of the absolute project path (first 16 hex chars) plus
/// a sanitized project-name suffix.
///   "a1b2c3d4e5f6a7b8_MBOpenClacky"
pub fn generate_project_hash(project_root : String) -> String {
  let abs = @path.Path(project_root).resolve().to_string()
  let digest = @crypto.md5(@utf8.encode(abs))
  let hex = @crypto.bytes_to_hex_string(digest)
  let hash = if hex.length() > 16 { hex[:16].to_owned() } else { hex }
  let name = sanitize_project_name(extract_basename(abs))
  "\{hash}_\{name}"
}

///|
/// Sanitize a project name for use inside a trash directory path:
/// non [a-zA-Z0-9_-] chars become `_`, truncated to 20 chars.
pub fn sanitize_project_name(name : String) -> String {
  let buf = StringBuilder()
  let mut count = 0
  for c in name {
    if count >= 20 {
      break
    }
    let is_ok = (c >= 'a' && c <= 'z') ||
      (c >= 'A' && c <= 'Z') ||
      (c >= '0' && c <= '9') ||
      c == '_' ||
      c == '-'
    if is_ok {
      buf.write_char(c)
      count = count + 1
    } else {
      buf.write_char('_')
      count = count + 1
    }
  }
  buf.to_string()
}

///|
/// Per-project file trash directory, mirroring the Ruby layout:
///   ~/.mbopenclacky/trash/file-trash/<project_hash>/
pub fn project_trash_dir(project_root : String) -> String {
  let root = get_trash_dir()
  let file_trash = @path.Path::join(@path.Path(root), @path.Path("file-trash")).to_string()
  let hash = generate_project_hash(project_root)
  @path.Path::join(@path.Path(file_trash), @path.Path(hash)).to_string()
}

///|
/// Trash metadata sidecar. The schema matches the sidecar written by the
/// safe-rm shell wrapper (`<trash_file>.metadata.json`), so entries made
/// through the shell `rm` interceptor are readable here.
pub struct TrashMetadata {
  original_path : String
  trash_directory : String
  deleted_at : String
  deleted_by : String
  file_size : Int
  file_type : String
  file_mode : String
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend TrashMetadata with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend TrashMetadata with @moonbitlang/core/json.FromJson::{from_json}

///|
pub extend TrashMetadata with Eq::{not_equal, equal}

///|
pub extend TrashMetadata with ToJson::{to_json}

///|
/// Metadata sidecar path for a trash file: `<trash_file>.metadata.json`.
pub fn trash_metadata_path(trash_file : String) -> String {
  trash_file + ".metadata.json"
}

///|
/// Read and parse a trash metadata sidecar. Returns None on any failure
/// (missing file, malformed JSON) — mirroring the Ruby rescue-skip.
pub fn read_trash_metadata(metadata_path : String) -> TrashMetadata? {
  let content = @fs.read_file_to_string(metadata_path) catch {
    _ => return None
  }
  let json = @json.parse(content) catch { _ => return None }
  // Annotate the target type explicitly: without it, the `?` return type
  // makes the generic `@json.from_json` infer `Option[TrashMetadata]`,
  // which fails to parse an object payload and is silently swallowed.
  let meta : TrashMetadata = @json.from_json(json) catch { _ => return None }
  Some(meta)
}

///|
/// Absolute-path expansion used by restore matching, mirroring Ruby's
/// File.expand_path(file_path, working_dir).
pub fn expand_trash_path(file_path : String, working_dir : String) -> String {
  if file_path.has_prefix("~") {
    file_path
  } else if @path.Path(file_path).is_absolute() {
    @path.Path(file_path).normalize().to_string()
  } else {
    @path.Path::join(@path.Path(working_dir), @path.Path(file_path))
    .normalize()
    .to_string()
  }
}

///|
/// Scan a trash directory and return live entries (trash file still
/// exists), newest first, mirroring Ruby's get_deleted_files.
pub fn list_trash_entries(trash_dir : String) -> Array[TrashEntry] {
  let entries : Array[TrashEntry] = []
  let files = @fs.read_dir(trash_dir) catch { _ => return entries }
  for name in files {
    if !name.has_suffix(".metadata.json") {
      continue
    }
    let metadata_path = @path.Path::join(trash_dir, @path.Path(name)).to_string()
    // read_dir yields bare entry names; re-join to get the trash file path.
    let trash_file = metadata_path[:metadata_path.length() -
    ".metadata.json".length()].to_owned()
    if !@fs.path_exists(trash_file) {
      continue
    }
    let meta = read_trash_metadata(metadata_path)
    match meta {
      Some(m) =>
        entries.push({
          original_path: m.original_path,
          trash_path: trash_file,
          deleted_at: m.deleted_at,
          size_bytes: m.file_size,
        })
      None => continue
    }
  }
  // Newest first by deleted_at (ISO8601 sorts lexicographically).
  let sorted = entries
  sorted.sort_by(fn(a, b) { b.deleted_at.compare(a.deleted_at) })
  sorted
}

///|
/// Recursively compute the total size in bytes of a directory tree.
pub fn dir_size(path : String) -> Int {
  let is_dir = @fs.is_dir(path) catch { _ => false }
  if !is_dir {
    if @fs.path_exists(path) {
      return file_size_safe(path)
    }
    return 0
  }
  let mut total = 0
  let files = @fs.read_dir(path) catch { _ => return 0 }
  for name in files {
    let full = @path.Path::join(path, @path.Path(name)).to_string()
    let f_is_dir = @fs.is_dir(full) catch { _ => false }
    if f_is_dir {
      total = total + dir_size(full)
    } else {
      total = total + file_size_safe(full)
    }
  }
  total
}

///|
/// Best-effort single-file size; 0 on any failure.
fn file_size_safe(path : String) -> Int {
  let bytes = @fs.read_file_to_bytes(path) catch { _ => return 0 }
  bytes.length()
}
