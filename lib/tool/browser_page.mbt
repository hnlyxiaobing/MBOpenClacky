// ── Page Cache & Error Recovery ─────────────────────────────────────────────

///|
/// Error patterns that indicate the selected page is no longer available.
/// When these errors are encountered, the page cache should be invalidated
/// and the operation retried after selecting a new page.
let retryable_page_errors : Array[String] = [
  "selected page has been closed", "No page found", "no active page", "Target closed",
  "page is detached",
]

///|
/// Invalidate the page cache, forcing the next operation to re-resolve the page.
/// Called after close_page, open/new_page, or any page-related error.
pub fn Browser::invalidate_page_cache(self : Browser) -> Unit {
  self.page_cache.current = None
  self.page_cache.invalidated = true
}

///|
/// Recover the selected page by listing available pages and selecting the first one.
/// Updates the page cache with the newly selected page ID.
/// Returns the recovered page ID or None if no pages are available.
pub async fn Browser::recover_selected_page(self : Browser) -> String? {
  let list_result = self.mcp_call("list_pages", Map([]))
  if list_result.is_error {
    return None
  }
  // Parse the page list response to find the first available page ID
  let page_id = extract_first_page_id(list_result.content)
  match page_id {
    Some(pid) => {
      // Select the recovered page via MCP (bypass with_page to avoid recursion)
      let select_args : Map[String, Json] = { "target_id": pid.to_json() }
      ignore(self.mcp_call("select_page", select_args))
      // Update cache
      self.page_cache.current = Some(pid)
      self.page_cache.invalidated = false
      Some(pid)
    }
    None => None
  }
}

///|
/// Extract the first page ID from a list_pages MCP response.
/// Looks for JSON patterns like `"id":"<value>"` or `"pageId":"<value>"`.
fn extract_first_page_id(content : String) -> String? {
  // Try to find "id" field in the response (common in page list responses)
  let patterns = ["\"id\":\"", "\"pageId\":\""]
  for pat in patterns {
    match content.find(pat) {
      Some(idx) => {
        let start = idx + pat.length()
        if start < content.length() {
          let rest = content[start:].to_owned()
          match rest.find("\"") {
            Some(end) => return Some(rest[:end].to_owned())
            None => ()
          }
        }
      }
      None => ()
    }
  }
  None
}

///|
/// Check if an error message matches any retryable page error pattern.
fn is_retryable_page_error(error_msg : String) -> Bool {
  for pattern in retryable_page_errors {
    if error_msg.contains(pattern) {
      return true
    }
  }
  false
}

///|
/// Resolve the current page ID, using cache if valid, otherwise recovering.
/// Returns the page ID or None if recovery fails.
async fn Browser::resolve_page_id(self : Browser) -> String? {
  // Check cache first
  if !self.page_cache.invalidated {
    match self.page_cache.current {
      Some(pid) => return Some(pid)
      None => ()
    }
  }
  // Cache miss or invalidated — recover
  self.recover_selected_page()
}

///|
/// Execute an MCP call with automatic page ID injection and error recovery.
/// If the page cache is valid, uses the cached page ID.
/// If the page cache is empty/invalidated, recovers by selecting the first available page.
/// On retryable page errors, invalidates cache, recovers, and retries once.
pub async fn Browser::with_page(
  self : Browser,
  tool_name : String,
  args : Map[String, Json],
) -> ToolResult {
  let page_id = self.resolve_page_id()
  // First attempt with resolved page_id
  let result = self.mcp_call(tool_name, args, page_id~)
  // Check for retryable page errors
  if result.is_error && is_retryable_page_error(result.content) {
    self.invalidate_page_cache()
    match self.recover_selected_page() {
      Some(new_pid) => self.mcp_call(tool_name, args, page_id=Some(new_pid))
      None => result
    }
  } else {
    result
  }
}

// ── Page Readiness Polling ───────────────────────────────────────────────────

///|
/// Poll `list_pages` until a page with `selected: true` is found.
/// Uses iteration-based waiting (each poll = ~one MCP round-trip).
/// `timeout_ms` is converted to a max poll count (est. 150ms per poll).
/// Returns Ok(()) when a selected page is found, Err on timeout.
pub async fn Browser::wait_for_page_ready(
  self : Browser,
  timeout_ms? : Int = 1500,
) -> Result[Unit, String] {
  // Estimate ~150ms per MCP poll round-trip
  let max_polls = if timeout_ms / 150 > 0 { timeout_ms / 150 } else { 1 }
  let mut polls = 0
  while polls < max_polls {
    let result = self.mcp_call("list_pages", Map([]))
    if !result.is_error {
      // Check if the response contains a selected page indicator
      let content = result.content
      if content.contains("selected") && content.contains("true") {
        return Ok(())
      }
    }
    polls = polls + 1
  }
  Err(
    "Page not ready after \{timeout_ms}ms (\{max_polls} polls). The browser may still be loading.",
  )
}
