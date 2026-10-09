///| Edit tool: precise string-replacement edits to files.

///|
/// Reference: D:/MoonBit/openclacky/lib/clacky/tools/edit.rb
pub(all) struct Edit {
  encoding : String
} derive(Eq, Debug)

///|
pub extend Edit with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend Edit with Eq::{not_equal, equal}

///|
pub fn Edit::new() -> Edit {
  { encoding: "utf-8", }
}

///|
impl Tool for Edit with fn name(_self) -> String {
  "edit"
}

///|
impl Tool for Edit with fn description(_self) -> String {
  "Performs exact string replacements in files.\n" +
  "- old_str must include all whitespace, indentation, and surrounding code exactly.\n" +
  "- Use replace_all for replacing all occurrences.\n" +
  "- ALWAYS prefer editing existing files. NEVER write new files unless explicitly required.\n" +
  "- CRITICAL: filePath must be returned before other fields."
}

///|
impl Tool for Edit with fn parameters(_) -> Json {
  Json::object({
    "type": Json("object"),
    "properties": Json::object({
      "path": Json::object({
        "type": Json("string"),
        "description": Json("The absolute path to the file to modify"),
      }),
      "old_string": Json::object({
        "type": Json("string"),
        "description": Json("The text to replace"),
      }),
      "new_string": Json::object({
        "type": Json("string"),
        "description": Json("The text to replace it with"),
      }),
      "replace_all": Json::object({
        "type": Json("boolean"),
        "description": Json(
          "Replace all occurrences of old_string (default false)",
        ),
      }),
    }),
    "required": [Json("path"), Json("old_string"), Json("new_string")],
  })
}

///|
impl Tool for Edit with fn category(_) -> ToolCategory {
  FileSystem
}

///|
impl Tool for Edit with fn execute(_, args : Map[String, Json]) -> ToolResult {
  let path = match args.get("path") {
    Some(String(s)) => s
    _ => return ToolResult::error("Missing required parameter: path")
  }
  let old_string = match args.get("old_string") {
    Some(String(s)) => s
    _ => return ToolResult::error("Missing required parameter: old_string")
  }
  let new_string = match args.get("new_string") {
    Some(String(s)) => s
    _ => return ToolResult::error("Missing required parameter: new_string")
  }
  let replace_all = get_bool_arg(args, "replace_all", false)

  guard !old_string.is_empty() else {
    return ToolResult::error("old_string cannot be empty")
  }

  if !@fs.path_exists(path) {
    return ToolResult::error("File not found: \{path}")
  }

  let content = match read_file_scrubbed(path) {
    Some(c) => c
    None => return ToolResult::error("Failed to read file: \{path}")
  }

  let old_string = @utils.sanitize_string(old_string)
  let new_string = @utils.sanitize_string(new_string)

  let match_result = match find_match(content, old_string) {
    Some(m) => m
    None =>
      return ToolResult::error(
        "old_string not found in file: \{path}. The string must match exactly including whitespace.",
      )
  }

  let matched = match_result.matched_string
  let occurrences = match_result.occurrences

  if !replace_all && occurrences > 1 {
    return ToolResult::error(
      "old_string appears \{occurrences} times. Set replace_all to true or provide more context.",
    )
  }

  let new_content = if replace_all {
    content.replace_all(old=matched, new=new_string)
  } else {
    match content.find(matched) {
      Some(idx) =>
        content[:idx].to_owned() +
        new_string +
        content[idx + matched.length():].to_owned()
      None => content
    }
  }

  if is_secret_path(path) {
    return ToolResult::error(
      "Write to credential/secret path blocked: \{path}.",
    )
  }

  @fs.write_string_to_file(path, new_content) catch {
    _ => return ToolResult::error("Failed to write file: \{path}")
  }
  let count = if replace_all { occurrences } else { 1 }
  ToolResult::success("Modified \{count} occurrence(s) in \{path}")
}

///|
impl Tool for Edit with fn format_call(_, args : Map[String, Json]) -> String {
  match args.get("path") {
    Some(String(p)) => "Edit(\{get_basename(p)})"
    _ => "Edit(?)"
  }
}

///|
impl Tool for Edit with fn format_result(_, result : ToolResult) -> String {
  result.content
}

///|
impl Tool for Edit with fn to_function_definition(self) -> FunctionDefinition {
  FunctionDefinition::new(self.name(), self.description(), self.parameters())
}
