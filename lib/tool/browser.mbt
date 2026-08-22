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
pub extend Browser with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend Browser with Eq::{not_equal, equal}

///|
/// Cache for the currently selected page to avoid redundant list_pages calls.
struct PageCache {
  mut current : String?
  mut invalidated : Bool
} derive(Eq, Debug)

///|
pub extend PageCache with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend PageCache with Eq::{not_equal, equal}

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
      "format": Json::object({
        "type": "string".to_json(),
        "description": "screenshot: output format ('png' or 'jpeg', default 'png')".to_json(),
        "enum": ["png".to_json(), "jpeg".to_json()],
      }),
      "quality": Json::object({
        "type": "integer".to_json(),
        "description": "screenshot: jpeg quality 0-100 (only applies when format='jpeg')".to_json(),
      }),
      "save_path": Json::object({
        "type": "string".to_json(),
        "description": "screenshot: custom file path to save (default: temp dir)".to_json(),
      }),
      // TODO: max_width / max_height — enforce via MCP clip or libpng FFI when available
      "max_width": Json::object({
        "type": "integer".to_json(),
        "description": "screenshot: max width in pixels (TODO: not yet enforced)".to_json(),
      }),
      "max_height": Json::object({
        "type": "integer".to_json(),
        "description": "screenshot: max height in pixels (TODO: not yet enforced)".to_json(),
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
        let format_param : String? = match args.get("format") {
          Some(String(f)) => Some(f)
          _ => None
        }
        let save_path_param : String? = match args.get("save_path") {
          Some(String(sp)) => Some(sp)
          _ => None
        }
        ToolResult::success(
          format_screenshot_result(
            raw_result.content,
            ref_param~,
            format=format_param,
            save_path=save_path_param,
          ),
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

///|
/// Call the browser MCP server with the given tool name and arguments.
/// If MCP is available, sends a JSON-RPC call through the registry.
/// Falls back to a stub error message when MCP is not connected.
pub async fn Browser::mcp_call(
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
        let augmented : Map[String, Json] = Map([])
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
      // Image blocks (screenshot) are carried as data-URI lines so the
      // screenshot producer (format_screenshot_result) can extract the
      // real base64 payload instead of dropping it (aligned with Ruby
      // `browser.rb` which pulls `type == "image"` blocks directly).
      let image_lines : Array[String] = []
      for item in items {
        match item {
          { "type": "text", "text": String(text), .. } => parts.push(text)
          {
            "type": "image",
            "data": String(data),
            "mimeType": String(mime),
            ..
          } => image_lines.push("data:\{mime};base64,\{data}")
          { "type": "image", "data": String(data), .. } =>
            image_lines.push("data:image/png;base64,\{data}")
          _ => ()
        }
      }
      // Text part is truncated for LLM token budget; image data-URI lines
      // must NOT be truncated or the base64 payload becomes unusable.
      let text_part = if parts.length() > 0 {
        truncate_browser_output(
          join_browser_parts(parts, "\n"),
          max_llm_output_chars,
        )
      } else if image_lines.length() > 0 {
        ""
      } else {
        "(empty response)"
      }
      if image_lines.length() > 0 {
        let img = join_browser_parts(image_lines, "\n")
        let output = if text_part.is_empty() {
          img
        } else {
          text_part + "\n" + img
        }
        ToolResult::success(output)
      } else {
        ToolResult::success(text_part)
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
