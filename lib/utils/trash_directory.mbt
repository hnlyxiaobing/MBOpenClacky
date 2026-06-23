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
  let buf = StringBuilder::new()
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
