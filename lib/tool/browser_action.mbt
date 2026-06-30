// ── Action Dispatch ──────────────────────────────────────────────────────────

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
    "type" | "fill" =>
      // type is an alias for fill — both map to the MCP "fill" verb.
      // "fill" replaces existing content then types; "type" is kept as
      // a user-facing synonym for backward compatibility.
      self.with_page("fill", args)
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

// ── Error Classification ─────────────────────────────────────────────────────

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
