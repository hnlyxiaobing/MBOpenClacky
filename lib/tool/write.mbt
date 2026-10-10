///| Write tool: creates or overwrites files.

///|
/// Reference: D:/MoonBit/openclacky/lib/clacky/tools/write.rb
pub(all) struct Write {
  encoding : String
} derive(Eq, Debug)

///|
pub extend Write with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend Write with Eq::{not_equal, equal}

///|
pub fn Write::new() -> Write {
  { encoding: "utf-8", }
}

///|
impl Tool for Write with fn name(_) -> String {
  "write"
}

///|
impl Tool for Write with fn description(_) -> String {
  "Writes a file to the local filesystem.\n" +
  "- This tool will overwrite the existing file if there is one.\n" +
  "- ALWAYS prefer editing existing files using the Edit tool.\n" +
  "- NEVER proactively create documentation files.\n" +
  "- CRITICAL: filePath MUST be an absolute path."
}

///|
impl Tool for Write with fn parameters(_) -> Json {
  Json::object({
    "type": Json("object"),
    "properties": Json::object({
      "path": Json::object({
        "type": Json("string"),
        "description": Json("The absolute path to the file to write"),
      }),
      "content": Json::object({
        "type": Json("string"),
        "description": Json("The content to write to the file"),
      }),
    }),
    "required": [Json("path"), Json("content")],
  })
}

///|
impl Tool for Write with fn category(_) -> ToolCategory {
  FileSystem
}

///|
impl Tool for Write with fn execute(_, args : Map[String, Json]) -> ToolResult {
  let path = match args.get("path") {
    Some(String(s)) => s
    _ => return ToolResult::error("Missing required parameter: path")
  }
  let content = match args.get("content") {
    Some(String(s)) => s
    _ => return ToolResult::error("Missing required parameter: content")
  }

  guard !path.trim().is_empty() else {
    return ToolResult::error("Path cannot be empty")
  }

  if is_secret_path(path) {
    return ToolResult::error(
      "Write to credential/secret path blocked: \{path}.",
    )
  }

  // 显式预检而非依赖底层写失败的 OS 错误（Windows/POSIX 目录错误文案不同）
  let path_is_dir = @fs.is_dir(path) catch { _ => false }
  if path_is_dir {
    return ToolResult::error("Failed to write file: Is a directory: \{path}")
  }

  let parent = @path.Path::dirname(@path.Path(path)).to_string()
  if !parent.is_empty() && parent != path && !@fs.path_exists(parent) {
    @utils.ensure_dir(parent)
  }

  @fs.write_string_to_file(path, content) catch {
    _ => return ToolResult::error("Failed to write file: \{path}")
  }
  let bytes = @utils.estimate_utf8_byte_length(content)
  let result_json = Json::object({
    "path": Json(path),
    "bytes_written": Json::number(bytes.to_double()),
    "error": Json::null(),
  })
  ToolResult::success(result_json.stringify())
}

///|
impl Tool for Write with fn format_call(_, args : Map[String, Json]) -> String {
  match args.get("path") {
    Some(String(p)) => "Write(\{get_basename(p)})"
    _ => "Write(?)"
  }
}

///|
impl Tool for Write with fn format_result(_, result : ToolResult) -> String {
  let json = @json.parse(result.content) catch { _ => return result.content }
  match json {
    Object(obj) => {
      let bytes = match obj.get("bytes_written") {
        Some(Number(n, ..)) => n.to_int().to_string()
        _ => "0"
      }
      "Written \{bytes} bytes"
    }
    _ => result.content
  }
}

///|
impl Tool for Write with fn to_function_definition(self) -> FunctionDefinition {
  FunctionDefinition::new(self.name(), self.description(), self.parameters())
}
