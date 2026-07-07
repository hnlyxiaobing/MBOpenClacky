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
      // Enhanced with focus/blur evaluate_script calls for framework compat.
      self.dispatch_fill_enhanced(args)
    "press" => self.with_page("press_key", args)
    "hover" => self.with_page("hover", args)
    "drag" => self.with_page("drag", args)
    "select" => self.with_page("select_option", args)
    "scroll" => self.dispatch_scroll(args)
    "wait" => self.with_page("wait_for", args)
    "evaluate" => self.mcp_call("evaluate_script", args)
    "click_at" => self.with_page("click_at", args)
    _ => ToolResult::error("Unknown act kind: \{kind}")
  }
}

// ── Scroll Dispatch (native with fallback) ─────────────────────────────────

///|
/// Dispatch scroll: try native MCP scroll_page first, fall back to evaluate_script.
fn Browser::dispatch_scroll(
  self : Browser,
  args : Map[String, Json],
) -> ToolResult {
  let native_result = self.with_page("scroll_page", args)
  if !native_result.is_error {
    return native_result
  }
  // Fallback: build evaluate_script scrollBy args
  let fallback_args : Map[String, Json] = {}
  for entry in args.iter() {
    fallback_args[entry.0] = entry.1
  }
  // Copy all args — build_mcp_evaluate_args detects direction/amount
  // and constructs the appropriate scrollBy JS automatically.
  self.with_page("evaluate_script", fallback_args)
}

// ── Fill Dispatch (focus/blur enhancement) ──────────────────────────────────

///|
/// Escape a string for safe embedding inside a JS single-quoted string literal.
fn escape_js_string(s : String) -> String {
  let mut result = ""
  for ch in s.iter() {
    if ch == '\\' {
      result = result + "\\\\"
    } else if ch == '\'' {
      result = result + "\\'"
    } else if ch == '"' {
      result = result + "\\\""
    } else if ch == '\n' {
      result = result + "\\n"
    } else if ch == '\r' {
      result = result + "\\r"
    } else if ch == '\t' {
      result = result + "\\t"
    } else {
      result = result + ch.to_string()
    }
  }
  result
}

///|
/// Dispatch fill with focus/blur evaluate_script enhancement.
/// focus/blur failures are silently ignored (graceful degradation).
fn Browser::dispatch_fill_enhanced(
  self : Browser,
  args : Map[String, Json],
) -> ToolResult {
  // Pre-fill: focus the target element for framework compatibility
  match args.get("ref") {
    Some(String(ref_val)) => {
      let escaped = escape_js_string(ref_val)
      let focus_script = "document.querySelector('[data-ref=\"\{escaped}\"]')?.focus()"
      let focus_args : Map[String, Json] = { "js": focus_script.to_json() }
      ignore(self.with_page("evaluate_script", focus_args))
    }
    _ => ()
  }
  // Core fill operation
  let fill_result = self.with_page("fill", args)
  // Post-fill: blur the target element (best-effort, ignore failure)
  if !fill_result.is_error {
    match args.get("ref") {
      Some(String(ref_val)) => {
        let escaped = escape_js_string(ref_val)
        let blur_script = "document.querySelector('[data-ref=\"\{escaped}\"]')?.blur()"
        let blur_args : Map[String, Json] = { "js": blur_script.to_json() }
        ignore(self.with_page("evaluate_script", blur_args))
      }
      _ => ()
    }
  }
  fill_result
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
