///| FileReader tool: reads text files, lists directories.

///|
/// Reference: D:/MoonBit/openclacky/lib/clacky/tools/file_reader.rb
pub(all) struct FileReader {
  max_lines : Int
  max_line_chars : Int
} derive(Eq, Debug)

///|
pub fn FileReader::new() -> FileReader {
  { max_lines: 1000, max_line_chars: 1000 }
}

///|
impl Tool for FileReader with fn name(_) -> String {
  "file_reader"
}

///|
impl Tool for FileReader with fn description(_) -> String {
  "Reads a file from the local filesystem. You can access any file directly by using this tool.\n" +
  "- You can optionally specify an offset and limit for long files.\n" +
  "- FilePath must be an absolute path."
}

///|
impl Tool for FileReader with fn parameters(_) -> Json {
  Json::object({
    "type": "object".to_json(),
    "properties": Json::object({
      "path": Json::object({
        "type": "string".to_json(),
        "description": "The absolute path to the file to read".to_json(),
      }),
      "offset": Json::object({
        "type": "integer".to_json(),
        "description": "The line number to start reading from".to_json(),
      }),
      "limit": Json::object({
        "type": "integer".to_json(),
        "description": "The number of lines to read".to_json(),
      }),
    }),
    "required": ["path".to_json()],
  })
}

///|
impl Tool for FileReader with fn category(_) -> ToolCategory {
  FileSystem
}

///|
impl Tool for FileReader with fn execute(self, args : Map[String, Json]) -> ToolResult {
  let path = match args.get("path") {
    Some(String(s)) => s
    _ => return ToolResult::error("Missing required parameter: path")
  }

  if !@fs.path_exists(path) {
    return ToolResult::error("File not found: \{path}")
  }

  let content = @fs.read_file_to_string(path) catch {
    _ => return ToolResult::error("Failed to read file: \{path}")
  }

  if content.is_empty() {
    return ToolResult::success("File is empty.")
  }

  let offset = get_int_arg(args, "offset", 0)
  let limit_val = get_int_arg(args, "limit", self.max_lines)

  // Process lines using find-based parsing (matching existing codebase patterns)
  let lines : Array[String] = []
  let mut pos = 0
  let content_len = content.length()
  while pos < content_len {
    match content[pos:].to_string().find("\n") {
      Some(idx) => {
        lines.push(content[pos:pos + idx].to_string())
        pos = pos + idx + 1
      }
      None => {
        lines.push(content[pos:].to_string())
        pos = content_len
      }
    }
  }

  let total_lines = lines.length()
  let start_idx = if offset >= 1 && offset - 1 < total_lines {
    offset - 1
  } else {
    0
  }
  let max_end = start_idx +
    (if limit_val > 0 { limit_val } else { self.max_lines })
  let actual_end = if max_end < total_lines { max_end } else { total_lines }

  let sb = StringBuilder::new()
  let mut i = start_idx
  while i < actual_end {
    let line = lines[i]
    let display = if line.length() > self.max_line_chars {
      line[:self.max_line_chars].to_string() + "...(truncated)"
    } else {
      line
    }
    sb.write_string("\{i + 1}\t\{display}\n")
    i = i + 1
  }
  if actual_end < total_lines {
    sb.write_string(
      "...(truncated: lines \{start_idx + 1}-\{actual_end} of \{total_lines})",
    )
  }
  ToolResult::success(sb.to_string())
}

///|
impl Tool for FileReader with fn format_call(_, args : Map[String, Json]) -> String {
  match args.get("path") {
    Some(String(p)) => "Read(\{get_basename(p)})"
    _ => "Read(?)"
  }
}

///|
impl Tool for FileReader with fn format_result(_, result : ToolResult) -> String {
  if result.is_error {
    result.content
  } else {
    "Read completed (\{result.content.length()} chars)"
  }
}

///|
impl Tool for FileReader with fn to_function_definition(self) -> FunctionDefinition {
  FunctionDefinition::new(self.name(), self.description(), self.parameters())
}

// ── Shared Helpers ──────────────────────────────────────────────────────────

///|
/// Get string value from JSON args map.
pub fn get_string_arg(
  args : Map[String, Json],
  key : String,
  default : String,
) -> String {
  match args.get(key) {
    Some(String(s)) => s
    _ => default
  }
}

///|
/// Get integer value from JSON args map.
pub fn get_int_arg(
  args : Map[String, Json],
  key : String,
  default : Int,
) -> Int {
  match args.get(key) {
    Some(Number(n, ..)) if n >= -2147483648.0 && n <= 2147483647.0 => n.to_int()
    Some(String(s)) =>
      @string.parse_int(s.to_string_view()) catch {
        _ => default
      }
    _ => default
  }
}

///|
/// Get boolean value from JSON args map.
pub fn get_bool_arg(
  args : Map[String, Json],
  key : String,
  default : Bool,
) -> Bool {
  match args.get(key) {
    Some(True) => true
    Some(False) => false
    Some(String(s)) => s.to_lower() == "true"
    _ => default
  }
}

///|
/// Extract basename from a path string.
pub fn get_basename(path : String) -> String {
  let s = path.replace(old="\\", new="/")
  let mut last = s
  let mut pos = 0
  while pos < s.length() {
    if s[pos:pos + 1].to_string() == "/" {
      if pos + 1 < s.length() {
        last = s[pos + 1:].to_string()
      }
    }
    pos = pos + 1
  }
  last
}
