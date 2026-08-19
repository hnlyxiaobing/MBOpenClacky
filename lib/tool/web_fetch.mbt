///| WebFetch tool: fetch and parse web page content.

///|

///| Fetches HTTP/HTTPS URLs and extracts text content.

///|
/// Reference: D:/MoonBit/openclacky/lib/clacky/tools/web_fetch.rb
pub(all) struct WebFetch {
  max_length : Int
} derive(Eq, Debug)

///|
pub extend WebFetch with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend WebFetch with Eq::{not_equal, equal}

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
  "Fetch and parse content from a web page. Returns the page content, title, and metadata."
}

///|
impl Tool for WebFetch with fn parameters(_) -> Json {
  Json::object({
    "type": "object".to_json(),
    "properties": Json::object({
      "url": Json::object({
        "type": "string".to_json(),
        "description": "The URL to fetch (must be a valid HTTP/HTTPS URL)".to_json(),
      }),
      "max_length": Json::object({
        "type": "integer".to_json(),
        "description": "Maximum content length to return in characters (default: 3000)".to_json(),
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
    Some(String(s)) => s.trim().to_owned()
    _ => return ToolResult::error("Missing required parameter: url")
  }

  // Ruby web_fetch.rb validates the URL with URI.parse and rejects anything
  // that is not URI::HTTP/URI::HTTPS. We do the same without rewriting the
  // scheme: no http→https upgrade and no auto-prepending of "https://".
  if !url.has_prefix("http://") && !url.has_prefix("https://") {
    return ToolResult::error("URL must be HTTP or HTTPS")
  }

  let max_len = get_int_arg(args, "max_length", self.max_length)

  // Send HTTP GET request, following redirects (sites like cn.bing.com 302
  // to a local endpoint; treating 3xx as a hard error made many fetches fail
  // for no reason). Transient connection failures get one retry.
  // Accept-Language is critical: without it, many sites' anti-scraping
  // mechanisms reject the request as non-browser traffic (HTTP 412).
  // Reference: openclacky/lib/clacky/tools/web_fetch.rb fetch_url headers.
  let headers : Array[(String, String)] = [
    (
      "User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36",
    ),
    (
      "Accept", "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    ),
    ("Accept-Language", "zh-CN,zh;q=0.9,en;q=0.8"),
  ]
  let first = http_get_follow_redirects(url, headers, 15000, 5)
  let result = match first {
    Err(err) if @client.is_retryable(err) =>
      // One retry: ReaderClosed / connection reset / timeout are often
      // transient, and the retry frequently succeeds.
      http_get_follow_redirects(url, headers, 15000, 5)
    other => other
  }
  match result {
    Ok(response) =>
      if response.status_code >= 200 && response.status_code < 300 {
        build_fetch_result(strip_html_tags(response.body), max_len)
      } else {
        ToolResult::error("HTTP error \{response.status_code} fetching \{url}")
      }
    Err(err) => ToolResult::error("Failed to fetch \{url}: \{err.to_repr()}")
  }
}

///|
/// Build the final ToolResult from fetched text. When the text exceeds
/// max_len the FULL content is spilled to a sidecar temp file and the
/// head is returned with a pointer to it (Ruby web_fetch.rb: truncated +
/// temp_file fields).
fn build_fetch_result(text : String, max_len : Int) -> ToolResult {
  if text.length() > max_len {
    let head = safe_truncate(text, max_len)
    match spill_overflow_file(text) {
      Some(path) =>
        ToolResult::success(
          head +
          "\n[Content truncated for LLM. Full content saved to: " +
          path +
          "]",
        )
      None => ToolResult::success(head + "\n[truncated]")
    }
  } else {
    ToolResult::success(text)
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
/// Strip leading "http(s)://" and the path, keeping only the host:port.
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
