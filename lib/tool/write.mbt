///| Write tool: creates or overwrites files.

///|
/// Reference: D:/MoonBit/openclacky/lib/clacky/tools/write.rb
pub(all) struct Write {
  encoding : String
} derive(Eq, Debug)

///|
pub fn Write::new() -> Write {
  { encoding: "utf-8" }
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
    "type": "object".to_json(),
    "properties": Json::object({
      "path": Json::object({
        "type": "string".to_json(),
        "description": "The absolute path to the file to write".to_json(),
      }),
      "content": Json::object({
        "type": "string".to_json(),
        "description": "The content to write to the file".to_json(),
      }),
    }),
    "required": ["path".to_json(), "content".to_json()],
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

  guard !path.is_empty() else {
    return ToolResult::error("Path cannot be empty")
  }

  if is_secret_path(path) {
    return ToolResult::error(
      "Write to credential/secret path blocked: \{path}.",
    )
  }

  let parent = @path.Path::dirname(@path.Path(path)).to_string()
  if !parent.is_empty() && parent != path && !@fs.path_exists(parent) {
    @fs.create_dir(parent) catch {
      _ => ()
    }
  }

  @fs.write_string_to_file(path, content) catch {
    _ => return ToolResult::error("Failed to write file: \{path}")
  }
  ToolResult::success("Written \{content.length()} bytes to \{path}")
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
  result.content
}

///|
impl Tool for Write with fn to_function_definition(self) -> FunctionDefinition {
  FunctionDefinition::new(self.name(), self.description(), self.parameters())
}
