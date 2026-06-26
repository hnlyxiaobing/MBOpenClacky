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
  { daemon_connected: false }
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
        Some(String(_)) => self.mcp_call("new_page", args)
        None => ToolResult::error("url is required for 'open' action")
        _ => ToolResult::error("url must be a string")
      }
    "navigate" =>
      match args.get("url") {
        Some(String(_)) => self.mcp_call("navigate_page", args)
        None => ToolResult::error("url is required for 'navigate' action")
        _ => ToolResult::error("url must be a string")
      }
    "snapshot" => {
      let raw_result = self.mcp_call("take_snapshot", args)
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
      let raw_result = self.mcp_call("take_screenshot", args)
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
        Some(String(_)) => self.mcp_call("select_page", args)
        None => ToolResult::error("target_id is required for 'focus' action")
        _ => ToolResult::error("target_id must be a string")
      }
    "close" =>
      match args.get("target_id") {
        Some(String(_)) => self.mcp_call("close_page", args)
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

///|
/// Kinds that require a `ref` parameter in the args map.
let require_ref_kinds : Array[String] = [
  "click", "dblclick", "type", "fill", "hover", "select",
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
    "click" => self.mcp_call("click", args)
    "dblclick" => {
      // Add dblClick flag so the MCP server knows to double-click
      let augmented : Map[String, Json] = {}
      for entry in args.iter() {
        augmented[entry.0] = entry.1
      }
      augmented["dblClick"] = true.to_json()
      self.mcp_call("click", augmented)
    }
    "type" | "fill" => self.mcp_call("fill", args)
    "press" => self.mcp_call("press_key", args)
    "hover" => self.mcp_call("hover", args)
    "drag" => self.mcp_call("drag", args)
    "select" => self.mcp_call("select_option", args)
    "scroll" => self.mcp_call("evaluate_script", args)
    "wait" => self.mcp_call("wait_for", args)
    "evaluate" => self.mcp_call("evaluate_script", args)
    "click_at" => self.mcp_call("click_at", args)
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
) -> ToolResult {
  // Try MCP path first
  if is_browser_mcp_available() {
    let mcp_args = build_mcp_args(tool_name, args)
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
  match tool_name {
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
  // Stage 2: Merge consecutive StaticText lines at same indent
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
        // Merge: keep first line, append " ..."
        merged.push(line + " ...")
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
let max_screenshot_width : Int = 800

///|
/// Maximum screenshot file size (bytes). Images above this are noted as oversized.
let max_screenshot_bytes : Int = 150 * 1024 // 150 KB

///|
/// Format a screenshot MCP response for LLM consumption.
/// Adds metadata about the image and formats as an injectable reference.
/// The actual image downscaling and disk save would be performed by an
/// image processing pipeline (not available without an image library).
pub fn format_screenshot_result(
  mcp_output : String,
  ref_param? : String? = None,
) -> String {
  let parts : Array[String] = []
  // Determine if this was an element-level or full-page screenshot
  match ref_param {
    Some(r) => parts.push("Screenshot captured for element ref=\{r}")
    None => parts.push("Full-page screenshot captured")
  }
  // Pass through the MCP output (typically base64 or a file path)
  parts.push("")
  parts.push(mcp_output)
  parts.push("")
  parts.push(
    "Note: Image pipeline stub — actual downscaling (max \{max_screenshot_width}px) and compression (max \{max_screenshot_bytes / 1024}KB) require an image processing library.",
  )
  join_browser_parts(parts, "\n")
}
