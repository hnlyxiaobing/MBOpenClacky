///|
/// Browser: drive the user's real Chrome browser for web automation.
///
/// This is a structured framework implementation. The actual browser control
/// is performed via the Chrome DevTools MCP server (chrome-devtools-mcp),
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

  if not(bypass_config) {
    // Check if browser is configured
    if not(self.is_browser_configured()) {
      return ToolResult::error(browser_not_setup_error())
    }
    if not(self.is_browser_enabled()) {
      return ToolResult::error(browser_disabled_error())
    }
  }

  // Dispatch to action handler
  match action {
    "status" => ToolResult::success(self.handle_status())
    "open" =>
      match args.get("url") {
        Some(String(url)) => self.mcp_call("navigate", url)
        None => ToolResult::error("url is required for 'open' action")
        _ => ToolResult::error("url must be a string")
      }
    "navigate" =>
      match args.get("url") {
        Some(String(url)) => self.mcp_call("navigate", url)
        None => ToolResult::error("url is required for 'navigate' action")
        _ => ToolResult::error("url must be a string")
      }
    "snapshot" => self.mcp_call("snapshot", "")
    "act" =>
      match args.get("kind") {
        Some(String(kind)) => self.mcp_call("act:\{kind}", "")
        None => ToolResult::error("kind is required for 'act' action")
        _ => ToolResult::error("kind must be a string")
      }
    "screenshot" => self.mcp_call("screenshot", "")
    "tabs" => self.mcp_call("list_tabs", "")
    "focus" =>
      match args.get("target_id") {
        Some(String(id)) => self.mcp_call("focus", id)
        None => ToolResult::error("target_id is required for 'focus' action")
        _ => ToolResult::error("target_id must be a string")
      }
    "close" =>
      match args.get("target_id") {
        Some(String(id)) => self.mcp_call("close", id)
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
      "[Error] \{msg[:80].to_string()}"
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
/// Check if the browser configuration file exists.
/// TODO: Phase 12 - implement actual FS check via @fs
pub fn Browser::is_browser_configured(self : Browser) -> Bool {
  // TODO: Check if browser_config_path exists on the filesystem
  // For now, return false to indicate browser is not set up
  false
}

///|
/// Check if the browser is enabled in the configuration.
/// TODO: Phase 12 - read browser.yml and check 'enabled' flag
pub fn Browser::is_browser_enabled(self : Browser) -> Bool {
  // TODO: Read browser_config_path and check if 'enabled' is true
  false
}

// ── MCP Call Interface ───────────────────────────────────────────────────────

///|
/// Call the Chrome DevTools MCP server with the given method and params.
/// TODO: Phase 12 - implement actual MCP JSON-RPC 2.0 communication
pub fn Browser::mcp_call(
  self : Browser,
  method : String,
  _params : String,
) -> ToolResult {
  // TODO: Phase 12 MCP Protocol Support Required
  // This will be implemented when MCP protocol is available:
  // 1. Start chrome-devtools-mcp daemon if not running
  // 2. Send JSON-RPC 2.0 request
  // 3. Wait for response (timeout: 60s)
  // 4. Parse and return result
  ToolResult::error(
    "Browser tool requires MCP protocol support (Phase 12). Method '\{method}' is not yet available.",
  )
}

// ── Action Handlers ──────────────────────────────────────────────────────────

///|
/// Handle the 'status' action - check browser and MCP daemon status.
pub fn Browser::handle_status(self : Browser) -> String {
  let parts : Array[String] = [
    "Browser Status:",
    "  Configured: \{self.is_browser_configured()}",
    "  Enabled: \{self.is_browser_enabled()}",
    "  MCP daemon connected: \{self.daemon_connected}",
    "  Config path: \{browser_config_path}",
    "",
    "Note: Browser tool requires MCP protocol support (Phase 12) to function.",
  ]
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
/// TODO: Phase 12 - implement full error classification
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
let snapshot_query_window : Int = 60

///|
/// Truncate output to a maximum number of characters.
pub fn truncate_browser_output(output : String, max_chars : Int) -> String {
  if output.length() <= max_chars {
    output
  } else {
    output[:max_chars].to_string() +
    "\n... (truncated, \{output.length() - max_chars} more chars)"
  }
}

///|
/// Compress a snapshot by removing empty containers and excessive whitespace.
/// TODO: Implement full compression logic matching Ruby
pub fn compress_snapshot(snapshot : String) -> String {
  // Basic implementation: truncate to max_snapshot_chars
  truncate_browser_output(snapshot, max_snapshot_chars)
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
