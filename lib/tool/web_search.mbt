///| WebSearch tool: search the web for information.

///| Tries multiple providers in a fallback chain (DuckDuckGo → Bing) so

///| searches keep working in network environments where a single provider

///| is blocked or unreachable (e.g. mainland China cannot reach DuckDuckGo).

///| Mirrors the original openclacky implementation:

///|   - DuckDuckGo HTML endpoint, decoding the real URL from its `uddg` param

///|   - Bing dual endpoints (cn.bing.com then www.bing.com), `form=QBLH`,

///|     relevance filtering to reject anti-scrape filler, and `/ck/a`

///|     redirect-URL decoding

///|   - DuckDuckGo is suppressed for 10 minutes after a failure so later

///|     searches don't burn a full timeout on every call.

///|

///|
/// Reference: D:/MoonBit/openclacky/lib/clacky/tools/web_search.rb
pub(all) struct WebSearch {
  max_results : Int
} derive(Eq, Debug)

///|
pub extend WebSearch with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend WebSearch with Eq::{not_equal, equal}

///|
/// Process-level memory: epoch-ms until which DuckDuckGo is skipped after a
/// failure (mirrors the original `@ddg_unavailable_until = Time.now + 600`).
let ddg_unavailable_until_ms : Ref[Int64] = Ref(0L)

///|
/// A single search result.
priv struct SearchResult {
  title : String
  url : String
  snippet : String
}

///|
/// How long to suppress DuckDuckGo after a failed search (10 minutes).
let ddg_cooldown_ms : Int64 = 600_000L

///|
/// Search providers in fallback order (matches the original PROVIDERS, plus
/// a configured custom searcher from ~/.clacky/searchers/).
priv enum SearchProvider {
  DuckDuckGo
  Bing
  Custom(String) // provider basename from ~/.clacky/search.yml
} derive(Eq)

///|
/// How long a configured searcher script may run before it is killed
/// (original SEARCHER_TIMEOUT = 30s).
let searcher_timeout_ms : Int = 30_000

///|
/// Build the provider chain to try for this search. An explicitly configured
/// searcher is authoritative (original `active_providers`): it is the only
/// provider tried — never falling back to a built-in scraper, which would
/// silently ignore the user's choice and make a broken key or script look
/// like a low-quality result set. A provider whose script is not installed
/// is treated as unset so web_search falls back to the built-ins instead of
/// erroring on every search. DuckDuckGo is skipped for 10 minutes after it
/// has failed once.

///|
/// Build the provider chain for an explicitly-resolved (provider, script)
/// pair. A configured searcher is authoritative (original
/// `active_providers`): it is the only provider tried — never falling back
/// to a built-in scraper, which would silently ignore the user's choice and
/// make a broken key or script look like a low-quality result set.
/// A provider whose script is not installed is treated as unset so
/// web_search falls back to the built-ins instead of erroring.
fn build_provider_chain_with(
  provider : String,
  script_path : String?,
) -> Array[SearchProvider] {
  if !provider.is_empty() && script_path is Some(_) {
    return [Custom(provider)]
  }
  let now_ms = @env.now().reinterpret_as_int64()
  if now_ms < ddg_unavailable_until_ms.val {
    [Bing]
  } else {
    [DuckDuckGo, Bing]
  }
}

///|
fn build_provider_chain() -> Array[SearchProvider] {
  let (provider, _key) = read_search_config()
  build_provider_chain_with(provider, custom_searcher_path(provider))
}

///|
fn provider_name(p : SearchProvider) -> String {
  match p {
    DuckDuckGo => "DuckDuckGo"
    Bing => "Bing"
    Custom(name) => name
  }
}

///|
/// Browser User-Agents, sampled per request (original USER_AGENTS list plus
/// Edge/Firefox/Safari — Bing and DDG sometimes blanket-ban Chrome UAs from
/// datacenter IPs, returning 307/captcha instead of results).
let user_agents : Array[String] = [
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36",
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36",
  "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36 Edg/126.0.0.0",
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:127.0) Gecko/20100101 Firefox/127.0",
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15",
]

///|
/// Pick a pseudo-random User-Agent (clock-seeded; good enough for scraping).
fn random_ua() -> String {
  let now = @env.now().reinterpret_as_int64()
  let idx = (now % user_agents.length().to_int64()).to_int()
  user_agents[idx]
}

///|
/// Bing endpoints, cn.bing.com first (accessible from mainland China), then
/// www.bing.com (original BING_ENDPOINTS). Each carries its own language.
let bing_endpoints : Array[(String, String)] = [
  ("cn.bing.com", "zh-CN,zh;q=0.9,en;q=0.8"),
  ("www.bing.com", "en-US,en;q=0.9"),
]

///|
/// Browser-like request headers for DuckDuckGo (original shared `http_get`).
fn ddg_headers() -> Array[(String, String)] {
  [
    ("User-Agent", random_ua()),
    (
      "Accept", "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    ),
    ("Accept-Language", "en-US,en;q=0.9"),
    ("Sec-Fetch-Dest", "document"),
    ("Sec-Fetch-Mode", "navigate"),
    ("Sec-Fetch-Site", "none"),
    ("Upgrade-Insecure-Requests", "1"),
    // Accept-Encoding is deliberately omitted: sending gzip makes Bing return
    // a JS-only skeleton instead of real HTML results (original comment).
  ]
}

///|
/// Browser-like request headers for Bing, with Referer (original `http_get`).
fn bing_headers(lang : String, host : String) -> Array[(String, String)] {
  [
    ("User-Agent", random_ua()),
    (
      "Accept", "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    ),
    ("Accept-Language", lang),
    ("Sec-Fetch-Dest", "document"),
    ("Sec-Fetch-Mode", "navigate"),
    ("Sec-Fetch-Site", "same-origin"),
    ("Upgrade-Insecure-Requests", "1"),
    ("Referer", "https://\{host}/"),
  ]
}

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
  // No hard cap (original passes max_results straight to the providers).
  let capped = if max < 1 { 10 } else { max }

  // Percent-encode the query as UTF-8 (original CGI.escape). Un-encoded CJK
  // bytes in the request line make Bing answer HTTP 400.
  let encoded_query = url_encode(query)
  let providers = build_provider_chain()
  let failures : Array[String] = []
  for provider in providers {
    let results = match provider {
      DuckDuckGo => search_ddg(encoded_query, capped)
      Bing => search_bing(query, encoded_query, capped)
      Custom(name) =>
        match search_custom(query, capped, name) {
          Ok(r) => r
          Err(msg) => {
            failures.push(msg)
            continue
          }
        }
    }
    if results.length() > 0 {
      if provider == DuckDuckGo {
        // DuckDuckGo works again: clear the suppression window.
        ddg_unavailable_until_ms.val = 0L
        return ToolResult::success(format_results(results))
      }
      // Bing: accept only relevant results; anti-scrape filler shares no
      // token with the query (original `bing_results_relevant?`).
      if bing_results_relevant(results, query) {
        return ToolResult::success(format_results(results))
      } else {
        failures.push("\{provider_name(provider)} returned no relevant results")
      }
    } else {
      failures.push("\{provider_name(provider)} returned no results")
      if provider == DuckDuckGo {
        // Suppress DuckDuckGo for 10 minutes (original 600s cooldown).
        ddg_unavailable_until_ms.val = @env.now().reinterpret_as_int64() +
          ddg_cooldown_ms
      }
    }
  }
  let detail = failures.join(" | ")
  match providers {
    [Custom(name)] => {
      // The only configured provider failed — tell the user where to look
      // (original `search_failure_message` for the :custom-only case).
      let script_path = match custom_searcher_path(name) {
        Some(p) => p
        None => "<~/.clacky/searchers/>"
      }
      ToolResult::error(
        "Configured search provider '\{name}' failed. Last error: \{detail}. " +
        "Check the key and the script at \{script_path}, or reconfigure it " +
        "in Settings → Search.",
      )
    }
    _ =>
      ToolResult::error("All search providers failed for: \{query} \{detail}")
  }
}

///|
// ── Configured searcher (~/.clacky/searchers/) ────────────────────────────

///|
/// Absolute path of ~/.clacky/search.yml.
fn search_config_path() -> String {
  match home_dir() {
    Some(h) =>
      @path.Path::join(@path.Path(h), @path.Path(".clacky/search.yml")).to_string()
    None => "~/.clacky/search.yml"
  }
}

///|
/// Read (provider, key) from ~/.clacky/search.yml. A missing or corrupt
/// file yields ("", "") so web_search falls back to the built-in engines
/// (original SearchConfig.load rescue).
fn read_search_config() -> (String, String) {
  let path = search_config_path()
  if !@fs.path_exists(path) {
    return ("", "")
  }
  let content = @fs.read_file_to_string(path) catch { _ => return ("", "") }
  parse_search_config(content)
}

///|
/// Parse `provider:` and `key:` lines out of a search.yml-style string
/// (line-based; no YAML dependency).
fn parse_search_config(content : String) -> (String, String) {
  let mut provider = ""
  let mut key = ""
  for line in content.split("\n") {
    let t = line.trim().to_owned()
    if t.has_prefix("provider:") {
      provider = t[9:].to_owned().trim().to_owned()
    } else if t.has_prefix("key:") {
      key = t[4:].to_owned().trim().to_owned()
    }
  }
  (provider, key)
}

///|
/// Absolute path of the configured searcher script, or None when the
/// provider is unset or its script is not installed (original
/// `SearchConfig.script_path` — a missing script is treated as unset so
/// web_search falls back to the built-ins instead of erroring).
fn custom_searcher_path(provider : String) -> String? {
  if provider.is_empty() {
    return None
  }
  match home_dir() {
    None => None
    Some(h) => searcher_path_in(h, provider)
  }
}

///|
/// Look for <provider>.rb then <provider>.py inside the given searchers
/// directory (the original tries .rb before .py).
fn searcher_path_in(home : String, provider : String) -> String? {
  let dir = @path.Path::join(@path.Path(home), @path.Path(".clacky/searchers"))
  let rb = @path.Path::join(dir, @path.Path(provider + ".rb")).to_string()
  if @fs.path_exists(rb) {
    return Some(rb)
  }
  let py = @path.Path::join(dir, @path.Path(provider + ".py")).to_string()
  if @fs.path_exists(py) {
    return Some(py)
  }
  None
}

///|
/// Quote a single argument for the platform shell (bash -c on Unix,
/// cmd.exe .bat on Windows) so queries survive metacharacters.
fn shell_quote(arg : String) -> String {
  if is_windows_platform() {
    "\"" + arg.replace(old="\"", new="\"\"") + "\""
  } else {
    "'" + arg.replace(old="'", new="'\\''") + "'"
  }
}

///|
/// Last index of `needle` in `haystack`, or -1 (find_substring walks
/// forward; used to slice the trailing ']' of the searcher's JSON array).
fn last_index_of(haystack : String, needle : String) -> Int {
  let mut pos = find_substring(haystack, needle, 0)
  let mut last = pos
  while pos >= 0 {
    last = pos
    pos = find_substring(haystack, needle, pos + 1)
  }
  last
}

///|
/// Run the configured searcher script (original `search_custom`):
///   <interpreter> <script> "<query>" <max_results>
/// with CLACKY_SEARCH_KEY in the environment. stdout must be a JSON array
/// of {title, url, snippet} objects; empty-url items are dropped.
async fn search_custom(
  query : String,
  max_results : Int,
  provider_name : String,
) -> Result[Array[SearchResult], String] {
  let script = match custom_searcher_path(provider_name) {
    Some(p) => p
    None => return Err("Searcher script not found for '\{provider_name}'")
  }
  let (_provider, key) = read_search_config()
  search_custom_script(script, query, max_results, key)
}

///|
/// Run a searcher script directly (core of `search_custom`, testable without
/// touching ~/.clacky): `<interpreter> <script> "<query>" <max_results>`
/// with CLACKY_SEARCH_KEY in the environment, and the same timeout/exit/JSON
/// handling as the original.
async fn search_custom_script(
  script : String,
  query : String,
  max_results : Int,
  key : String,
) -> Result[Array[SearchResult], String] {
  let interpreter = if script.has_suffix(".rb") { "ruby" } else { "python3" }
  let cmd = interpreter +
    " " +
    shell_quote(script) +
    " " +
    shell_quote(query) +
    " " +
    max_results.to_string()
  let (output, exit_code, _out_file, timed_out) = execute_command_sync(
    cmd,
    ".",
    searcher_timeout_ms,
    @env.now().reinterpret_as_int64().to_int(),
    Map::from_array([("CLACKY_SEARCH_KEY", key)]),
  )
  if timed_out {
    return Err("Searcher timed out after 30s")
  }
  if exit_code != 0 {
    let stderr = output.trim().to_owned()
    if stderr.is_empty() {
      return Err("Searcher exited with \{exit_code}")
    }
    return Err(stderr)
  }
  parse_custom_results(output, max_results)
}

///|
/// Parse the searcher's JSON-array stdout into SearchResults (original
/// `parse_custom_results`). stderr may be interleaved with stdout, so the
/// JSON array is extracted from the first '[' to the last ']'.
fn parse_custom_results(
  raw : String,
  max_results : Int,
) -> Result[Array[SearchResult], String] {
  let text = raw.trim().to_owned()
  let start = find_substring(text, "[", 0)
  if start < 0 {
    return Err("Searcher must output a JSON array")
  }
  let end = last_index_of(text, "]")
  if end <= start {
    return Err("Searcher must output a JSON array")
  }
  let parsed = @json.parse(text[start:end + 1]) catch {
    _ => return Err("Searcher must output a JSON array")
  }
  let items = match parsed {
    Json::Array(arr) => arr
    _ => return Err("Searcher must output a JSON array")
  }
  let results : Array[SearchResult] = []
  for item in items {
    if results.length() >= max_results {
      break
    }
    let obj = match item {
      Json::Object(o) => o
      _ => continue
    }
    let url = match obj.get("url") {
      Some(Json::String(s)) => s
      _ => continue
    }
    if url.is_empty() {
      continue
    }
    let title = match obj.get("title") {
      Some(Json::String(s)) => s
      _ => ""
    }
    let snippet = match obj.get("snippet") {
      Some(Json::String(s)) => s
      _ => ""
    }
    results.push({ title, url, snippet })
  }
  Ok(results)
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
    "[OK] Found search results"
  }
}

///|
impl Tool for WebSearch with fn to_function_definition(self) -> FunctionDefinition {
  FunctionDefinition::new(self.name(), self.description(), self.parameters())
}

// ── Providers ────────────────────────────────────────────────────────────────

///|
/// Query DuckDuckGo's HTML endpoint. The real target URL is hidden in the
/// `uddg` parameter of a `//duckduckgo.com/l/?uddg=...` redirect link.
/// Timeout raised from 8s to 15s to reduce spurious failures on slow networks
/// (mainland China accessing DDG often exceeds 8s due to TLS handshake latency).
/// Retryable errors (ReaderClosed, timeout, connection reset) get one retry.
async fn search_ddg(
  encoded_query : String,
  max_results : Int,
) -> Array[SearchResult] {
  let url = "https://html.duckduckgo.com/html/?q=\{encoded_query}"
  let first = http_get_follow_redirects(url, ddg_headers(), 15000, 5)
  let resp = match first {
    Err(err) if @client.is_retryable(err) =>
      http_get_follow_redirects(url, ddg_headers(), 15000, 5)
    other => other
  }
  match resp {
    Ok(r) if r.status_code >= 200 && r.status_code < 300 =>
      parse_ddg_results(r.body, max_results)
    _ => []
  }
}

///|
/// Query Bing's two endpoints in order and return the first relevant batch
/// (original: race both in parallel; serial here since we have no threads).
/// If neither batch is relevant, fall back to the first non-empty one.
async fn search_bing(
  query : String,
  encoded_query : String,
  max_results : Int,
) -> Array[SearchResult] {
  let mut best : Array[SearchResult] = []
  for endpoint in bing_endpoints {
    let results = bing_fetch(endpoint.0, endpoint.1, encoded_query, max_results)
    if results.length() > 0 {
      if bing_results_relevant(results, query) {
        return results
      }
      if best.length() == 0 {
        best = results
      }
    }
  }
  best
}

///|
/// Single Bing endpoint request with redirect following (original
/// `bing_fetch`, follow_redirects: 2).
/// Timeout raised from 8s to 15s; retryable errors get one automatic retry.
async fn bing_fetch(
  host : String,
  lang : String,
  encoded_query : String,
  max_results : Int,
) -> Array[SearchResult] {
  let url = "https://\{host}/search?q=\{encoded_query}&count=\{max_results}&form=QBLH"
  let first = http_get_follow_redirects(url, bing_headers(lang, host), 15000, 2)
  let resp = match first {
    Err(err) if @client.is_retryable(err) =>
      // One retry for transient errors (ReaderClosed, timeout, connection reset).
      http_get_follow_redirects(url, bing_headers(lang, host), 15000, 2)
    other => other
  }
  match resp {
    Ok(r) if r.status_code >= 200 && r.status_code < 300 =>
      parse_bing_results(r.body, max_results)
    _ => []
  }
}

// ── Parsing ──────────────────────────────────────────────────────────────────

///|
/// Parse DuckDuckGo HTML. The original regex pulls the `uddg` param from
/// `//duckduckgo.com/l/?uddg=URL` and unescapes it to get the real URL.
/// Results that are themselves duckduckgo filler pages ("Web search results")
/// are dropped, matching the original success check.
fn parse_ddg_results(html : String, max_results : Int) -> Array[SearchResult] {
  let results : Array[SearchResult] = []
  let mut pos = 0
  let html_len = html.length()
  while pos < html_len && results.length() < max_results {
    let marker_pos = find_substring(html, "class=\"result__a\"", pos)
    if marker_pos < 0 {
      break
    }
    // <a ... class="result__a" href="//duckduckgo.com/l/?uddg=...">
    let href_start = find_substring(html, "href=\"", marker_pos)
    if href_start < 0 {
      pos = marker_pos + 1
      continue
    }
    let href_value_start = href_start + 6
    let href_end = find_substring(html, "\"", href_value_start)
    if href_end < 0 {
      pos = marker_pos + 1
      continue
    }
    let href = html[href_value_start:href_end].to_owned()
    let uddg_pos = find_substring(href, "uddg=", 0)
    let url = if uddg_pos >= 0 {
      let uddg_value_start = uddg_pos + 5
      let uddg_end = find_substring(href, "&", uddg_value_start)
      let cut = if uddg_end < 0 { href.length() } else { uddg_end }
      url_decode(href[uddg_value_start:cut].to_owned())
    } else {
      ""
    }
    // Title between > and </a>
    let title_start = find_substring(html, ">", href_end)
    if title_start < 0 {
      pos = marker_pos + 1
      continue
    }
    let title_value_start = title_start + 1
    let title_end = find_substring(html, "</a>", title_value_start)
    if title_end < 0 {
      pos = marker_pos + 1
      continue
    }
    let title = strip_simple_html(html[title_value_start:title_end].to_owned())
    // Snippet in class="result__snippet"
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
    // Drop DDG filler results (its "no results" page links back to itself).
    let is_filler = url.contains("duckduckgo.com") &&
      title == "Web search results"
    if url.length() > 0 && title.length() > 0 && !is_filler {
      results.push({ title, url, snippet })
    }
    pos = if snippet_pos >= 0 { snippet_pos + 1 } else { title_end + 1 }
  }
  results
}

///|
/// Parse Bing HTML. Each result is an `<li class="b_algo">` block with an
/// `<h2><a href="URL">TITLE</a></h2>` and a snippet in a `b_lineclamp` `<p>`
/// (or a `.b_caption` block), matching the original regexes.
fn parse_bing_results(html : String, max_results : Int) -> Array[SearchResult] {
  let results : Array[SearchResult] = []
  let mut pos = 0
  let html_len = html.length()
  while pos < html_len && results.length() < max_results {
    let li_pos = find_substring(html, "class=\"b_algo\"", pos)
    if li_pos < 0 {
      break
    }
    let block_end = find_substring(html, "</li>", li_pos)
    let limit = if block_end < 0 { html_len } else { block_end }
    // Title link lives inside <h2>...</h2>. Real Bing output is
    // `<a target="_blank" href="...">` — attributes may precede href, so
    // search for the bare `href="` inside the h2 block, not `<a href="`.
    let h2_pos = find_substring(html, "<h2", li_pos)
    if h2_pos < 0 || h2_pos >= limit {
      pos = li_pos + 1
      continue
    }
    let href_start = find_substring(html, "href=\"", h2_pos)
    if href_start < 0 || href_start >= limit {
      pos = li_pos + 1
      continue
    }
    let url_start = href_start + 6
    let url_end = find_substring(html, "\"", url_start)
    if url_end < 0 || url_end >= limit {
      pos = li_pos + 1
      continue
    }
    let raw_url = html[url_start:url_end].to_owned()
    // Only http(s) links are real results; decode /ck/a redirect URLs.
    if !raw_url.has_prefix("http://") && !raw_url.has_prefix("https://") {
      pos = li_pos + 1
      continue
    }
    let url = decode_bing_url(raw_url)
    // Title between > and </a>
    let title_start = find_substring(html, ">", url_end)
    if title_start < 0 || title_start >= limit {
      pos = li_pos + 1
      continue
    }
    let title_end = find_substring(html, "</a>", title_start + 1)
    if title_end < 0 || title_end >= limit {
      pos = li_pos + 1
      continue
    }
    let title = strip_simple_html(html[title_start + 1:title_end].to_owned())
    // Snippet: <p class="b_lineclamp...">...</p> first, .b_caption <p> fallback
    let snippet = bing_snippet(html, title_end, limit)
    if url.length() > 0 && title.length() > 0 {
      results.push({ title, url, snippet })
    }
    pos = if block_end < 0 { html_len } else { block_end + 1 }
  }
  results
}

///|
/// Extract the snippet from a Bing result block, bounded by `limit`.
fn bing_snippet(html : String, start : Int, limit : Int) -> String {
  let lc_pos = find_substring(html, "class=\"b_lineclamp", start)
  if lc_pos >= 0 && lc_pos < limit {
    let p_start = find_substring(html, ">", lc_pos)
    if p_start >= 0 && p_start < limit {
      let s_end = find_substring(html, "</p>", p_start + 1)
      if s_end >= 0 && s_end < limit {
        return strip_simple_html(html[p_start + 1:s_end].to_owned())
      }
    }
  }
  let cap_pos = find_substring(html, "class=\"b_caption\"", start)
  if cap_pos >= 0 && cap_pos < limit {
    let p_start = find_substring(html, "<p", cap_pos)
    if p_start >= 0 && p_start < limit {
      let s_start = find_substring(html, ">", p_start)
      if s_start >= 0 && s_start < limit {
        let s_end = find_substring(html, "</p>", s_start + 1)
        if s_end >= 0 && s_end < limit {
          return strip_simple_html(html[s_start + 1:s_end].to_owned())
        }
      }
    }
  }
  ""
}

///|
/// Decode Bing's redirect URL: bing.com/ck/a?...&u=a1BASE64URL&ntb=1
/// The `u` param is an "a1" prefix followed by URL-safe base64 of the real URL.
fn decode_bing_url(url : String) -> String {
  if !url.contains("bing.com/ck/") {
    return url
  }
  let q_pos = find_substring(url, "?u=", 0)
  let a_pos = find_substring(url, "&u=", 0)
  let u_pos = if q_pos >= 0 && (a_pos < 0 || q_pos < a_pos) {
    q_pos
  } else {
    a_pos
  }
  if u_pos < 0 {
    return url
  }
  let enc_start = u_pos + 3
  let enc_end = find_substring(url, "&", enc_start)
  let cut = if enc_end < 0 { url.length() } else { enc_end }
  let encoded = url[enc_start:cut].to_owned()
  // Bing prefixes the base64 payload with "a1"
  if !encoded.has_prefix("a1") {
    return url
  }
  let base64_part = encoded[2:]
  // URL-safe base64 without padding: re-add '=' padding before decoding.
  let pad = (4 - base64_part.length() % 4) % 4
  let mut padded = base64_part
  for _i = 0; _i < pad; _i = _i + 1 {
    padded = padded + "="
  }
  let decoded = @base64.decode(padded, url_safe=true) catch { _ => return url }
  let out = @utf8.decode_lossy(decoded)
  // If the result isn't valid UTF-8, keep the original redirect URL.
  if out.contains("\u{FFFD}") {
    url
  } else {
    out
  }
}

///|
/// A real Bing answer mentions at least one query token in its titles or
/// snippets. The anti-scrape fallback returns top-domain filler sharing
/// nothing with the query (original `bing_results_relevant?`).
fn bing_results_relevant(results : Array[SearchResult], query : String) -> Bool {
  if results.length() == 0 {
    return false
  }
  let tokens = query_tokens(query)
  if tokens.length() == 0 {
    return true
  }
  for r in results {
    let haystack = (r.title + " " + r.snippet).to_lower()
    for t in tokens {
      if haystack.contains(t) {
        return true
      }
    }
  }
  false
}

///|
/// Extract alphanumeric/CJK tokens from a query (original
/// `/[\p{L}\p{N}]+/`), dropping tokens shorter than 2 characters.
fn query_tokens(query : String) -> Array[String] {
  let tokens : Array[String] = []
  let mut cur = ""
  for ch in query.to_lower().iter() {
    let code = ch.to_int()
    let is_token = (code >= 0x30 && code <= 0x39) ||
      (code >= 0x41 && code <= 0x5A) ||
      (code >= 0x61 && code <= 0x7A) ||
      code >= 0x80
    if is_token {
      cur = cur + ch.to_string()
    } else {
      if cur.length() >= 2 {
        tokens.push(cur)
      }
      cur = ""
    }
  }
  if cur.length() >= 2 {
    tokens.push(cur)
  }
  tokens
}

// ── Encoding ─────────────────────────────────────────────────────────────────

///|
/// Percent-encode a query string as UTF-8 (matches Ruby `CGI.escape`):
/// unreserved chars pass through, space becomes '+', everything else %XX.
fn url_encode(s : String) -> String {
  let bytes = @utf8.encode(s)
  let hex = "0123456789ABCDEF"
  let out : Array[Byte] = []
  for i = 0; i < bytes.length(); i = i + 1 {
    let b = bytes[i].to_int()
    if (b >= 0x30 && b <= 0x39) ||
      (b >= 0x41 && b <= 0x5A) ||
      (b >= 0x61 && b <= 0x7A) ||
      b == 0x2D ||
      b == 0x2E ||
      b == 0x5F ||
      b == 0x7E {
      out.push(bytes[i])
    } else if b == 0x20 {
      out.push(b'+')
    } else {
      out.push(b'%')
      out.push(hex[b / 16].to_int().to_byte())
      out.push(hex[b % 16].to_int().to_byte())
    }
  }
  @utf8.decode_lossy(Bytes::from_array(out))
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
