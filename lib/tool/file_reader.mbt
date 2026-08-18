///|
/// FileReader tool: reads text files, lists directories.
///
/// Reference: D:/MoonBit/openclacky/lib/clacky/tools/file_reader.rb
/// 对齐（spec 2026-08-18_03 决策 3/4）：双轨参数（start_line/end_line/max_lines
/// + offset/limit 别名）、越界/逆序显式报错、输出无行号、空文件返回空 content、
/// 60000 字符总量截断、1MB 大文件护栏、目录列清单、UTF-8 scrub。
pub(all) struct FileReader {
  max_lines : Int
  max_line_chars : Int
} derive(Eq, Debug)

///|
pub extend FileReader with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend FileReader with Eq::{not_equal, equal}

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
  "- You can optionally specify max_lines (lines from start), or start_line/end_line (1-indexed range).\n" +
  "- Directories are listed (first-level contents).\n" +
  "- Files larger than 1MB are rejected — use grep to search within them instead.\n" +
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
      "max_lines": Json::object({
        "type": "integer".to_json(),
        "description": "Maximum number of lines to read from start (default: 1000)".to_json(),
      }),
      "start_line": Json::object({
        "type": "integer".to_json(),
        "description": "Start line number (1-indexed, e.g., 100 reads from line 100)".to_json(),
      }),
      "end_line": Json::object({
        "type": "integer".to_json(),
        "description": "End line number (1-indexed, e.g., 200 reads up to line 200)".to_json(),
      }),
    }),
    "required": ["path".to_json()],
  })
}

///|
impl Tool for FileReader with fn category(_) -> ToolCategory {
  FileSystem
}

// ── 常量（对齐 Ruby file_reader.rb） ────────────────────────────────────────

///|
let max_text_file_size : Int64 = 1_048_576

///|
let max_content_chars : Int = 60_000

// ────────────────────────────────────────────────────────────────────────────

///|
impl Tool for FileReader with fn execute(self, args : Map[String, Json]) -> ToolResult {
  let path = match args.get("path") {
    Some(String(s)) => s
    _ => return ToolResult::error("Missing required parameter: path")
  }

  if !@fs.path_exists(path) {
    return ToolResult::error("File not found: \{path}")
  }

  // 目录 → 第一层列清单（对齐 Ruby list_directory_contents）
  let is_dir_val = @fs.is_dir(path) catch { _ => false }
  if is_dir_val {
    return list_directory_contents(path)
  }

  let is_file_val = @fs.is_file(path) catch { _ => false }
  if !is_file_val {
    return ToolResult::error("Path is not a file: \{path}")
  }

  // 图片/文档等二进制扩展名 → 清晰报错（决策 9 降级落地；
  // Ruby 原版有文档解析管线，MB 无解析能力，报错引导 grep/其他工具）
  if is_binary_extension(path) {
    return ToolResult::error(
      "Binary or document file detected: \{get_basename(path)}. " +
      "File parsing is not supported — use grep tool to search within it, " +
      "or an external tool for document content.",
    )
  }

  // 1MB 大文件护栏（对齐 Ruby MAX_TEXT_FILE_SIZE）
  match file_size_or_none(path) {
    Some(sz) if sz > max_text_file_size =>
      return ToolResult::error(
        "Text file too large: \{format_file_size(sz)} (max: 1.0 MB). Please use grep tool to search within this file instead.",
      )
    _ => ()
  }

  // 读文件 + UTF-8 scrub（GBK 等非法字节 → U+FFFD）
  let content = match read_file_scrubbed(path) {
    Some(c) => c
    None => return ToolResult::error("Failed to read file: \{path}")
  }

  // 空文件 → 空 content 成功（对齐 Ruby content: ""）
  if content.is_empty() {
    return ToolResult::success("")
  }

  // 双轨参数解析：start_line/end_line/max_lines（1-indexed），
  // offset/limit 作为别名保留（决策 3：MB 既有调用与 wbtest 兼容）
  let start_line = get_int_arg(
    args,
    "start_line",
    get_int_arg(args, "offset", 0),
  )
  let end_line = get_int_arg(args, "end_line", 0)
  let max_lines = get_int_arg(
    args,
    "max_lines",
    get_int_arg(args, "limit", self.max_lines),
  )

  // Process lines using find-based parsing
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
  let start_idx = if start_line >= 1 { start_line - 1 } else { 0 }
  let end_idx = if end_line >= 1 {
    let e = end_line - 1
    if e < total_lines {
      e
    } else {
      total_lines - 1
    }
  } else if start_line >= 1 {
    // Ruby: calculated_end_line = start_line + max_lines - 1; end_idx = min(calculated-1, total-1)
    let calculated = start_line + max_lines - 1
    let e = calculated - 1
    if e < total_lines {
      e
    } else {
      total_lines - 1
    }
  } else {
    let e = max_lines - 1
    if e < total_lines {
      e
    } else {
      total_lines - 1
    }
  }

  // start_line 越界显式报错（对齐 Ruby）
  if start_idx >= total_lines {
    return ToolResult::error(
      "Invalid line range: start_line \{start_line} exceeds total lines (\{total_lines})",
    )
  }

  // start > end 显式报错（对齐 Ruby）
  if start_idx > end_idx {
    return ToolResult::error(
      "Invalid line range: start_line \{start_line} > end_line \{end_line}",
    )
  }

  let sb = StringBuilder::new()
  let mut i = start_idx
  while i <= end_idx {
    let line = lines[i]
    let display = if line.length() > self.max_line_chars {
      line[:self.max_line_chars].to_owned() +
      "... [Line truncated - \{line.length()} chars]"
    } else {
      line
    }
    // 无行号前缀（对齐 Ruby：content = lines.join）
    sb.write_string(display)
    sb.write_string("\n")
    i = i + 1
  }

  let mut out = sb.to_string()
  // 60000 字符总量截断（对齐 Ruby MAX_CONTENT_CHARS）
  if out.length() > max_content_chars {
    out = out[:max_content_chars].to_owned() +
      "\n\n[Content truncated - exceeded \{max_content_chars} characters (~10,000 tokens)]" +
      "\nUse start_line/end_line parameters to read specific sections, or grep tool to search for keywords."
  }

  // 行数说明尾部（MB 既有风格保留）
  if end_idx < total_lines - 1 {
    out = out +
      "...(truncated: lines \{start_idx + 1}-\{end_idx + 1} of \{total_lines})"
  }

  ToolResult::success(out)
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

// ── 目录列清单（对齐 Ruby list_directory_contents） ────────────────────────

///|
fn list_directory_contents(path : String) -> ToolResult {
  let entries = @fs.read_dir(path) catch {
    _ => return ToolResult::error("Error reading directory: \{path}")
  }

  let dirs : Array[String] = []
  let files : Array[String] = []
  for entry in entries {
    if entry == "." || entry == ".." {
      continue
    }
    let full = join_path(path, entry)
    let is_dir_val = @fs.is_dir(full) catch { _ => false }
    if is_dir_val {
      dirs.push(entry + "/")
    } else {
      files.push(entry)
    }
  }

  dirs.sort()
  files.sort()
  let all_entries = dirs + files

  let sb = StringBuilder::new()
  sb.write_string("Directory listing:\n")
  for entry in all_entries {
    sb.write_string("  \{entry}\n")
  }
  ToolResult::success(sb.to_string())
}

// ── Shared Helpers ──────────────────────────────────────────────────────────

///|
/// 人类可读文件大小（对齐 Ruby format_file_size）。
pub fn format_file_size(bytes : Int64) -> String {
  if bytes < 1024 {
    "\{bytes} bytes"
  } else if bytes < 1024 * 1024 {
    "\{bytes.to_double() / 1024.0 |> double_round_2} KB"
  } else {
    "\{bytes.to_double() / (1024.0 * 1024.0) |> double_round_2} MB"
  }
}

///|
fn double_round_2(v : Double) -> Double {
  (v * 100.0).round() / 100.0
}

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
  let s = path.replace_all(old="\\", new="/")
  let mut last = s
  let mut pos = 0
  while pos < s.length() {
    if s[pos:pos + 1].to_owned() == "/" {
      if pos + 1 < s.length() {
        last = s[pos + 1:].to_owned()
      }
    }
    pos = pos + 1
  }
  last
}
