///|
/// Glob tool: find files matching glob patterns.
///
/// Reference: D:/MoonBit/openclacky/lib/clacky/tools/glob.rb
/// 对齐（spec 2026-08-18_03 决策 2/5）：**/*/? 递归匹配、裸模式自动扩展、
/// mtime 降序排序、gitignore/隐藏目录跳过、空 pattern 与坏 base_path 显式报错。
pub(all) struct Glob {
  limit : Int
} derive(Eq, Debug)

///|
pub extend Glob with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend Glob with Eq::{not_equal, equal}

///|
pub fn Glob::new() -> Glob {
  { limit: 10 }
}

///|
impl Tool for Glob with fn name(_) -> String {
  "glob"
}

///|
impl Tool for Glob with fn description(_) -> String {
  "Find files matching a glob pattern (e.g., '**/*.mbt', 'src/**/*.mbt', '*.txt').\n" +
  "- Supports ** (recursive), * (within a segment), and ? (single char)\n" +
  "- Bare patterns like '*.mbt' are auto-expanded to search recursively\n" +
  "- Returns matching file paths sorted by modification time (most recent first)\n" +
  "- Respects .gitignore patterns and skips hidden directories"
}

///|
impl Tool for Glob with fn parameters(_) -> Json {
  Json::object({
    "type": "object".to_json(),
    "properties": Json::object({
      "pattern": Json::object({
        "type": "string".to_json(),
        "description": "The glob pattern to match files (e.g., '**/*.rb', 'lib/**/*.rb', '*.txt')".to_json(),
      }),
      "base_path": Json::object({
        "type": "string".to_json(),
        "description": "The base directory to search in (defaults to current directory)".to_json(),
      }),
      "limit": Json::object({
        "type": "integer".to_json(),
        "description": "Maximum number of results to return (default: 10)".to_json(),
      }),
    }),
    "required": ["pattern".to_json()],
  })
}

///|
impl Tool for Glob with fn category(_) -> ToolCategory {
  FileSystem
}

///|
impl Tool for Glob with fn execute(self, args : Map[String, Json]) -> ToolResult {
  let pattern = match args.get("pattern") {
    Some(String(s)) => s
    _ => return ToolResult::error("Missing required parameter: pattern")
  }
  if pattern.trim().is_empty() {
    return ToolResult::error("Pattern cannot be empty")
  }
  let base_path = match args.get("base_path") {
    Some(String(s)) => s
    _ => "."
  }
  let limit = get_int_arg(args, "limit", self.limit)

  // base_path 校验（对齐 Ruby：Dir.exist? 检查）
  if !@fs.path_exists(base_path) {
    return ToolResult::error("Base path does not exist: \{base_path}")
  }
  let base_is_dir = @fs.is_dir(base_path) catch { _ => false }
  if !base_is_dir {
    return ToolResult::error("Base path is not a directory: \{base_path}")
  }

  // 裸模式自动扩展：无 / 且非 ** 开头 → **/pattern（对齐 Ruby glob.rb）
  let effective = if !pattern.contains("/") && !pattern.has_prefix("**") {
    "**/" + pattern
  } else {
    pattern
  }

  let matcher = GlobMatcher::new(effective)
  let ignore = @utils.IgnoreConfig::new()
  let all = walk_files(base_path, limit * 10 + 100, 10000, ignore)

  // 过滤：glob 匹配 + 1MB 护栏 + 二进制跳过，记录 (path, mtime)
  let collected : Array[(String, Int64)] = []
  for rel in all {
    guard collected.length() < limit else { break }
    if !matcher.match_path(rel) {
      continue
    }
    let full = join_path(base_path, rel)
    // 1MB 大文件跳过（对齐 Ruby MAX_FILE_SIZE）
    match file_size_or_none(full) {
      Some(sz) if sz > 1_048_576 => continue
      _ => ()
    }
    // 二进制跳过（扩展名黑名单）
    if is_binary_extension(rel) {
      continue
    }
    let mtime = mtime_sec_or_none(full).unwrap_or(0)
    collected.push((full, mtime))
  }

  // mtime 降序排序（插入排序，collected 规模 <= limit）
  for i = 1; i < collected.length(); i = i + 1 {
    let key = collected[i]
    let mut j = i - 1
    while j >= 0 && collected[j].1 < key.1 {
      collected[j + 1] = collected[j]
      j = j - 1
    }
    collected[j + 1] = key
  }

  let total = collected.length()
  let shown = if total > limit { limit } else { total }

  if shown == 0 {
    return ToolResult::success("No files matched pattern: \{pattern}")
  }

  let sb = StringBuilder::new()
  if shown < total {
    sb.write_string(
      "Found \{total} file(s) matching: \{pattern} (showing first \{shown})\n",
    )
  } else {
    sb.write_string("Found \{total} file(s) matching: \{pattern}\n")
  }
  let mut idx = 0
  while idx < shown {
    sb.write_string("\{idx + 1}. \{collected[idx].0}\n")
    idx = idx + 1
  }
  ToolResult::success(sb.to_string())
}

///|
impl Tool for Glob with fn format_call(_, args : Map[String, Json]) -> String {
  let pat = match args.get("pattern") {
    Some(String(s)) => s
    _ => "?"
  }
  let base = match args.get("base_path") {
    Some(String(s)) => s
    _ => "."
  }
  "glob(\"\{pat}\" in \{base})"
}

///|
impl Tool for Glob with fn format_result(_, result : ToolResult) -> String {
  if result.is_error {
    result.content
  } else {
    "[OK] Glob completed"
  }
}

///|
impl Tool for Glob with fn to_function_definition(self) -> FunctionDefinition {
  FunctionDefinition::new(self.name(), self.description(), self.parameters())
}

// ── 兼容入口（旧 pub API，语义升级为 **/*/? 递归匹配） ─────────────────────

///|
/// Glob-style path match：`**`/`*`/`?` 递归匹配（相对路径语义）。
/// 兼容旧 simple_glob_match 调用点（spec 决策 2：重写实现、保留入口）。
pub fn simple_glob_match(name : String, pat : String) -> Bool {
  glob_path_match(pat, name)
}

// ── 公共 walk（grep 与 glob 共用） ─────────────────────────────────────────

///|
priv struct WalkBudget {
  mut dirs : Int
}

///|
/// 遍历 base 下所有文件（gitignore + 隐藏目录跳过），返回相对 base 的路径。
/// limit 为收集上限保护，max_dirs 为目录访问预算（防失控遍历）。
pub fn walk_files(
  base : String,
  limit : Int,
  max_dirs : Int,
  ignore : @utils.IgnoreConfig,
) -> Array[String] {
  let results : Array[String] = []
  let budget : WalkBudget = { dirs: 0 }
  walk_recursive(base, base, ignore, limit, max_dirs, budget, results)
  results
}

///|
fn walk_recursive(
  current : String,
  base : String,
  ignore : @utils.IgnoreConfig,
  limit : Int,
  max_dirs : Int,
  budget : WalkBudget,
  results : Array[String],
) -> Unit {
  budget.dirs = budget.dirs + 1
  guard budget.dirs <= max_dirs else { return }
  guard results.length() < limit else { return }

  let entries = @fs.read_dir(current) catch { _ => return }
  // 本层 .gitignore 追加（对齐 Ruby walk_files 逐层读取）
  let ignore2 = load_layer_gitignore(ignore, current)

  let mut idx = 0
  while idx < entries.length() {
    guard results.length() < limit else { return }
    let name = entries[idx]
    if name == "." || name == ".." {
      idx = idx + 1
      continue
    }
    let full = join_path(current, name)
    let rel = relative_to(base, full)

    let is_dir_val = @fs.is_dir(full) catch { _ => false }
    if is_dir_val {
      // 隐藏目录跳过（沿用现有 . 前缀规则）+ gitignore
      if name.has_prefix(".") {
        idx = idx + 1
        continue
      }
      if ignore2.should_ignore(rel, is_dir=true) {
        idx = idx + 1
        continue
      }
      walk_recursive(full, base, ignore2, limit, max_dirs, budget, results)
    } else {
      if ignore2.should_ignore(rel) {
        idx = idx + 1
        continue
      }
      results.push(rel)
    }
    idx = idx + 1
  }
}

///|
fn load_layer_gitignore(
  ignore : @utils.IgnoreConfig,
  dir : String,
) -> @utils.IgnoreConfig {
  let p = join_path(dir, ".gitignore")
  if @fs.path_exists(p) {
    let content = @fs.read_file_to_string(p) catch { _ => "" }
    if content.is_empty() {
      ignore
    } else {
      ignore.load_gitignore(content)
    }
  } else {
    ignore
  }
}

// ── 路径 helpers ───────────────────────────────────────────────────────────

///|
/// 拼接路径段（处理 "" 与尾斜杠）。
pub fn join_path(dir : String, name : String) -> String {
  if dir.is_empty() {
    name
  } else if dir.has_suffix("/") {
    dir + name
  } else {
    dir + "/" + name
  }
}

///|
/// 计算 full 相对 base 的路径（base="." → "./a" 得 "a"）。
pub fn relative_to(base : String, full : String) -> String {
  let prefix = if base == "." {
    "./"
  } else if base == "/" {
    "/"
  } else if base.has_suffix("/") {
    base
  } else {
    base + "/"
  }
  if full.has_prefix(prefix) {
    full[prefix.length():].to_owned()
  } else {
    full
  }
}

///|
/// 已知二进制扩展名（跳过；对齐 Ruby FileProcessor.binary_file_path? 的意图）。
pub fn is_binary_extension(path : String) -> Bool {
  let lower = path.to_lower()
  let exts = [
    ".png", ".jpg", ".jpeg", ".gif", ".webp", ".bmp", ".ico", ".pdf", ".doc", ".docx",
    ".xls", ".xlsx", ".ppt", ".pptx", ".zip", ".tar", ".gz", ".tgz", ".bz2", ".7z",
    ".rar", ".exe", ".dll", ".so", ".dylib", ".bin", ".class", ".o", ".a", ".pyc",
    ".woff", ".woff2", ".ttf", ".otf", ".eot", ".mp3", ".mp4", ".avi", ".mov", ".mkv",
    ".wav", ".flac", ".wasm", ".dat", ".db", ".sqlite", ".sqlite3", ".jar", ".war",
    ".wps", ".et", ".dps",
  ]
  for ext in exts {
    if lower.has_suffix(ext) {
      return true
    }
  }
  false
}
