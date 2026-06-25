///| Grep tool: search file contents with pattern matching.

///|
/// Reference: D:/MoonBit/openclacky/lib/clacky/tools/grep.rb
pub(all) struct Grep {
  max_files : Int
  max_matches_per_file : Int
  max_total_matches : Int
  max_line_length : Int
} derive(Eq, Debug)

///|
pub fn Grep::new() -> Grep {
  {
    max_files: 50,
    max_matches_per_file: 50,
    max_total_matches: 200,
    max_line_length: 500,
  }
}

///|
impl Tool for Grep with fn name(_) -> String {
  "grep"
}

///|
impl Tool for Grep with fn description(_) -> String {
  "A powerful search tool for searching file contents.\n" +
  "- ALWAYS use Grep for search tasks.\n" +
  "- Filter files with glob parameter.\n" +
  "- CRITICAL: pattern MUST be returned before other fields."
}

///|
impl Tool for Grep with fn parameters(_) -> Json {
  Json::object({
    "type": "object".to_json(),
    "properties": Json::object({
      "pattern": Json::object({
        "type": "string".to_json(),
        "description": "The regex pattern to search for in file contents".to_json(),
      }),
      "path": Json::object({
        "type": "string".to_json(),
        "description": "File or directory to search in".to_json(),
      }),
      "file_pattern": Json::object({
        "type": "string".to_json(),
        "description": "Glob pattern to filter files".to_json(),
      }),
      "case_insensitive": Json::object({
        "type": "boolean".to_json(),
        "description": "Case insensitive search (default: false)".to_json(),
      }),
      "context_lines": Json::object({
        "type": "integer".to_json(),
        "description": "Number of context lines (max 10)".to_json(),
      }),
      "max_files": Json::object({
        "type": "integer".to_json(),
        "description": "Maximum number of files to search (default: 50)".to_json(),
      }),
      "max_matches_per_file": Json::object({
        "type": "integer".to_json(),
        "description": "Maximum matches per file (default: 50)".to_json(),
      }),
    }),
    "required": ["pattern".to_json()],
  })
}

///|
impl Tool for Grep with fn category(_) -> ToolCategory {
  FileSystem
}

///|
impl Tool for Grep with fn execute(self, args : Map[String, Json]) -> ToolResult {
  let pattern = match args.get("pattern") {
    Some(String(s)) => s
    _ => return ToolResult::error("Missing required parameter: pattern")
  }
  let path = match args.get("path") {
    Some(String(s)) => s
    _ => "."
  }
  let file_pattern = match args.get("file_pattern") {
    Some(String(s)) => s
    _ => "**/*"
  }
  let case_insensitive = get_bool_arg(args, "case_insensitive", false)
  let context_val = get_int_arg(args, "context_lines", 0)
  let context = if context_val > 10 {
    10
  } else if context_val < 0 {
    0
  } else {
    context_val
  }
  let max_files = get_int_arg(args, "max_files", self.max_files)
  let max_per_file = get_int_arg(
    args,
    "max_matches_per_file",
    self.max_matches_per_file,
  )

  let search_result = do_search(
    path,
    pattern,
    file_pattern,
    case_insensitive,
    context,
    max_files,
    max_per_file,
    self.max_total_matches,
    self.max_line_length,
  )
  ToolResult::success(search_result)
}

///|
impl Tool for Grep with fn format_call(_, args : Map[String, Json]) -> String {
  let pat = match args.get("pattern") {
    Some(String(s)) => s
    _ => "?"
  }
  let p = match args.get("path") {
    Some(String(s)) => s
    _ => "."
  }
  "grep(\"\{pat}\" in \{p})"
}

///|
impl Tool for Grep with fn format_result(_, result : ToolResult) -> String {
  if result.is_error {
    result.content
  } else {
    "[OK] Grep completed"
  }
}

///|
impl Tool for Grep with fn to_function_definition(self) -> FunctionDefinition {
  FunctionDefinition::new(self.name(), self.description(), self.parameters())
}

///|
fn do_search(
  search_path : String,
  pattern : String,
  file_glob : String,
  case_insensitive : Bool,
  context : Int,
  max_files : Int,
  max_per_file : Int,
  max_total : Int,
  max_line_len : Int,
) -> String {
  let sb = StringBuilder::new()
  let mut total_matches = 0
  let mut files_searched = 0

  guard @fs.path_exists(search_path) else {
    return "(error): Path not found: \{search_path}"
  }

  let files : Array[String] = []
  collect_all_files(search_path, file_glob, max_files + 50, files)

  let mut fi = 0
  while fi < files.length() {
    guard files_searched < max_files && total_matches < max_total else { break }

    let file = files[fi]
    let content = @fs.read_file_to_string(file) catch {
      _ => {
        fi = fi + 1
        continue
      }
    }

    if has_null_bytes(content) {
      fi = fi + 1
      continue
    }

    let matches = search_in_content(
      content,
      pattern,
      case_insensitive,
      context,
      max_per_file,
      max_total - total_matches,
      max_line_len,
    )

    if matches.length() > 0 {
      files_searched = files_searched + 1
      sb.write_string("\n--- \{file} ---\n")
      let mut mi = 0
      while mi < matches.length() {
        sb.write_string(matches[mi])
        sb.write_string("\n")
        mi = mi + 1
      }
      total_matches = total_matches + matches.length()
    }
    fi = fi + 1
  }

  "(result): Found \{total_matches} match(es) in \{files_searched} file(s)" +
  sb.to_string()
}

///|
fn search_in_content(
  content : String,
  pattern : String,
  case_insensitive : Bool,
  context : Int,
  max_per_file : Int,
  max_remaining : Int,
  max_line_len : Int,
) -> Array[String] {
  let results : Array[String] = []

  // Parse lines
  let lines : Array[String] = []
  let mut pos = 0
  let content_len = content.length()
  while pos < content_len {
    match content[pos:].to_owned().find("\n") {
      Some(idx) => {
        lines.push(content[pos:pos + idx].to_owned())
        pos = pos + idx + 1
      }
      None => {
        lines.push(content[pos:].to_owned())
        pos = content_len
      }
    }
  }

  let total_lines = lines.length()
  guard total_lines > 0 else { return results }

  let effective = if case_insensitive { pattern.to_lower() } else { pattern }

  let mut i = 0
  while i < total_lines {
    guard results.length() < max_per_file && results.length() < max_remaining else {
      break
    }

    let line = lines[i]
    let search_line = if case_insensitive { line.to_lower() } else { line }

    if search_line.find(effective) is Some(_) {
      let line_num = i + 1
      let display = if line.length() > max_line_len {
        line[:max_line_len].to_owned() + "..."
      } else {
        line
      }

      if context > 0 {
        let ctx_start = if i >= context { i - context } else { 0 }
        let mut j = ctx_start
        while j < i {
          let ctx_line = if lines[j].length() > max_line_len {
            lines[j][:max_line_len].to_owned() + "..."
          } else {
            lines[j]
          }
          results.push("  \{j + 1}: \{ctx_line}")
          j = j + 1
        }
      }

      results.push("→ \{line_num}: \{display}")

      if context > 0 {
        let ctx_end = if i + context < total_lines {
          i + context + 1
        } else {
          total_lines
        }
        let mut j = i + 1
        while j < ctx_end {
          let ctx_line = if lines[j].length() > max_line_len {
            lines[j][:max_line_len].to_owned() + "..."
          } else {
            lines[j]
          }
          results.push("  \{j + 1}: \{ctx_line}")
          j = j + 1
        }
      }
    }
    i = i + 1
  }
  results
}

///|
fn collect_all_files(
  current : String,
  glob : String,
  limit : Int,
  results : Array[String],
) -> Unit {
  guard results.length() < limit else { return }
  guard @fs.path_exists(current) else { return }

  let is_file_val = @fs.is_file(current) catch { _ => false }
  if is_file_val {
    results.push(current)
    return
  }

  let entries = @fs.read_dir(current) catch { _ => return }

  let mut idx = 0
  while idx < entries.length() {
    guard results.length() < limit else { return }
    let name = entries[idx]
    let full = current + "/" + name

    let is_dir_val = @fs.is_dir(full) catch { _ => false }
    if is_dir_val {
      if !name.has_prefix(".") || name == "." {
        collect_all_files(full, glob, limit, results)
      }
    } else if simple_glob_match(name, glob) || simple_glob_match(full, glob) {
      results.push(full)
    }
    idx = idx + 1
  }
}

///|
fn has_null_bytes(content : String) -> Bool {
  let check_len = if content.length() > 2048 { 2048 } else { content.length() }
  let mut null_count = 0
  let mut i = 0
  while i < check_len {
    if content[i:i + 1].to_owned() == "\u0000" {
      null_count = null_count + 1
      if null_count > 3 {
        return true
      }
    }
    i = i + 1
  }
  false
}
