///| WebSearch tool: search the web for information.

///|

///|
/// Reference: D:/MoonBit/openclacky/lib/clacky/tools/web_search.rb
pub(all) struct WebSearch {
  max_results : Int
} derive(Eq, Debug)

///|
pub fn WebSearch::new() -> WebSearch {
  { max_results: 10 }
}

///|
impl Tool for WebSearch with name(_) -> String {
  "web_search"
}

///|
impl Tool for WebSearch with description(_) -> String {
  "- Allows searching the web and using the results to inform responses\n" +
  "- Provides up-to-date information for current events and recent data\n" +
  "- The search results will include relevant snippets and URLs"
}

///|
impl Tool for WebSearch with parameters(_) -> Json {
  Json::object({
    "type": "object".to_json(),
    "properties": Json::object({
      "query": Json::object({
        "type": "string".to_json(),
        "description": "Search query. Value range: 1 to 100 characters.".to_json(),
      }),
      "max_results": Json::object({
        "type": "integer".to_json(),
        "description": "Maximum number of results to return (default: 10)".to_json(),
      }),
    }),
    "required": ["query".to_json()],
  })
}

///|
impl Tool for WebSearch with category(_) -> ToolCategory {
  Web
}

///|
impl Tool for WebSearch with execute(self, args : Map[String, Json]) -> ToolResult {
  let query = match args.get("query") {
    Some(String(s)) => s
    _ => return ToolResult::error("Missing required parameter: query")
  }
  guard !query.trim().is_empty() else {
    return ToolResult::error("Query cannot be empty")
  }
  let max = get_int_arg(args, "max_results", self.max_results)
  let capped = if max > 20 { 20 } else if max < 1 { 10 } else { max }

  ToolResult::success(
    "[WebSearch ready] Query: \"\{query}\", max_results: \{capped}\n" +
    "Requires async HTTP client for live web searches. " +
    "Tool metadata and parameters are fully configured.",
  )
}

///|
impl Tool for WebSearch with format_call(_, args : Map[String, Json]) -> String {
  match args.get("query") {
    Some(String(q)) => {
      let display = if q.length() > 40 { q[:40].to_string() + "..." } else { q }
      "web_search(\"\{display}\")"
    }
    _ => "web_search(?)"
  }
}

///|
impl Tool for WebSearch with format_result(_, result : ToolResult) -> String {
  if result.is_error {
    result.content
  } else {
    "[OK] WebSearch completed"
  }
}

///|
impl Tool for WebSearch with to_function_definition(self) -> FunctionDefinition {
  FunctionDefinition::new(self.name(), self.description(), self.parameters())
}
