///|
/// TrashManager: manage deleted files in the AI trash.
///
/// Provides actions to list, restore, check status, and permanently
/// delete files that were safely moved to the trash directory by the
/// terminal tool. The trash directory is located at
/// ~/.mbopenclacky/trash/file-trash/<project_hash>/.
///
/// Metadata for each deleted file is stored as <trash_file>.metadata.json
/// containing: original_path, deleted_at, file_size, file_type, file_mode.
/// Behavior and message formats mirror the Ruby reference implementation
/// (lib/clacky/tools/trash_manager.rb).
pub(all) struct TrashManager {} derive(Eq, Debug)

///|
pub extend TrashManager with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend TrashManager with Eq::{not_equal, equal}

///|
impl Tool for TrashManager with fn name(_) -> String {
  "trash_manager"
}

///|
impl Tool for TrashManager with fn description(_) -> String {
  "Manage deleted files in the AI trash - list, restore, or permanently delete files"
}

///|
impl Tool for TrashManager with fn parameters(_) -> Json {
  Json::object({
    "type": "object".to_json(),
    "properties": Json::object({
      "action": Json::object({
        "type": "string".to_json(),
        "description": "Action to perform: 'list' (show deleted files), 'restore' (restore a file), 'status' (show trash summary), 'empty' (permanently delete old files), 'help' (show usage)".to_json(),
        "enum": [
          "list".to_json(),
          "restore".to_json(),
          "status".to_json(),
          "empty".to_json(),
          "help".to_json(),
        ],
      }),
      "file_path": Json::object({
        "type": "string".to_json(),
        "description": "Original file path to restore (required for 'restore' action)".to_json(),
      }),
      "days_old": Json::object({
        "type": "integer".to_json(),
        "description": "For 'empty' action: permanently delete files older than this many days (default: 7)".to_json(),
      }),
    }),
    "required": ["action".to_json()],
  })
}

///|
impl Tool for TrashManager with fn category(_) -> ToolCategory {
  FileSystem
}

///|
impl Tool for TrashManager with fn execute(_, args : Map[String, Json]) -> ToolResult {
  let action = match args.get("action") {
    Some(String(a)) => a.to_lower()
    _ => ""
  }
  let project_root = @utils.current_dir()
  let trash_dir = @utils.project_trash_dir(project_root)

  let dir_exists = @fs.is_dir(trash_dir) catch { _ => false }
  if !dir_exists {
    return ToolResult::error(
      "No trash directory found. No files have been safely deleted yet.",
    )
  }

  match action {
    "list" => list_deleted_files(trash_dir, project_root)
    "restore" => {
      let file_path = match args.get("file_path") {
        Some(String(p)) => p
        _ => ""
      }
      if file_path.length() == 0 {
        ToolResult::error("file_path is required for restore action")
      } else {
        restore_file(trash_dir, file_path, project_root)
      }
    }
    "status" => show_trash_status(trash_dir, project_root)
    "empty" => {
      let days_old = match args.get("days_old") {
        Some(Number(n, ..)) => n.to_int()
        _ => 7
      }
      empty_trash(trash_dir, days_old, project_root)
    }
    "help" => ToolResult::success(trash_help_text())
    _ => ToolResult::error("Unknown action: \{action}")
  }
}

///|
impl Tool for TrashManager with fn format_call(_, args : Map[String, Json]) -> String {
  let action = match args.get("action") {
    Some(String(a)) => a
    _ => "unknown"
  }
  "TrashManager(\{action})"
}

///|
impl Tool for TrashManager with fn format_result(_, result : ToolResult) -> String {
  if result.is_error {
    result.content
  } else {
    let content = result.content
    if content.length() > 200 {
      content[:200].to_owned() + "..."
    } else {
      content
    }
  }
}

///|
impl Tool for TrashManager with fn to_function_definition(self) -> FunctionDefinition {
  FunctionDefinition::new(self.name(), self.description(), self.parameters())
}

// ── Actions ────────────────────────────────────────────────────────────────

///|
/// list: show all deleted files, newest first.
fn list_deleted_files(trash_dir : String, _project_root : String) -> ToolResult {
  let deleted_files = @utils.list_trash_entries(trash_dir)

  if deleted_files.is_empty() {
    return ToolResult::success("🗑️  Trash is empty")
  }

  let file_list : Array[String] = []
  for index, file in deleted_files {
    let size_info = if file.size_bytes > 0 {
      " (\{format_bytes(file.size_bytes)})"
    } else {
      ""
    }
    file_list.push(
      "\{index + 1}. \{file.original_path}\{size_info}\n   Deleted: \{format_time(file.deleted_at)}",
    )
  }

  ToolResult::success(
    "🗑️  Deleted Files:\n\n\{join_trash_lines(file_list, "\n\n")}\n\n💡 Use trash_manager with action='restore' and file_path='<path>' to restore a file",
  )
}

///|
/// restore: move a file back from trash to its original location.
async fn restore_file(
  trash_dir : String,
  file_path : String,
  project_root : String,
) -> ToolResult {
  let deleted_files = @utils.list_trash_entries(trash_dir)
  let expanded_path = @utils.expand_trash_path(file_path, project_root)

  let mut target_file : @utils.TrashEntry? = None
  for f in deleted_files {
    if f.original_path == expanded_path {
      target_file = Some(f)
      break
    }
  }

  match target_file {
    None => {
      // Suggest files with the same basename (mirroring Ruby).
      let wanted_base = @utils.basename_of(file_path)
      let similar : Array[String] = []
      for f in deleted_files {
        if @utils.basename_of(f.original_path) == wanted_base {
          similar.push(f.original_path)
        }
      }
      if similar.length() > 0 {
        let suggestions = join_trash_lines(similar, "\n  - ")
        ToolResult::error(
          "File not found in trash: \{file_path}\n\nDid you mean one of these?\n  - \{suggestions}",
        )
      } else {
        ToolResult::error(
          "File not found in trash: \{file_path}\n\nUse trash_manager with action='list' to see available files.",
        )
      }
    }
    Some(target) => {
      if @fs.path_exists(expanded_path) {
        return ToolResult::error(
          "Cannot restore: file already exists at \{file_path}",
        )
      }
      let dirname = dirname_of(expanded_path)
      ensure_dir(dirname)
      let code = move_path(target.trash_path, expanded_path)
      if code != 0 {
        return ToolResult::error(
          "❌ Failed to restore file: mv failed with exit code \{code}",
        )
      }
      let _ = @fs.remove_file(@utils.trash_metadata_path(target.trash_path)) catch {
        _ => ()
      }
      ToolResult::success("✅ Successfully restored: \{file_path}")
    }
  }
}

///|
/// status: show trash summary with statistics grouped by file type.
fn show_trash_status(trash_dir : String, _project_root : String) -> ToolResult {
  let deleted_files = @utils.list_trash_entries(trash_dir)
  let mut total_size = 0
  for f in deleted_files {
    total_size = total_size + f.size_bytes
  }

  if deleted_files.is_empty() {
    return ToolResult::success("🗑️  Trash is empty")
  }

  // Group by file type (extension).
  let type_keys : Array[String] = []
  let type_sizes : Map[String, Int] = Map([])
  let type_counts : Map[String, Int] = Map([])
  for f in deleted_files {
    let ext = file_type_of(f.original_path)
    if !type_sizes.contains(ext) {
      type_keys.push(ext)
    }
    type_sizes[ext] = type_sizes.get_or_default(ext, 0) + f.size_bytes
    type_counts[ext] = type_counts.get_or_default(ext, 0) + 1
  }
  let type_summary : Array[String] = []
  for ext in type_keys {
    type_summary.push(
      "  \{ext}: \{type_counts[ext]} files (\{format_bytes(type_sizes[ext])})",
    )
  }

  let recent_files : Array[String] = []
  let recent_count = if deleted_files.length() < 3 {
    deleted_files.length()
  } else {
    3
  }
  for i = 0; i < recent_count; i = i + 1 {
    let f = deleted_files[i]
    recent_files.push(
      "  - \{@utils.basename_of(f.original_path)} (\{format_time(f.deleted_at)})",
    )
  }

  let message : Array[String] = [
    "🗑️  Trash Status:",
    "  Files: \{deleted_files.length()}",
    "  Total size: \{format_bytes(total_size)}",
    "  Location: \{trash_dir}",
    "",
    "📊 By file type:",
  ]
  for t in type_summary {
    message.push(t)
  }
  message.push("")
  message.push("📅 Recently deleted:")
  for r in recent_files {
    message.push(r)
  }

  ToolResult::success(join_trash_lines(message, "\n"))
}

///|
/// empty: permanently delete files older than `days_old` days.
async fn empty_trash(
  trash_dir : String,
  days_old : Int,
  _project_root : String,
) -> ToolResult {
  let deleted_files = @utils.list_trash_entries(trash_dir)
  let cutoff_sec = @env.now().reinterpret_as_int64() / 1000 -
    (days_old * 24 * 60 * 60).to_int64()

  let old_files : Array[@utils.TrashEntry] = []
  for f in deleted_files {
    match iso_to_unix_sec(f.deleted_at) {
      Some(sec) => if sec < cutoff_sec { old_files.push(f) }
      None => continue
    }
  }

  if old_files.is_empty() {
    return ToolResult::success(
      "🗑️  No files older than \{days_old} days found in trash",
    )
  }

  let mut deleted_count = 0
  let mut freed_size = 0
  for f in old_files {
    if @fs.path_exists(f.trash_path) {
      let is_dir = @fs.is_dir(f.trash_path) catch { _ => false }
      if is_dir {
        freed_size = freed_size + @utils.dir_size(f.trash_path)
        let _ = remove_path(f.trash_path) catch { _ => () }
      } else {
        freed_size = freed_size + f.size_bytes
        let _ = @fs.remove_file(f.trash_path) catch { _ => () }
      }
      deleted_count = deleted_count + 1
    }
    let _ = @fs.remove_file(@utils.trash_metadata_path(f.trash_path)) catch {
      _ => ()
    }
  }

  ToolResult::success(
    "🗑️  Permanently deleted \{deleted_count} files older than \{days_old} days\n💾 Freed up \{format_bytes(freed_size)} of disk space",
  )
}

///|
fn trash_help_text() -> String {
  let lines : Array[String] = [
    "🗑️ Trash Manager Help", "", "The `terminal` tool automatically moves deleted files to a trash directory",
    "instead of permanently deleting them. This tool helps you manage those files.",
    "", "Available actions:", "", "📋 list - Show all deleted files", "  Example: trash_manager(action=\"list\")",
    "", "♻️  restore - Restore a deleted file to its original location", "  Example: trash_manager(action=\"restore\", file_path=\"path/to/file.txt\")",
    "", "📊 status - Show trash summary with statistics", "  Example: trash_manager(action=\"status\")",
    "", "🗑️  empty - Permanently delete files older than N days (default: 7)",
    "  Example: trash_manager(action=\"empty\", days_old=7)", "", "❓ help - Show this help message",
    "", "💡 Tips:", "- Use 'list' to see what files are in trash", "- Use 'restore' to get back accidentally deleted files",
    "- Use 'empty' periodically to free up disk space",
  ]
  join_trash_lines(lines, "\n")
}

// ── Formatting helpers ─────────────────────────────────────────────────────

///|
/// Format a byte count into a human-readable string, mirroring Ruby's
/// format_bytes: "0 B", "512 B", "1.0 KB", "1.5 MB" (round to 2, trailing
/// zeros trimmed to one decimal place).
pub fn format_bytes(bytes : Int) -> String {
  if bytes == 0 {
    return "0 B"
  }
  let units = ["B", "KB", "MB", "GB"]
  let mut size = bytes.to_double()
  let mut unit_index = 0
  while size >= 1024.0 && unit_index < units.length() - 1 {
    size = size / 1024.0
    unit_index = unit_index + 1
  }
  if unit_index == 0 {
    return "\{bytes} B"
  }
  let scaled = (size * 100.0).round().to_int()
  let int_part = scaled / 100
  let frac_part = scaled % 100
  if frac_part == 0 {
    "\{int_part}.0 \{units[unit_index]}"
  } else if frac_part % 10 == 0 {
    "\{int_part}.\{frac_part / 10} \{units[unit_index]}"
  } else if frac_part < 10 {
    "\{int_part}.0\{frac_part} \{units[unit_index]}"
  } else {
    "\{int_part}.\{frac_part} \{units[unit_index]}"
  }
}

///|
/// Format a deleted_at timestamp like Ruby's format_time:
/// today → "HH:MM", yesterday → "yesterday HH:MM", this year → "MM/DD HH:MM",
/// older → "YYYY/MM/DD". Falls back to the raw string on parse failure.
fn format_time(time_str : String) -> String {
  match parse_iso_parts(time_str) {
    None => time_str
    Some((y, mo, d, h, mi)) => {
      let now = utc_now_parts()
      if y == now.0 && mo == now.1 && d == now.2 {
        pad2(h) + ":" + pad2(mi)
      } else {
        let yesterday = utc_yesterday_parts()
        if y == yesterday.0 && mo == yesterday.1 && d == yesterday.2 {
          "yesterday " + pad2(h) + ":" + pad2(mi)
        } else if y == now.0 {
          pad2(mo) + "/" + pad2(d) + " " + pad2(h) + ":" + pad2(mi)
        } else {
          "\{y}/\{pad2(mo)}/\{pad2(d)}"
        }
      }
    }
  }
}

///|
fn parse_iso_parts(iso : String) -> (Int, Int, Int, Int, Int)? {
  // Accept "YYYY-MM-DDTHH:MM:SS..." (any zone suffix).
  if iso.length() < 16 {
    return None
  }
  let year = @string.parse_int(iso[:4].to_owned()) catch { _ => return None }
  if iso[4:5].to_owned() != "-" {
    return None
  }
  let month = @string.parse_int(iso[5:7].to_owned()) catch { _ => return None }
  if iso[7:8].to_owned() != "-" {
    return None
  }
  let day = @string.parse_int(iso[8:10].to_owned()) catch { _ => return None }
  let hour = @string.parse_int(iso[11:13].to_owned()) catch { _ => return None }
  let minute = @string.parse_int(iso[14:16].to_owned()) catch {
    _ => return None
  }
  Some((year, month, day, hour, minute))
}

///|
/// Parse an ISO8601 timestamp into Unix epoch seconds. Returns None on
/// failure (mirroring Ruby's Time.parse rescue fallback).
fn iso_to_unix_sec(iso : String) -> Int64? {
  // PlainDateTime has no zone support: strip trailing "Z" and any
  // fractional-second part before parsing (mirrors Ruby's Time.parse,
  // which accepts "2020-01-01T00:00:00Z").
  let stripped = strip_iso_suffix(iso)
  let dt = (@string.FromStr::from_str(stripped) : @time.PlainDateTime) catch {
    _ => return None
  }
  Some(dt.to_unix_second())
}

///|
fn strip_iso_suffix(iso : String) -> String {
  let no_z = if iso.has_suffix("Z") {
    iso[:iso.length() - 1].to_owned()
  } else {
    iso
  }
  let parts = no_z.split(".").collect()
  parts[0].to_owned()
}

///|
fn utc_now_parts() -> (Int, Int, Int) {
  let sec = @env.now().reinterpret_as_int64() / 1000
  let dt = @time.PlainDateTime::from_unix_second(sec, 0, @time.utc_offset) catch {
    _ => return (1970, 1, 1)
  }
  (dt.year(), dt.month(), dt.day())
}

///|
fn utc_yesterday_parts() -> (Int, Int, Int) {
  let sec = @env.now().reinterpret_as_int64() / 1000
  let dt = @time.PlainDateTime::from_unix_second(
    sec - (24 * 60 * 60).to_int64(),
    0,
    @time.utc_offset,
  ) catch {
    _ => return (1970, 1, 1)
  }
  (dt.year(), dt.month(), dt.day())
}

///|
fn pad2(n : Int) -> String {
  if n < 10 {
    "0\{n}"
  } else {
    "\{n}"
  }
}

///|
/// File-type label for grouping: extension including dot, or "no extension".
fn file_type_of(path : String) -> String {
  let base = @utils.basename_of(path)
  let chars = base.to_array()
  let mut last_dot = -1
  for i, c in chars {
    if c == '.' {
      last_dot = i
    }
  }
  if last_dot > 0 && last_dot < base.length() - 1 {
    base[last_dot:].to_owned()
  } else {
    "no extension"
  }
}

///|
fn dirname_of(path : String) -> String {
  let chars = path.to_array()
  let mut last_sep = -1
  for i, c in chars {
    if c == '/' || c == '\\' {
      last_sep = i
    }
  }
  if last_sep < 0 {
    "."
  } else {
    path[:last_sep].to_owned()
  }
}

///|
/// Create a directory (and parents), mirroring Ruby's FileUtils.mkdir_p.
async fn ensure_dir(path : String) -> Unit {
  let _ = @process.run(
    if shell_is_windows() {
      "mkdir"
    } else {
      "mkdir"
    },
    if shell_is_windows() {
      [path]
    } else {
      ["-p", path]
    },
    no_console_window=true,
  ) catch {
    _ => -1
  }
}

///|
/// Move a file or directory; returns the child exit code (0 = success).
async fn move_path(src : String, dst : String) -> Int {
  if shell_is_windows() {
    @process.run("move", ["/Y", src, dst], no_console_window=true) catch {
      _ => -1
    }
  } else {
    @process.run("mv", [src, dst], no_console_window=true) catch {
      _ => -1
    }
  }
}

///|
/// Recursively remove a path (permanent delete, used only by `empty`).
async fn remove_path(path : String) -> Unit {
  if shell_is_windows() {
    let _ = @process.run("rmdir", ["/s", "/q", path], no_console_window=true) catch {
      _ => -1
    }
  } else {
    let _ = @process.run("rm", ["-rf", path], no_console_window=true) catch {
      _ => -1
    }
  }
}

///|
/// Join an array of strings with a separator (local helper).
fn join_trash_lines(parts : Array[String], sep : String) -> String {
  if parts.length() == 0 {
    return ""
  }
  let mut result = parts[0]
  let mut i = 1
  while i < parts.length() {
    result = result + sep + parts[i]
    i = i + 1
  }
  result
}
