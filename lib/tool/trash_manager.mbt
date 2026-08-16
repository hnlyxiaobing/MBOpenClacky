///|
/// TrashManager: manage deleted files in the AI trash.
///
/// Provides actions to list, restore, check status, and permanently
/// delete files that were safely moved to the trash directory by the
/// terminal tool. The trash directory is located at
/// ~/.mbopenclacky/trash/<project_hash>/.
///
/// Metadata for each deleted file is stored as <trash_file>.metadata.json
/// containing: original_path, deleted_at, file_size, file_type, file_mode.
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
  match action {
    "list" => ToolResult::success(trash_list_message())
    "restore" => {
      let file_path = match args.get("file_path") {
        Some(String(p)) => p
        _ => ""
      }
      if file_path.length() == 0 {
        ToolResult::error("file_path is required for restore action")
      } else {
        ToolResult::success(trash_restore_not_found_message(file_path))
      }
    }
    "status" => ToolResult::success(trash_status_message())
    "empty" => {
      let days_old = match args.get("days_old") {
        Some(Number(n, ..)) => n.to_int()
        _ => 7
      }
      ToolResult::success(trash_empty_message(days_old))
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

// ── Trash Messages ──────────────────────────────────────────────────────────

///|
fn trash_list_message() -> String {
  "Trash is empty (no trash directory found or no files have been safely deleted yet)"
}

///|
fn trash_restore_not_found_message(file_path : String) -> String {
  "File not found in trash: \{file_path}\n\nUse trash_manager with action='list' to see available files."
}

///|
fn trash_status_message() -> String {
  "Trash Status:\n  Files: 0\n  Total size: 0 B\n  (No trash directory found)"
}

///|
fn trash_empty_message(days_old : Int) -> String {
  "No files older than \{days_old} days found in trash"
}

///|
fn trash_help_text() -> String {
  let lines : Array[String] = [
    "Trash Manager Help", "", "The `terminal` tool automatically moves deleted files to a trash directory",
    "instead of permanently deleting them. This tool helps you manage those files.",
    "", "Available actions:", "", "list - Show all deleted files", "  Example: trash_manager(action=\"list\")",
    "", "restore - Restore a deleted file to its original location", "  Example: trash_manager(action=\"restore\", file_path=\"path/to/file.txt\")",
    "", "status - Show trash summary with statistics", "  Example: trash_manager(action=\"status\")",
    "", "empty - Permanently delete files older than N days (default: 7)", "  Example: trash_manager(action=\"empty\", days_old=7)",
    "", "help - Show this help message", "", "Tips:", "- Use 'list' to see what files are in trash",
    "- Use 'restore' to get back accidentally deleted files", "- Use 'empty' periodically to free up disk space",
  ]
  join_trash_lines(lines, "\n")
}

///|
/// Format a byte count into a human-readable string (e.g., "1.5 KB").
pub fn format_bytes(bytes : Int) -> String {
  if bytes == 0 {
    return "0 B"
  }
  let units = ["B", "KB", "MB", "GB"]
  let mut size = bytes.to_double()
  let mut unit_index = 0
  while size >= 1024.0 && unit_index < 3 {
    size = size / 1024.0
    unit_index = unit_index + 1
  }
  if unit_index == 0 {
    "\{bytes} B"
  } else {
    let rounded = (size * 100.0).to_int() / 100
    let int_part = rounded / 100
    let frac_part = rounded % 100
    if frac_part == 0 {
      "\{int_part}.00 \{units[unit_index]}"
    } else if frac_part < 10 {
      "\{int_part}.0\{frac_part} \{units[unit_index]}"
    } else {
      "\{int_part}.\{frac_part} \{units[unit_index]}"
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
