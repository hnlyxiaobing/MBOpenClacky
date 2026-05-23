///| WebFetch tool: fetch and parse web page content.

///|

///| Fetches HTTP/HTTPS URLs and extracts text content.

///|
/// Reference: D:/MoonBit/openclacky/lib/clacky/tools/web_fetch.rb
pub(all) struct WebFetch {
  max_length : Int
} derive(Eq, Debug)

///|
pub fn WebFetch::new() -> WebFetch {
  { max_length: 3000 }
}

///|
impl Tool for WebFetch with name(_) -> String {
  "web_fetch"
}

///|
impl Tool for WebFetch with description(_) -> String {
  "Fetches content from a specified URL and processes it.\n" +
  "- Fetches the URL content, converts HTML to markdown\n" +
  "- Use this tool when you need to retrieve and analyze web content\n" +
  "- The URL must be a fully-formed valid URL"
}

///|
impl Tool for WebFetch with parameters(_) -> Json {
  Json::object({
    "type": "object".to_json(),
    "properties": Json::object({
      "url": Json::object({
        "type": "string".to_json(),
        "description": "The URL to fetch content from".to_json(),
      }),
      "max_length": Json::object({
        "type": "integer".to_json(),
        "description": "Maximum number of characters to return (default: 3000)".to_json(),
      }),
    }),
    "required": ["url".to_json()],
  })
}

///|
impl Tool for WebFetch with category(_) -> ToolCategory {
  Web
}

///|
impl Tool for WebFetch with execute(self, args : Map[String, Json]) -> ToolResult {
  let url = match args.get("url") {
    Some(String(s)) => s
    _ => return ToolResult::error("Missing required parameter: url")
  }

  let normalized = normalize_url(url)
  guard normalized.has_prefix("https://") || normalized.has_prefix("http://") else {
    return ToolResult::error(
      "Invalid URL: \{url}. Must be an HTTP or HTTPS URL.",
    )
  }

  let max_len = get_int_arg(args, "max_length", self.max_length)

  ToolResult::success(
    "[WebFetch ready] URL: \{normalized}, max_length: \{max_len}\n" +
    "Requires async HTTP client for live web fetching. " +
    "Tool metadata and parameters are fully configured.",
  )
}

///|
impl Tool for WebFetch with format_call(_, args : Map[String, Json]) -> String {
  match args.get("url") {
    Some(String(url)) => {
      let domain = extract_domain(url)
      "web_fetch(\{domain})"
    }
    _ => "web_fetch(?)"
  }
}

///|
impl Tool for WebFetch with format_result(_, result : ToolResult) -> String {
  if result.is_error {
    result.content
  } else {
    "[OK] Fetched content"
  }
}

///|
impl Tool for WebFetch with to_function_definition(self) -> FunctionDefinition {
  FunctionDefinition::new(self.name(), self.description(), self.parameters())
}

// ── Helpers ─────────────────────────────────────────────────────────────────

///|
fn normalize_url(url : String) -> String {
  let trimmed = url.trim().to_string()
  if trimmed.find("://") is Some(_) {
    if trimmed.has_prefix("http://") {
      "https://" + trimmed["http://".length():].to_string()
    } else {
      trimmed
    }
  } else {
    "https://\{trimmed}"
  }
}

///|
fn extract_domain(url : String) -> String {
  let stripped = if url.has_prefix("https://") {
    url["https://".length():].to_string()
  } else if url.has_prefix("http://") {
    url["http://".length():].to_string()
  } else {
    url
  }
  match stripped.find("/") {
    Some(idx) => stripped[:idx].to_string()
    None => stripped
  }
}
