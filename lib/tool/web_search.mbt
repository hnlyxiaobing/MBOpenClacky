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
impl Tool for WebSearch with fn name(_) -> String {
  "web_search"
}

///|
impl Tool for WebSearch with fn description(_) -> String {
  "- Allows searching the web and using the results to inform responses\n" +
  "- Provides up-to-date information for current events and recent data\n" +
  "- The search results will include relevant snippets and URLs"
}

///|
impl Tool for WebSearch with fn parameters(_) -> Json {
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
impl Tool for WebSearch with fn category(_) -> ToolCategory {
  Web
}

///|
impl Tool for WebSearch with fn execute(self, args : Map[String, Json]) -> ToolResult {
  let query = match args.get("query") {
    Some(String(s)) => s
    _ => return ToolResult::error("Missing required parameter: query")
  }
  guard !query.trim().is_empty() else {
    return ToolResult::error("Query cannot be empty")
  }
  let max = get_int_arg(args, "max_results", self.max_results)
  let capped = if max > 20 { 20 } else if max < 1 { 10 } else { max }

  // Use DuckDuckGo HTML search (no API key required)
  let encoded_query = url_encode(query)
  let search_url = "https://html.duckduckgo.com/html/?q=\{encoded_query}"
  let headers : Array[(String, String)] = [
    ("User-Agent", "Mozilla/5.0 (compatible; MBOpenClacky/1.0)"),
    ("Accept", "text/html"),
  ]
  let result = @client.http_get(search_url, headers, 15000)
  match result {
    Ok(response) =>
      if response.status_code >= 200 && response.status_code < 300 {
        let results = parse_search_results(response.body, capped)
        if results.length() == 0 {
          ToolResult::success("No search results found for: \{query}")
        } else {
          ToolResult::success(format_results(results))
        }
      } else {
        ToolResult::error(
          "HTTP error \{response.status_code} searching for: \{query}",
        )
      }
    Err(err) => ToolResult::error("Failed to search: \{err.to_repr()}")
  }
}

///|
impl Tool for WebSearch with fn format_call(_, args : Map[String, Json]) -> String {
  match args.get("query") {
    Some(String(q)) => {
      let display = if q.length() > 40 { q[:40].to_owned() + "..." } else { q }
      "web_search(\"\{display}\")"
    }
    _ => "web_search(?)"
  }
}

///|
impl Tool for WebSearch with fn format_result(_, result : ToolResult) -> String {
  if result.is_error {
    result.content
  } else {
    "[OK] WebSearch completed"
  }
}

///|
impl Tool for WebSearch with fn to_function_definition(self) -> FunctionDefinition {
  FunctionDefinition::new(self.name(), self.description(), self.parameters())
}

// ── Helpers ─────────────────────────────────────────────────────────────────

///|
/// A single search result.
priv struct SearchResult {
  title : String
  url : String
  snippet : String
}

///|
/// Simple URL encoder for query strings.
fn url_encode(s : String) -> String {
  let mut result = ""
  let chars = s.iter()
  for ch in chars {
    let c = ch.to_string()
    if c == " " {
      result = result + "+"
    } else if c == "&" {
      result = result + "%26"
    } else if c == "=" {
      result = result + "%3D"
    } else if c == "?" {
      result = result + "%3F"
    } else if c == "#" {
      result = result + "%23"
    } else if c == "+" {
      result = result + "%2B"
    } else {
      result = result + c
    }
  }
  result
}

///|
/// Parse search results from DuckDuckGo HTML response.
fn parse_search_results(
  html : String,
  max_results : Int,
) -> Array[SearchResult] {
  let results : Array[SearchResult] = []
  // Simple extraction: look for result links and snippets in DuckDuckGo HTML
  // DuckDuckGo HTML has results in <a> tags with class "result__a" and snippets in "result__snippet"
  let mut pos = 0
  let html_len = html.length()
  while pos < html_len && results.length() < max_results {
    // Find result link: <a rel="nofollow" class="result__a" href="URL">TITLE</a>
    let link_marker = "class=\"result__a\""
    let link_pos = html[find_substring(html, link_marker, pos):].to_owned()
    if link_pos.length() == 0 {
      break
    }
    let abs_link_pos = html_len - link_pos.length()
    // Find href
    let href_start = find_substring(html, "href=\"", abs_link_pos)
    if href_start < 0 {
      pos = abs_link_pos + 1
      continue
    }
    let href_value_start = href_start + 6
    let href_end = find_substring(html, "\"", href_value_start)
    if href_end < 0 {
      pos = abs_link_pos + 1
      continue
    }
    let url = html[href_value_start:href_end].to_owned()
    // Find title (between > and </a>)
    let title_start = find_substring(html, ">", href_end)
    if title_start < 0 {
      pos = abs_link_pos + 1
      continue
    }
    let title_value_start = title_start + 1
    let title_end = find_substring(html, "</a>", title_value_start)
    if title_end < 0 {
      pos = abs_link_pos + 1
      continue
    }
    let title = strip_simple_html(html[title_value_start:title_end].to_owned())
    // Find snippet
    let snippet_marker = "class=\"result__snippet\""
    let snippet_pos = find_substring(html, snippet_marker, title_end)
    let snippet = if snippet_pos >= 0 {
      let snip_start = find_substring(html, ">", snippet_pos)
      if snip_start >= 0 {
        let snip_value_start = snip_start + 1
        let snip_end = find_substring(html, "</", snip_value_start)
        if snip_end >= 0 {
          strip_simple_html(html[snip_value_start:snip_end].to_owned())
        } else {
          ""
        }
      } else {
        ""
      }
    } else {
      ""
    }
    if url.length() > 0 && title.length() > 0 {
      results.push({ title, url, snippet })
    }
    pos = if snippet_pos >= 0 { snippet_pos + 1 } else { title_end + 1 }
  }
  results
}

///|
/// Find substring position in string starting from offset.
fn find_substring(haystack : String, needle : String, start : Int) -> Int {
  let h_len = haystack.length()
  let n_len = needle.length()
  if start < 0 || start + n_len > h_len {
    return -1
  }
  for i = start; i <= h_len - n_len; i = i + 1 {
    if haystack[i:i + n_len].to_owned() == needle {
      return i
    }
  }
  -1
}

///|
/// Strip simple HTML tags from a string.
fn strip_simple_html(s : String) -> String {
  let mut result = ""
  let mut in_tag = false
  let chars = s.iter()
  for ch in chars {
    if ch == '<' {
      in_tag = true
    } else if ch == '>' {
      in_tag = false
    } else if !in_tag {
      result = result + ch.to_string()
    }
  }
  result
  .replace(old="&nbsp;", new=" ")
  .replace(old="&amp;", new="&")
  .replace(old="&lt;", new="<")
  .replace(old="&gt;", new=">")
  .replace(old="&quot;", new="\"")
  .replace(old="&#39;", new="'")
  .trim()
  .to_owned()
}

///|
/// Format search results into a readable string.
fn format_results(results : Array[SearchResult]) -> String {
  let mut output = ""
  let mut index = 1
  for r in results {
    output = output + "\{index}. \{r.title}\n"
    output = output + "   URL: \{r.url}\n"
    if r.snippet.length() > 0 {
      output = output + "   \{r.snippet}\n"
    }
    output = output + "\n"
    index = index + 1
  }
  output
}
