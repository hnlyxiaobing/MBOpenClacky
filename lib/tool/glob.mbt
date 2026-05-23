///| Glob tool: find files matching glob patterns.

///|
/// Reference: D:/MoonBit/openclacky/lib/clacky/tools/glob.rb
pub(all) struct Glob {
  limit : Int
} derive(Eq, Debug)

///|
pub fn Glob::new() -> Glob {
  { limit: 10 }
}

///|
impl Tool for Glob with name(_) -> String {
  "glob"
}

///|
impl Tool for Glob with description(_) -> String {
  "Fast file pattern matching tool.\n" +
  "- Supports glob patterns like \"**/*.js\" or \"src/**/*.ts\"\n" +
  "- Returns matching file paths sorted by modification time\n" +
  "- Use this tool when you need to find files by name patterns"
}

///|
impl Tool for Glob with parameters(_) -> Json {
  Json::object({
    "type": "object".to_json(),
    "properties": Json::object({
      "pattern": Json::object({
        "type": "string".to_json(),
        "description": "The glob pattern to match files against".to_json(),
      }),
      "base_path": Json::object({
        "type": "string".to_json(),
        "description": "The directory to search in (default: current directory)".to_json(),
      }),
      "limit": Json::object({
        "type": "integer".to_json(),
        "description": "Maximum number of results (default: 10)".to_json(),
      }),
    }),
    "required": ["pattern".to_json()],
  })
}

///|
impl Tool for Glob with category(_) -> ToolCategory {
  FileSystem
}

///|
impl Tool for Glob with execute(self, args : Map[String, Json]) -> ToolResult {
  let pattern = match args.get("pattern") {
    Some(String(s)) => s
    _ => return ToolResult::error("Missing required parameter: pattern")
  }
  let base_path = match args.get("base_path") {
    Some(String(s)) => s
    _ => "."
  }
  let limit = get_int_arg(args, "limit", self.limit)

  let effective = pattern

  // Collect files recursively
  let matches : Array[String] = []
  walk_glob_files(base_path, effective, limit, matches)

  if matches.is_empty() {
    return ToolResult::success("No files matched pattern: \{effective}")
  }

  let sb = StringBuilder::new()
  sb.write_string("Found \{matches.length()} file(s) matching: \{effective}\n")
  let mut idx = 0
  while idx < matches.length() {
    sb.write_string("\{idx + 1}. \{matches[idx]}\n")
    idx = idx + 1
  }
  ToolResult::success(sb.to_string())
}

///|
impl Tool for Glob with format_call(_, args : Map[String, Json]) -> String {
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
impl Tool for Glob with format_result(_, result : ToolResult) -> String {
  if result.is_error {
    result.content
  } else {
    "[OK] Glob completed"
  }
}

///|
impl Tool for Glob with to_function_definition(self) -> FunctionDefinition {
  FunctionDefinition::new(self.name(), self.description(), self.parameters())
}

///|
fn walk_glob_files(
  current : String,
  pattern : String,
  limit : Int,
  results : Array[String],
) -> Unit {
  guard results.length() < limit else { return }
  guard @fs.path_exists(current) else { return }

  let entries = @fs.read_dir(current) catch { _ => return }

  let mut idx = 0
  while idx < entries.length() {
    guard results.length() < limit else { return }
    let name = entries[idx]
    let full = current + "/" + name

    let is_dir_val = @fs.is_dir(full) catch { _ => false }
    if is_dir_val {
      if !name.has_prefix(".") || name == "." {
        walk_glob_files(full, pattern, limit, results)
      }
    } else if simple_glob_match(name, pattern) ||
      simple_glob_match(full, pattern) {
      results.push(full)
    }
    idx = idx + 1
  }
}

///|
pub fn simple_glob_match(name : String, pat : String) -> Bool {
  if pat == "*" {
    return true
  }
  if pat == "**" {
    return true
  }
  if name == pat {
    return true
  }
  // prefix*suffix pattern
  match pat.find("*") {
    Some(star_idx) => {
      let prefix = pat[:star_idx].to_string()
      let suffix = if star_idx + 1 < pat.length() {
        pat[star_idx + 1:].to_string()
      } else {
        ""
      }
      name.has_prefix(prefix) && name.has_suffix(suffix)
    }
    None => false
  }
}
