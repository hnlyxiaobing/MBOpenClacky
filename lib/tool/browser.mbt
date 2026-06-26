///|
/// Browser: drive the user's real Chrome browser for web automation.
///
/// This is a structured framework implementation. The actual browser control
/// is performed via the Chrome DevTools MCP server (browser-use),
/// which requires MCP protocol support (Phase 12).
///
/// Architecture:
/// - Uses the existing-session driver (Chrome MCP)
/// - Communication: MCP stdio JSON-RPC 2.0 over a persistent daemon process
/// - The MCP server process is started once and kept alive across all tool calls
///
/// Actions: open | navigate | snapshot | act | screenshot | tabs | focus | close | status
/// Act kinds: click | dblclick | type | fill | press | hover | drag | select | scroll | wait | evaluate | click_at
pub(all) struct Browser {
  /// Whether the browser MCP daemon is currently connected
  mut daemon_connected : Bool
  /// Cache for the currently selected page to avoid redundant list_pages calls
  mut page_cache : PageCache
} derive(Eq, Debug)

///|
/// Cache for the currently selected page to avoid redundant list_pages calls.
struct PageCache {
  mut current : String?
  mut invalidated : Bool
} derive(Eq, Debug)

// ── MCP Server Configuration ─────────────────────────────────────────────────

///|
/// The MCP server name used for browser automation.
let browser_mcp_server : String = "browser-use"

///|
/// Module-level state holding the MCP registry reference for browser calls.
priv struct BrowserMcpState {
  mut registry : @mcp.McpRegistry?
}

///|
/// Global browser MCP state (mutable via struct field).
let browser_mcp_state : BrowserMcpState = { registry: None }

///|
/// Set the MCP registry for browser tool to use.
/// Call this during application initialization to enable MCP-based browser control.
pub fn set_browser_mcp_registry(registry : @mcp.McpRegistry) -> Unit {
  browser_mcp_state.registry = Some(registry)
}

///|
/// Check if the browser MCP server is available in the registry.
pub fn is_browser_mcp_available() -> Bool {
  match browser_mcp_state.registry {
    Some(registry) =>
      match registry.get_client(browser_mcp_server) {
        Some(_) => true
        None => false
      }
    None => false
  }
}

///|
/// Create a new Browser tool instance.
pub fn Browser::new() -> Browser {
  { daemon_connected: false, page_cache: { current: None, invalidated: true } }
}

///|
impl Tool for Browser with fn name(_) -> String {
  "browser"
}

///|
impl Tool for Browser with fn description(_) -> String {
  "Drive the user's real Chrome for web automation. Prefer web_fetch for read-only pages.\nActions: open | navigate | snapshot | act | screenshot | tabs | focus | close | status\nWorkflow: open -> snapshot(interactive:true) -> act(ref=...). New tab from `open` is auto-selected; only use `focus` to switch back to a previously-opened tab.\nsnapshot: returns hierarchical a11y tree truncated to ~8KB. Use query=\"text\" to seek, or offset=N to page.\nact kinds: click | dblclick | type | fill | press | hover | scroll | drag | select | wait | evaluate | click_at\nevaluate: `js` is a JS expression, e.g. \"document.title\". For multi-line / async logic use an IIFE: \"(async () => { const r = await fetch(...); return r.status })()\". Result is JSON-encoded.\nscreenshot: expensive - pass `ref` to capture one element instead of the whole page."
}

///|
impl Tool for Browser with fn parameters(_) -> Json {
  Json::object({
    "type": "object".to_json(),
    "properties": Json::object({
      "action": Json::object({
        "type": "string".to_json(),
        "description": "Browser action to perform".to_json(),
        "enum": [
          "snapshot".to_json(),
          "act".to_json(),
          "open".to_json(),
          "navigate".to_json(),
          "tabs".to_json(),
          "focus".to_json(),
          "close".to_json(),
          "screenshot".to_json(),
          "status".to_json(),
        ],
      }),
      "kind": Json::object({
        "type": "string".to_json(),
        "description": "act: interaction kind".to_json(),
        "enum": [
          "click".to_json(),
          "dblclick".to_json(),
          "type".to_json(),
          "fill".to_json(),
          "press".to_json(),
          "hover".to_json(),
          "drag".to_json(),
          "select".to_json(),
          "scroll".to_json(),
          "wait".to_json(),
          "evaluate".to_json(),
          "click_at".to_json(),
        ],
      }),
      "ref": Json::object({
        "type": "string".to_json(),
        "description": "element ref from snapshot (e.g. 'e1')".to_json(),
      }),
      "text": Json::object({
        "type": "string".to_json(),
        "description": "act type/fill text".to_json(),
      }),
      "key": Json::object({
        "type": "string".to_json(),
        "description": "act press key (e.g. 'Enter')".to_json(),
      }),
      "direction": Json::object({
        "type": "string".to_json(),
        "description": "act scroll direction".to_json(),
        "enum": [
          "up".to_json(),
          "down".to_json(),
          "left".to_json(),
          "right".to_json(),
        ],
      }),
      "amount": Json::object({
        "type": "integer".to_json(),
        "description": "act scroll pixels (default 300)".to_json(),
      }),
      "ms": Json::object({
        "type": "integer".to_json(),
        "description": "act wait ms".to_json(),
      }),
      "selector": Json::object({
        "type": "string".to_json(),
        "description": "act wait: text or CSS selector".to_json(),
      }),
      "js": Json::object({
        "type": "string".to_json(),
        "description": "act evaluate: JS expression (use IIFE for multi-line/async)".to_json(),
      }),
      "target_ref": Json::object({
        "type": "string".to_json(),
        "description": "act drag destination ref".to_json(),
      }),
      "values": Json::object({
        "type": "array".to_json(),
        "items": Json::object({ "type": "string".to_json() }),
        "description": "act select options".to_json(),
      }),
      "x": Json::object({
        "type": "number".to_json(),
        "description": "click_at x px".to_json(),
      }),
      "y": Json::object({
        "type": "number".to_json(),
        "description": "click_at y px".to_json(),
      }),
      "url": Json::object({
        "type": "string".to_json(),
        "description": "open/navigate URL".to_json(),
      }),
      "target_id": Json::object({
        "type": "string".to_json(),
        "description": "focus/close tab id".to_json(),
      }),
      "interactive": Json::object({
        "type": "boolean".to_json(),
        "description": "snapshot: only interactive elements".to_json(),
      }),
      "compact": Json::object({
        "type": "boolean".to_json(),
        "description": "snapshot: drop empty containers".to_json(),
      }),
      "depth": Json::object({
        "type": "integer".to_json(),
        "description": "snapshot: max tree depth".to_json(),
      }),
      "query": Json::object({
        "type": "string".to_json(),
        "description": "snapshot: return window around first match".to_json(),
      }),
      "offset": Json::object({
        "type": "integer".to_json(),
        "description": "snapshot: skip N lines (paging)".to_json(),
      }),
      "full_page": Json::object({
        "type": "boolean".to_json(),
        "description": "screenshot: full page".to_json(),
      }),
    }),
    "required": ["action".to_json()],
  })
}

///|
impl Tool for Browser with fn category(_) -> ToolCategory {
  Web
}

///|
impl Tool for Browser with fn execute(self, args : Map[String, Json]) -> ToolResult {
  let action = match args.get("action") {
    Some(String(a)) => a
    _ => ""
  }

  // Status action and act/evaluate bypass config check
  let is_evaluate = match args.get("kind") {
    Some(String("evaluate")) => true
    _ => false
  }
  let bypass_config = action == "status" || (action == "act" && is_evaluate)

  if !bypass_config {
    // Check if browser is configured
    if !self.is_browser_configured() {
      return ToolResult::error(browser_not_setup_error())
    }
    if !self.is_browser_enabled() {
      return ToolResult::error(browser_disabled_error())
    }
  }

  // Dispatch to action handler
  match action {
    "status" => ToolResult::success(self.handle_status())
    "open" =>
      match args.get("url") {
        Some(String(_)) => {
          let result = self.mcp_call("new_page", args)
          self.invalidate_page_cache()
          result
        }
        None => ToolResult::error("url is required for 'open' action")
        _ => ToolResult::error("url must be a string")
      }
    "navigate" =>
      match args.get("url") {
        Some(String(_)) => self.with_page("navigate_page", args)
        None => ToolResult::error("url is required for 'navigate' action")
        _ => ToolResult::error("url must be a string")
      }
    "snapshot" => {
      let raw_result = self.with_page("take_snapshot", args)
      // Post-process: apply query window or compression on success
      if !raw_result.is_error {
        let output = raw_result.content
        let result_text = match args.get("query") {
          Some(String(q)) => {
            let offset = match args.get("offset") {
              Some(Number(n, ..)) => n.to_int()
              _ => 0
            }
            query_snapshot(output, q, offset~)
          }
          _ => compress_snapshot(output)
        }
        ToolResult::success(result_text)
      } else {
        raw_result
      }
    }
    "act" =>
      match args.get("kind") {
        Some(String(kind)) => self.dispatch_act(kind, args)
        None => ToolResult::error("kind is required for 'act' action")
        _ => ToolResult::error("kind must be a string")
      }
    "screenshot" => {
      let raw_result = self.with_page("take_screenshot", args)
      if !raw_result.is_error {
        let ref_param = match args.get("ref") {
          Some(String(r)) => Some(r)
          _ => None
        }
        ToolResult::success(
          format_screenshot_result(raw_result.content, ref_param~),
        )
      } else {
        raw_result
      }
    }
    "tabs" => self.mcp_call("list_pages", args)
    "focus" =>
      match args.get("target_id") {
        Some(String(_)) => {
          let result = self.mcp_call("select_page", args)
          // Update cache: after focus, the targeted page becomes current
          if !result.is_error {
            match args.get("target_id") {
              Some(String(tid)) => {
                self.page_cache.current = Some(tid)
                self.page_cache.invalidated = false
              }
              _ => ()
            }
          }
          result
        }
        None => ToolResult::error("target_id is required for 'focus' action")
        _ => ToolResult::error("target_id must be a string")
      }
    "close" =>
      match args.get("target_id") {
        Some(String(_)) => {
          let result = self.mcp_call("close_page", args)
          self.invalidate_page_cache()
          result
        }
        None => ToolResult::error("target_id is required for 'close' action")
        _ => ToolResult::error("target_id must be a string")
      }
    _ => ToolResult::error("Unknown action: \{action}")
  }
}

///|
impl Tool for Browser with fn format_call(_, args : Map[String, Json]) -> String {
  let action = match args.get("action") {
    Some(String(a)) => a
    _ => "browser"
  }
  "browser(\{action})"
}

///|
impl Tool for Browser with fn format_result(_, result : ToolResult) -> String {
  if result.is_error {
    let msg = result.content
    if msg.length() > 80 {
      "[Error] \{msg[:80].to_owned()}"
    } else {
      "[Error] \{msg}"
    }
  } else {
    let lines = result.content.split("\n")
    "[OK] \{lines.length()} lines"
  }
}

///|
impl Tool for Browser with fn to_function_definition(self) -> FunctionDefinition {
  FunctionDefinition::new(self.name(), self.description(), self.parameters())
}

// ── Browser Configuration ────────────────────────────────────────────────────

///|
/// Path to the browser configuration file.
/// In MoonBit version: ~/.mbopenclacky/browser.yml
let browser_config_path : String = "~/.mbopenclacky/browser.yml"

///|
/// Check if the browser configuration file exists or MCP is available.
pub fn Browser::is_browser_configured(self : Browser) -> Bool {
  ignore(self)
  // If MCP browser server is available, consider it configured
  if is_browser_mcp_available() {
    return true
  }
  // TODO: Check if browser_config_path exists on the filesystem
  false
}

///|
/// Check if the browser is enabled in the configuration or via MCP.
pub fn Browser::is_browser_enabled(self : Browser) -> Bool {
  ignore(self)
  // If MCP browser server is available, consider it enabled
  if is_browser_mcp_available() {
    return true
  }
  // TODO: Read browser_config_path and check if 'enabled' is true
  false
}

// ── MCP Call Interface ───────────────────────────────────────────────────────

// ── Page Cache & Error Recovery ─────────────────────────────────────────────

///|
/// Error patterns that indicate the selected page is no longer available.
/// When these errors are encountered, the page cache should be invalidated
/// and the operation retried after selecting a new page.
let retryable_page_errors : Array[String] = [
  "selected page has been closed",
  "No page found",
  "no active page",
  "Target closed",
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
pub fn Browser::recover_selected_page(self : Browser) -> String? {
  let list_result = self.mcp_call("list_pages", {})
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
fn Browser::resolve_page_id(self : Browser) -> String? {
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
pub fn Browser::with_page(
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

///|
/// Kinds that require a `ref` parameter in the args map.
let require_ref_kinds : Array[String] = [
  "click", "dblclick", "type", "fill", "hover", "select", "drag",
]

///|
/// Dispatch an 'act' action to the appropriate MCP tool based on kind.
/// Validates require_ref before dispatching.
fn Browser::dispatch_act(
  self : Browser,
  kind : String,
  args : Map[String, Json],
) -> ToolResult {
  // Validate require_ref: actions that target a specific element need `ref`
  if require_ref_kinds.contains(kind) {
    match args.get("ref") {
      Some(String(_)) => ()
      _ =>
        return ToolResult::error(
          "ref is required for act kind '\{kind}'. Use snapshot to find element refs.",
        )
    }
  }
  match kind {
    "click" => self.with_page("click", args)
    "dblclick" => {
      // Add dblClick flag so the MCP server knows to double-click
      let augmented : Map[String, Json] = {}
      for entry in args.iter() {
        augmented[entry.0] = entry.1
      }
      augmented["dblClick"] = true.to_json()
      self.with_page("click", augmented)
    }
    "type" | "fill" => {
      // type is an alias for fill — both map to the MCP "fill" verb.
      // "fill" replaces existing content then types; "type" is kept as
      // a user-facing synonym for backward compatibility.
      self.with_page("fill", args)
    }
    "press" => self.with_page("press_key", args)
    "hover" => self.with_page("hover", args)
    "drag" => self.with_page("drag", args)
    "select" => self.with_page("select_option", args)
    "scroll" => self.with_page("evaluate_script", args)
    "wait" => self.with_page("wait_for", args)
    "evaluate" => self.mcp_call("evaluate_script", args)
    "click_at" => self.with_page("click_at", args)
    _ => ToolResult::error("Unknown act kind: \{kind}")
  }
}

///|
/// Call the browser MCP server with the given tool name and arguments.
/// If MCP is available, sends a JSON-RPC call through the registry.
/// Falls back to a stub error message when MCP is not connected.
pub fn Browser::mcp_call(
  self : Browser,
  tool_name : String,
  args : Map[String, Json],
  page_id? : String? = None,
) -> ToolResult {
  // Try MCP path first
  if is_browser_mcp_available() {
    // Inject pageId into args if provided
    let effective_args = match page_id {
      Some(pid) => {
        let augmented : Map[String, Json] = {}
        for entry in args.iter() {
          augmented[entry.0] = entry.1
        }
        augmented["pageId"] = pid.to_json()
        augmented
      }
      None => args
    }
    let mcp_args = build_mcp_args(tool_name, effective_args)
    match browser_mcp_state.registry {
      Some(registry) => {
        let result = registry.call_tool(browser_mcp_server, tool_name, mcp_args) catch {
          @mcp.McpError(msg) => {
            let classified = classify_browser_error(msg)
            return ToolResult::error(classified)
          }
        }
        // Update daemon connection state
        self.daemon_connected = true
        // Parse and return the MCP response
        parse_mcp_tool_response(result)
      }
      None =>
        ToolResult::error(
          "Browser MCP server not connected. Please ensure browser-use MCP is running.",
        )
    }
  } else {
    // Fallback: MCP not available
    ToolResult::error(
      "Browser MCP server not connected. Please ensure browser-use MCP is running.",
    )
  }
}

// ── MCP Argument Builders ────────────────────────────────────────────────────

///|
/// Build MCP tool arguments from the raw args map based on the tool being called.
fn build_mcp_args(tool_name : String, args : Map[String, Json]) -> Json {
  let base = match tool_name {
    "new_page" => build_mcp_navigate_args(args)
    "navigate_page" => build_mcp_navigate_args(args)
    "take_snapshot" => build_mcp_snapshot_args(args)
    "take_screenshot" => build_mcp_screenshot_args(args)
    "click" => build_mcp_click_args(args)
    "fill" => build_mcp_fill_args(args)
    "press_key" => build_mcp_press_args(args)
    "hover" => build_mcp_hover_args(args)
    "drag" => build_mcp_drag_args(args)
    "select_option" => build_mcp_select_args(args)
    "wait_for" => build_mcp_wait_args(args)
    "evaluate_script" => build_mcp_evaluate_args(args)
    "click_at" => build_mcp_click_at_args(args)
    "list_pages" => Json::object({})
    "select_page" => build_mcp_select_page_args(args)
    "close_page" => build_mcp_close_page_args(args)
    _ => Json::object({})
  }
  // Propagate pageId from args if present (injected by with_page / mcp_call)
  match args.get("pageId") {
    Some(v) => {
      match base {
        Object(obj) => {
          obj["pageId"] = v
          Json::object(obj)
        }
        _ => base
      }
    }
    None => base
  }
}

///|
fn build_mcp_navigate_args(args : Map[String, Json]) -> Json {
  let obj : Map[String, Json] = {}
  match args.get("url") {
    Some(String(url)) => obj["url"] = url.to_json()
    _ => ()
  }
  Json::object(obj)
}

///|
fn build_mcp_snapshot_args(args : Map[String, Json]) -> Json {
  let obj : Map[String, Json] = {}
  match args.get("interactive") {
    Some(v) => obj["interactive"] = v
    _ => ()
  }
  match args.get("compact") {
    Some(v) => obj["compact"] = v
    _ => ()
  }
  match args.get("depth") {
    Some(v) => obj["depth"] = v
    _ => ()
  }
  match args.get("query") {
    Some(v) => obj["query"] = v
    _ => ()
  }
  match args.get("offset") {
    Some(v) => obj["offset"] = v
    _ => ()
  }
  Json::object(obj)
}

///|
fn build_mcp_screenshot_args(args : Map[String, Json]) -> Json {
  let obj : Map[String, Json] = {}
  match args.get("ref") {
    Some(v) => obj["ref"] = v
    _ => ()
  }
  match args.get("full_page") {
    Some(v) => obj["full_page"] = v
    _ => ()
  }
  Json::object(obj)
}

///|
fn build_mcp_click_args(args : Map[String, Json]) -> Json {
  let obj : Map[String, Json] = {}
  match args.get("ref") {
    Some(v) => obj["selector"] = v
    _ => ()
  }
  // Pass dblClick flag for double-click actions
  match args.get("dblClick") {
    Some(v) => obj["dblClick"] = v
    _ => ()
  }
  Json::object(obj)
}

///|
fn build_mcp_fill_args(args : Map[String, Json]) -> Json {
  let obj : Map[String, Json] = {}
  match args.get("ref") {
    Some(v) => obj["selector"] = v
    _ => ()
  }
  // Accept both "text" (user-facing) and "value" (direct MCP) keys
  match args.get("text") {
    Some(String(t)) => obj["value"] = t.to_json()
    _ =>
      match args.get("value") {
        Some(v) => obj["value"] = v
        _ => ()
      }
  }
  Json::object(obj)
}

///|
fn build_mcp_press_args(args : Map[String, Json]) -> Json {
  let obj : Map[String, Json] = {}
  match args.get("key") {
    Some(v) => obj["key"] = v
    _ => ()
  }
  Json::object(obj)
}

///|
fn build_mcp_hover_args(args : Map[String, Json]) -> Json {
  let obj : Map[String, Json] = {}
  match args.get("ref") {
    Some(v) => obj["selector"] = v
    _ => ()
  }
  Json::object(obj)
}

///|
fn build_mcp_drag_args(args : Map[String, Json]) -> Json {
  let obj : Map[String, Json] = {}
  match args.get("ref") {
    Some(v) => obj["from_uid"] = v
    _ => ()
  }
  match args.get("target_ref") {
    Some(v) => obj["to_uid"] = v
    _ => ()
  }
  Json::object(obj)
}

///|
fn build_mcp_select_args(args : Map[String, Json]) -> Json {
  let obj : Map[String, Json] = {}
  match args.get("ref") {
    Some(v) => obj["selector"] = v
    _ => ()
  }
  match args.get("values") {
    Some(v) => obj["values"] = v
    _ => ()
  }
  Json::object(obj)
}

///|
fn build_mcp_wait_args(args : Map[String, Json]) -> Json {
  let obj : Map[String, Json] = {}
  match args.get("selector") {
    Some(v) => obj["selector"] = v
    _ => ()
  }
  match args.get("ms") {
    Some(Number(n, ..)) => obj["timeout"] = n.to_int().to_json()
    _ => ()
  }
  Json::object(obj)
}

///|
fn build_mcp_evaluate_args(args : Map[String, Json]) -> Json {
  let obj : Map[String, Json] = {}
  // For scroll simulation via evaluate_script
  match args.get("direction") {
    Some(String(dir)) => {
      let amount = match args.get("amount") {
        Some(Number(n, ..)) => n.to_int()
        _ => 300
      }
      let scroll_js = match dir {
        "up" => "window.scrollBy(0, -\{amount})"
        "down" => "window.scrollBy(0, \{amount})"
        "left" => "window.scrollBy(-\{amount}, 0)"
        _ => "window.scrollBy(\{amount}, 0)"
      }
      obj["script"] = scroll_js.to_json()
      return Json::object(obj)
    }
    _ => ()
  }
  // Regular evaluate: wrap in IIFE if not already wrapped
  match args.get("js") {
    Some(String(js)) => {
      let script = if js.has_prefix("(function") || js.has_prefix("(()") {
        js
      } else {
        "(function() { " + js + " })()"
      }
      obj["script"] = script.to_json()
    }
    Some(v) => obj["script"] = v
    _ => ()
  }
  Json::object(obj)
}

///|
fn build_mcp_click_at_args(args : Map[String, Json]) -> Json {
  let obj : Map[String, Json] = {}
  match args.get("x") {
    Some(v) => obj["x"] = v
    _ => ()
  }
  match args.get("y") {
    Some(v) => obj["y"] = v
    _ => ()
  }
  Json::object(obj)
}

///|
fn build_mcp_select_page_args(args : Map[String, Json]) -> Json {
  let obj : Map[String, Json] = {}
  match args.get("target_id") {
    Some(v) => obj["pageId"] = v
    _ => ()
  }
  // Also accept pageId directly
  match args.get("pageId") {
    Some(v) => obj["pageId"] = v
    _ => ()
  }
  // Add bringToFront for focus behavior
  obj["bringToFront"] = true.to_json()
  Json::object(obj)
}

///|
fn build_mcp_close_page_args(args : Map[String, Json]) -> Json {
  let obj : Map[String, Json] = {}
  match args.get("target_id") {
    Some(v) => obj["pageId"] = v
    _ => ()
  }
  // Also accept pageId directly
  match args.get("pageId") {
    Some(v) => obj["pageId"] = v
    _ => ()
  }
  Json::object(obj)
}

// ── MCP Response Parser ──────────────────────────────────────────────────────

///|
/// Parse the JSON response from an MCP tool call into a ToolResult.
fn parse_mcp_tool_response(response : Json) -> ToolResult {
  // MCP tool responses typically have: { "content": [{ "type": "text", "text": "..." }] }
  match response {
    { "isError": True, "content": Array(items), .. } => {
      let parts : Array[String] = []
      for item in items {
        match item {
          { "text": String(text), .. } => parts.push(text)
          _ => ()
        }
      }
      let msg = if parts.length() > 0 {
        join_browser_parts(parts, "\n")
      } else {
        "MCP tool returned an error"
      }
      ToolResult::error(classify_browser_error(msg))
    }
    { "content": Array(items), .. } => {
      let parts : Array[String] = []
      for item in items {
        match item {
          { "text": String(text), .. } => parts.push(text)
          _ => ()
        }
      }
      if parts.length() > 0 {
        let output = join_browser_parts(parts, "\n")
        ToolResult::success(
          truncate_browser_output(output, max_llm_output_chars),
        )
      } else {
        ToolResult::success("(empty response)")
      }
    }
    String(text) => ToolResult::success(text)
    _ => {
      // Try to stringify the raw response
      let text = response.stringify()
      ToolResult::success(truncate_browser_output(text, max_llm_output_chars))
    }
  }
}

// ── Action Handlers ──────────────────────────────────────────────────────────

///|
/// Handle the 'status' action - check browser and MCP daemon status.
pub fn Browser::handle_status(self : Browser) -> String {
  let mcp_available = is_browser_mcp_available()
  let parts : Array[String] = [
    "Browser Status:",
    "  Configured: \{self.is_browser_configured()}",
    "  Enabled: \{self.is_browser_enabled()}",
    "  MCP daemon connected: \{self.daemon_connected}",
    "  MCP server available: \{mcp_available}",
    "  MCP server name: \{browser_mcp_server}",
    "  Config path: \{browser_config_path}",
  ]
  if !mcp_available {
    parts.push("")
    parts.push(
      "Note: Browser MCP server not connected. Ensure browser-use MCP is running.",
    )
  }
  join_browser_parts(parts, "\n")
}

// ── Error Messages ───────────────────────────────────────────────────────────

///|
/// Error message when browser is not set up (no config file).
pub fn browser_not_setup_error() -> String {
  "Browser is not set up. Configuration file not found at \{browser_config_path}\n\nTo set up the browser tool, run the browser-setup skill or create the configuration file manually."
}

///|
/// Error message when browser is disabled in config.
pub fn browser_disabled_error() -> String {
  "Browser is disabled in the configuration file.\n\nTo enable it, set 'enabled: true' in \{browser_config_path}"
}

///|
/// Classify a browser error and return an appropriate message.
pub fn classify_browser_error(error_msg : String) -> String {
  // Cause 4: Chrome unresponsive (timeout)
  if error_msg.find("timed out") is Some(_) {
    return "Browser error: \{error_msg}\n\nChrome has become unresponsive. This often happens after Chrome has been running for a long time. Ask the user to restart Chrome, then retry the action."
  }
  // Cause 1+2: Chrome not running or Remote Debugging disabled
  if error_msg.find("Could not connect to Chrome") is Some(_) {
    return "Browser error: \{error_msg}\n\nChrome is not reachable. Possible causes:\n1. Chrome is not running\n2. Remote Debugging is disabled"
  }
  // Cause 3: MCP daemon crashed
  if error_msg.find("handshake") is Some(_) || error_msg.find("MCP") is Some(_) {
    return "Browser error: \{error_msg}\n\nThe browser MCP daemon crashed or failed to start. It may recover automatically on the next action."
  }
  // Default: pass through
  "Browser error: \{error_msg}"
}

// ── Pure Logic Helpers ───────────────────────────────────────────────────────

///|
/// Maximum snapshot output size in characters.
let max_snapshot_chars : Int = 8000

///|
/// Maximum LLM output size in characters.
let max_llm_output_chars : Int = 6000

///|
/// Lines of context to show around a query match in snapshot.
let _snapshot_query_window : Int = 60

///|
/// Truncate output to a maximum number of characters.
pub fn truncate_browser_output(output : String, max_chars : Int) -> String {
  if output.length() <= max_chars {
    output
  } else {
    output[:max_chars].to_owned() +
    "\n... (truncated, \{output.length() - max_chars} more chars)"
  }
}

///|
/// Compress a snapshot by removing noise and merging consecutive static text.
/// Two-stage compression matching Ruby's approach:
///   Stage 1: Remove noise lines (empty containers, decoration-only lines)
///   Stage 2: Merge consecutive StaticText lines at the same indent
/// Then truncate to max_snapshot_chars.
pub fn compress_snapshot(snapshot : String) -> String {
  // Collect lines into Array[String] (split returns Iter[StringView])
  let lines : Array[String] = []
  for sv in snapshot.split("\n") {
    lines.push(sv.to_owned())
  }
  // Stage 1: Remove noise lines
  let cleaned : Array[String] = []
  for line in lines {
    let trimmed = line.trim().to_owned()
    if trimmed == "" {
      // keep blank lines for readability only if last cleaned line wasn't blank
      if cleaned.length() > 0 && cleaned[cleaned.length() - 1].trim() != "" {
        cleaned.push(line)
      }
    } else if is_noise_line(trimmed) {
      // skip noise
    } else {
      cleaned.push(line)
    }
  }
  // Stage 2: Merge consecutive StaticText lines at same indent as "a / b / c"
  let merged : Array[String] = []
  let mut i = 0
  while i < cleaned.length() {
    let line = cleaned[i]
    let indent = leading_indent(line)
    let trimmed = line.trim().to_owned()
    if is_static_text_line(trimmed) && i + 1 < cleaned.length() {
      // Look ahead for consecutive StaticText at same indent
      let mut j = i + 1
      while j < cleaned.length() {
        let next_trimmed = cleaned[j].trim().to_owned()
        let next_indent = leading_indent(cleaned[j])
        if is_static_text_line(next_trimmed) && next_indent == indent {
          j = j + 1
        } else {
          break
        }
      }
      if j > i + 1 {
        // Merge: extract text values and join with " / "
        let texts : Array[String] = []
        let mut k = i
        while k < j {
          texts.push(extract_static_text_value(cleaned[k].trim().to_owned()))
          k = k + 1
        }
        let merged_text = join_browser_parts(texts, " / ")
        let prefix = line[:indent].to_owned()
        merged.push(prefix + "StaticText: " + merged_text)
        i = j
      } else {
        merged.push(line)
        i = i + 1
      }
    } else {
      merged.push(line)
      i = i + 1
    }
  }
  let result = join_browser_parts(merged, "\n")
  truncate_browser_output(result, max_snapshot_chars)
}

///|
/// Check if a trimmed line is noise (empty container, decoration, etc.)
fn is_noise_line(trimmed : String) -> Bool {
  if trimmed == "()" || trimmed == "[]" || trimmed == "{}" {
    return true
  }
  // Lines that are only box-drawing characters (─, │, ├, └, ┌, ┐, ┘, ┤)
  if trimmed.length() > 0 && is_all_decoration(trimmed) {
    return true
  }
  false
}

///|
/// Check if a string consists entirely of box-drawing decoration characters.
fn is_all_decoration(s : String) -> Bool {
  let mut i = 0
  while i < s.length() {
    let c = s[i]
    if c != '─' &&
      c != '│' &&
      c != '├' &&
      c != '└' &&
      c != '┌' &&
      c != '┐' &&
      c != '┘' &&
      c != '┤' &&
      c != ' ' {
      return false
    }
    i = i + 1
  }
  true
}

// ── Page Readiness Polling ───────────────────────────────────────────────────

///|
/// Poll `list_pages` until a page with `selected: true` is found.
/// Uses iteration-based waiting (each poll = ~one MCP round-trip).
/// `timeout_ms` is converted to a max poll count (est. 150ms per poll).
/// Returns Ok(()) when a selected page is found, Err on timeout.
pub fn Browser::wait_for_page_ready(
  self : Browser,
  timeout_ms? : Int = 1500,
) -> Result[Unit, String] {
  // Estimate ~150ms per MCP poll round-trip
  let max_polls = if timeout_ms / 150 > 0 { timeout_ms / 150 } else { 1 }
  let mut polls = 0
  while polls < max_polls {
    let result = self.mcp_call("list_pages", {})
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

///|
/// Check if a trimmed line looks like a StaticText node.
/// Heuristic: lines that don't end with a ref marker `[ref=N]` and
/// don't have typical interactive element patterns (button, link, input).
fn is_static_text_line(trimmed : String) -> Bool {
  if trimmed.has_prefix("StaticText:") || trimmed.has_prefix("text:") {
    return true
  }
  false
}

///|
/// Extract the text value from a StaticText line (after "StaticText:" or "text:").
fn extract_static_text_value(trimmed : String) -> String {
  if trimmed.has_prefix("StaticText:") {
    let rest = trimmed[11:].to_owned()
    rest.trim().to_owned()
  } else if trimmed.has_prefix("text:") {
    let rest = trimmed[5:].to_owned()
    rest.trim().to_owned()
  } else {
    trimmed
  }
}

///|
/// Count the leading whitespace indent of a line.
fn leading_indent(line : String) -> Int {
  let mut count = 0
  while count < line.length() {
    let c = line[count]
    if c == ' ' || c == '\t' {
      count = count + 1
    } else {
      break
    }
  }
  count
}

///|
/// Query a snapshot for a text pattern, returning a window of lines around the match.
/// Supports offset-based paging for navigating through large snapshots.
pub fn query_snapshot(
  snapshot : String,
  query : String,
  offset? : Int = 0,
) -> String {
  let compressed = compress_snapshot(snapshot)
  // Collect into Array[String] for indexed access
  let lines : Array[String] = []
  for sv in compressed.split("\n") {
    lines.push(sv.to_owned())
  }
  // Find first match at or after offset
  let mut match_line = -1
  let mut i = offset
  let lower_query = query.to_lower()
  while i < lines.length() {
    if lines[i].to_lower().contains(lower_query) {
      match_line = i
      break
    }
    i = i + 1
  }
  if match_line < 0 {
    return "No match found for query \"\{query}\"" +
      (if offset > 0 { " (after line \{offset})" } else { "" })
  }
  // Extract window around match
  let half = _snapshot_query_window / 2
  let start = if match_line - half > 0 { match_line - half } else { 0 }
  let end = if match_line + half < lines.length() {
    match_line + half
  } else {
    lines.length()
  }
  let window : Array[String] = []
  // Add header with match info
  window.push(
    "--- match at line \{match_line + 1}, showing lines \{start + 1}-\{end} of \{lines.length()} ---",
  )
  let mut li = start
  while li < end {
    let marker = if li == match_line { ">> " } else { "   " }
    window.push(marker + lines[li])
    li = li + 1
  }
  // Add paging hint if there's more
  if end < lines.length() {
    window.push("--- use offset=\{end} to see next page ---")
  }
  join_browser_parts(window, "\n")
}

///|
/// Join an array of strings with a separator (local helper).
fn join_browser_parts(parts : Array[String], sep : String) -> String {
  if parts.length() == 0 {
    return ""
  }
  let mut result = parts[0]
  let mut i = 1
  while i < parts.length() {
    result = result + sep + parts[i]
    i = i + 1
  }
  result
}

// ── Screenshot Pipeline ────────────────────────────────────────────────────

///|
/// Maximum screenshot width before downscaling (pixels).
/// TODO: used when libpng FFI is available for downscaling.
let _max_screenshot_width : Int = 800

///|
/// Maximum screenshot file size (bytes). Images above this are noted as oversized.
let max_screenshot_bytes : Int = 150 * 1024 // 150 KB

///|
/// Get the system temporary directory for saving screenshots.
fn get_screenshot_temp_dir() -> String {
  let dir = match @sys.get_env_var("TEMP") {
    Some(d) => d
    None =>
      match @sys.get_env_var("TMPDIR") {
        Some(d) => d
        None => "/tmp"
      }
  }
  let subdir = @path.Path(dir).join(@path.Path("mbopenclacky_screenshots"))
  let subdir_str = subdir.to_string()
  if !@fs.path_exists(subdir_str) {
    @fs.create_dir(subdir_str) catch { _ => () }
  }
  subdir_str
}

///|
/// Generate a unique screenshot filename using timestamp.
/// Fix: [H1] 截图文件计数器并发不安全 — 改用时间戳确保文件名唯一性
fn next_screenshot_filename() -> String {
  let ts = @async.now()
  "screenshot_\{ts}.png"
}

///|
/// Format a screenshot MCP response for LLM consumption.
/// Saves the raw PNG to a temp directory, checks the 150KB size limit,
/// and returns a structured `{ content_string, image_inject }` payload.
/// TODO: 800px downscaling requires libpng FFI — currently skipped.
pub fn format_screenshot_result(
  mcp_output : String,
  ref_param? : String? = None,
) -> String {
  let parts : Array[String] = []
  // Determine if this was an element-level or full-page screenshot
  let caption = match ref_param {
    Some(r) => "Screenshot captured for element ref=\{r}"
    None => "Full-page screenshot captured"
  }
  parts.push(caption)
  // Attempt to extract base64 image data and save to disk
  let base64_data = extract_base64_image(mcp_output)
  match base64_data {
    Some(b64) => {
      let png_bytes = @base64.decode(b64.view()) catch { _ => Bytes::make(0, b'\x00') }
      let byte_len = png_bytes.length()
      let temp_dir = get_screenshot_temp_dir()
      let filename = next_screenshot_filename()
      let filepath = @path.Path(temp_dir).join(@path.Path(filename)).to_string()
      @fs.write_bytes_to_file(filepath, png_bytes) catch {
        _ => {
          parts.push("")
          parts.push("[image_inject]")
          parts.push("mime_type: image/png")
          parts.push("base64_data: (\{b64.length()} chars)")
          parts.push("")
          parts.push(
            "Note: Failed to save screenshot to disk. Image data returned inline.",
          )
          return join_browser_parts(parts, "\n")
        }
      }
      parts.push("")
      parts.push("[image_inject]")
      parts.push("mime_type: image/png")
      parts.push("base64_data: (\{b64.length()} chars)")
      parts.push("path: \{filepath}")
      // Size limit check
      if byte_len > max_screenshot_bytes {
        parts.push("")
        parts.push(
          "⚠ Screenshot is \{byte_len / 1024}KB (limit \{max_screenshot_bytes / 1024}KB). Consider using snapshot instead for text-heavy pages.",
        )
      }
      // TODO: downscale to max_screenshot_width px — requires libpng FFI
    }
    None => {
      // MCP returned text-only output (no base64 image)
      parts.push("")
      parts.push(mcp_output)
    }
  }
  join_browser_parts(parts, "\n")
}

///|
/// Try to extract a base64 image payload from the MCP screenshot response.
/// Looks for common patterns: data URI prefix or raw base64 block.
fn extract_base64_image(mcp_output : String) -> String? {
  // Pattern 1: data URI — "data:image/png;base64,<data>"
  match mcp_output.find("base64,") {
    Some(idx) => {
      let start = idx + 7
      if start < mcp_output.length() {
        return Some(mcp_output[start:].to_owned().trim().to_owned())
      }
      return None
    }
    None => ()
  }
  // Pattern 2: line starting with a long base64 string (>100 chars, only [A-Za-z0-9+/=])
  for sv in mcp_output.split("\n") {
    let line = sv.trim().to_owned()
    if line.length() > 100 && is_base64_like(line) {
      return Some(line)
    }
  }
  None
}

///|
/// Heuristic check: does the string look like base64 (only valid chars)?
fn is_base64_like(s : String) -> Bool {
  let mut i = 0
  while i < s.length() {
    let c = s[i]
    let valid = (c >= 'A' && c <= 'Z') ||
      (c >= 'a' && c <= 'z') ||
      (c >= '0' && c <= '9') ||
      c == '+' ||
      c == '/' ||
      c == '='
    if !valid {
      return false
    }
    i = i + 1
  }
  true
}
