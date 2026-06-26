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
impl Tool for WebFetch with fn name(_) -> String {
  "web_fetch"
}

///|
impl Tool for WebFetch with fn description(_) -> String {
  "Fetches content from a specified URL and processes it.\n" +
  "- Fetches the URL content, converts HTML to markdown\n" +
  "- Use this tool when you need to retrieve and analyze web content\n" +
  "- The URL must be a fully-formed valid URL"
}

///|
impl Tool for WebFetch with fn parameters(_) -> Json {
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
impl Tool for WebFetch with fn category(_) -> ToolCategory {
  Web
}

///|
impl Tool for WebFetch with fn execute(self, args : Map[String, Json]) -> ToolResult {
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

  // Send HTTP GET request
  let headers : Array[(String, String)] = [
    ("User-Agent", "Mozilla/5.0 (compatible; MBOpenClacky/1.0)"),
    ("Accept", "text/html,application/xhtml+xml,text/plain"),
  ]
  let result = @client.http_get(normalized, headers, 15000)
  match result {
    Ok(response) => {
      if response.status_code >= 200 && response.status_code < 300 {
        let text = strip_html_tags(response.body)
        let truncated = if text.length() > max_len {
          text[:max_len].to_owned() + "\n[truncated]"
        } else {
          text
        }
        ToolResult::success(truncated)
      } else {
        ToolResult::error(
          "HTTP error \{response.status_code} fetching \{normalized}",
        )
      }
    }
    Err(err) => ToolResult::error("Failed to fetch \{normalized}: \{err}")
  }
}

///|
impl Tool for WebFetch with fn format_call(_, args : Map[String, Json]) -> String {
  match args.get("url") {
    Some(String(url)) => {
      let domain = extract_domain(url)
      "web_fetch(\{domain})"
    }
    _ => "web_fetch(?)"
  }
}

///|
impl Tool for WebFetch with fn format_result(_, result : ToolResult) -> String {
  if result.is_error {
    result.content
  } else {
    "[OK] Fetched content"
  }
}

///|
impl Tool for WebFetch with fn to_function_definition(self) -> FunctionDefinition {
  FunctionDefinition::new(self.name(), self.description(), self.parameters())
}

// ── Helpers ─────────────────────────────────────────────────────────────────

///|
/// Simple HTML tag stripper: removes all <...> tags and decodes common entities.
fn strip_html_tags(html : String) -> String {
  let mut result = ""
  let mut in_tag = false
  let chars = html.iter()
  for ch in chars {
    if ch == '<' {
      in_tag = true
    } else if ch == '>' {
      in_tag = false
    } else if !in_tag {
      result = result + ch.to_string()
    }
  }
  // Decode common HTML entities
  result
    .replace(old="&nbsp;", new=" ")
    .replace(old="&amp;", new="&")
    .replace(old="&lt;", new="<")
    .replace(old="&gt;", new=">")
    .replace(old="&quot;", new="\"")
    .replace(old="&#39;", new="'")
}

///|
fn normalize_url(url : String) -> String {
  let trimmed = url.trim().to_owned()
  if trimmed.find("://") is Some(_) {
    if trimmed.has_prefix("http://") {
      "https://" + trimmed["http://".length():].to_owned()
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
    url["https://".length():].to_owned()
  } else if url.has_prefix("http://") {
    url["http://".length():].to_owned()
  } else {
    url
  }
  match stripped.find("/") {
    Some(idx) => stripped[:idx].to_owned()
    None => stripped
  }
}
