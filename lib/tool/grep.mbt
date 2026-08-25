///|
/// Grep tool: search file contents with regular expressions.
///
/// Reference: D:/MoonBit/openclacky/lib/clacky/tools/grep.rb
/// 对齐（spec 2026-08-18_03 决策 1/6）：正则语义匹配、空 pattern 显式报错、
/// schema 补 max_total_matches/max_file_size、紧凑摘要头、UTF-8 scrub。
pub(all) struct Grep {
  max_files : Int
  max_matches_per_file : Int
  max_total_matches : Int
  max_line_length : Int
} derive(Eq, Debug)

///|
pub extend Grep with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend Grep with Eq::{not_equal, equal}

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
  "Search file contents using regular expressions. Returns matching lines with context.\n" +
  "- ALWAYS use Grep for search tasks.\n" +
  "- pattern is a regex (supports character classes, quantifiers, anchors, groups)\n" +
  "- Filter files with the file_pattern glob (e.g., '*.mbt', '**/*.js')\n" +
  "- CRITICAL: pattern MUST be returned before other fields."
}

///|
impl Tool for Grep with fn parameters(_) -> Json {
  Json::object({
    "type": "object".to_json(),
    "properties": Json::object({
      "pattern": Json::object({
        "type": "string".to_json(),
        "description": "The regular expression pattern to search for".to_json(),
      }),
      "path": Json::object({
        "type": "string".to_json(),
        "description": "File or directory to search in (defaults to current directory)".to_json(),
      }),
      "file_pattern": Json::object({
        "type": "string".to_json(),
        "description": "Glob pattern to filter files (e.g., '*.rb', '**/*.js')".to_json(),
      }),
      "case_insensitive": Json::object({
        "type": "boolean".to_json(),
        "description": "Perform case-insensitive search (default: false)".to_json(),
      }),
      "context_lines": Json::object({
        "type": "integer".to_json(),
        "description": "Number of context lines to show before and after each match (max: 10)".to_json(),
      }),
      "max_files": Json::object({
        "type": "integer".to_json(),
        "description": "Maximum number of matching files to return (default: 50)".to_json(),
      }),
      "max_matches_per_file": Json::object({
        "type": "integer".to_json(),
        "description": "Maximum number of matches to return per file (default: 50)".to_json(),
      }),
      "max_total_matches": Json::object({
        "type": "integer".to_json(),
        "description": "Maximum total number of matches to return across all files (default: 200)".to_json(),
      }),
      "max_file_size": Json::object({
        "type": "integer".to_json(),
        "description": "Maximum file size in bytes to search (default: 1048576)".to_json(),
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
  // 空 pattern 校验（对齐 Ruby："Pattern cannot be empty"）
  if pattern.trim().is_empty() {
    return ToolResult::error("Pattern cannot be empty")
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
  let max_total = get_int_arg(args, "max_total_matches", self.max_total_matches)
  let max_file_size = get_int_arg(args, "max_file_size", 1_048_576)

  // 正则编译（对齐 Ruby Regexp.new；case_insensitive → (?i:...) 包裹）
  let regex_str = if case_insensitive {
    "(?i:" + pattern + ")"
  } else {
    pattern
  }
  let re = Some(@string.Regex::Regex(regex_str)) catch { _ => None }
  match re {
    None => return ToolResult::error("Invalid regex pattern: \{pattern}")
    Some(re) =>
      do_search(
        path,
        re,
        file_pattern,
        context,
        max_files,
        max_per_file,
        max_total,
        max_file_size,
        self.max_line_length,
      )
  }
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
  re : @string.Regex,
  file_glob : String,
  context : Int,
  max_files : Int,
  max_per_file : Int,
  max_total : Int,
  max_file_size : Int,
  max_line_len : Int,
) -> ToolResult {
  let sb = StringBuilder()
  let mut total_matches = 0
  let mut files_searched = 0
  let mut files_with_matches = 0
  let mut skipped_large = 0
  let mut skipped_binary = 0
  let mut truncation_reason : String? = None

  if !@fs.path_exists(search_path) {
    return ToolResult::error("Path does not exist: \{search_path}")
  }

  // 文件收集：单文件直接；目录 walk + file_pattern 过滤（相对路径匹配）
  let is_file_val = @fs.is_file(search_path) catch { _ => false }
  let files : Array[String] = if is_file_val {
    [search_path]
  } else {
    // 裸 file_pattern 自动扩展（含 "/" 不动，否则 **/ 前缀；对齐 Ruby grep.rb）
    let effective = if file_glob.contains("/") {
      file_glob
    } else {
      "**/" + file_glob
    }
    let matcher = GlobMatcher::new(effective)
    let ignore = @utils.IgnoreConfig::new()
    let all = walk_files(search_path, max_files * 10 + 100, 10000, ignore)
    let result : Array[String] = []
    for rel in all {
      if matcher.match_path(rel) {
        result.push(join_path(search_path, rel))
      }
    }
    result
  }

  let mut fi = 0
  while fi < files.length() {
    guard files_searched < max_files && total_matches < max_total else {
      truncation_reason = Some("search limits reached")
      break
    }

    let file = files[fi]
    // 1MB 大文件跳过（对齐 Ruby max_file_size）
    match file_size_or_none(file) {
      Some(sz) if sz > max_file_size.to_int64() => {
        skipped_large = skipped_large + 1
        fi = fi + 1
        continue
      }
      _ => ()
    }

    // 读文件 + UTF-8 scrub（非法字节 → U+FFFD，对齐 Ruby safe_utf8）
    let content = match read_file_scrubbed(file) {
      Some(c) => c
      None => {
        fi = fi + 1
        continue
      }
    }

    if has_null_bytes(content) {
      skipped_binary = skipped_binary + 1
      fi = fi + 1
      continue
    }

    files_searched = files_searched + 1

    let matches = search_in_content(
      content,
      re,
      context,
      max_per_file,
      max_total - total_matches,
      max_line_len,
    )

    if matches.length() > 0 {
      files_with_matches = files_with_matches + 1
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

  // 紧凑摘要头（决策 6）：total / files_with_matches / files_searched / 截断
  let mut header = "(result): Found \{total_matches} match(es) in " +
    "\{files_with_matches} file(s), searched \{files_searched} file(s)"
  if skipped_large > 0 || skipped_binary > 0 {
    header = header +
      " (skipped: \{skipped_binary} binary, \{skipped_large} too large)"
  }
  match truncation_reason {
    Some(r) => header = header + " (truncated: \{r})"
    None => ()
  }

  ToolResult::success(header + sb.to_string())
}

///|
/// 读文件并 scrub 非法 UTF-8：统一走 @utf8.decode_lossy（先严格解码，
/// 失败才以 U+FFFD 替换，对齐 Ruby safe_utf8 意图）。
/// 注意：x/fs read_file_to_string 内部是宽松解码（非法字节被组合成伪字符，
/// 不产生 U+FFFD），故必须自己从 bytes 解码。
pub fn read_file_scrubbed(path : String) -> String? {
  Some(@utf8.decode_lossy(@fs.read_file_to_bytes(path).view())) catch {
    _ => None
  }
}

///|
fn search_in_content(
  content : String,
  re : @string.Regex,
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

  let mut i = 0
  while i < total_lines {
    guard results.length() < max_per_file && results.length() < max_remaining else {
      break
    }

    let line = lines[i]
    // 正则逐行匹配（^/$ 因此获得逐行锚点语义，等价 Ruby per-line =~）
    if re.execute(line) is Some(_) {
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
