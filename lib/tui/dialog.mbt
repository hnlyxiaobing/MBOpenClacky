///|
/// Dialog rendering for inline confirmation prompts.
///
/// Renders confirmation prompts as inline text lines (not full-screen
/// modals), consistent with the Inline Scrolling architecture.
/// The prompt is displayed above the input area and cleared after
/// the user responds.

///|
/// Render the confirmation dialog as an array of lines.
///
/// Returns an empty array if no confirmation is pending.
/// Lines include ANSI color codes for emphasis.
///
/// Format:
/// ```
/// ⚠ [tool_name] prompt_text  [y/N]
/// ```
/// Where `y/N` indicates yes/no with uppercase = default.
pub fn render_confirmation_lines(state : TuiState) -> Array[String] {
  let pending = match state.pending_confirmation {
    Some(p) => p
    None => return []
  }
  // Build the y/n indicator
  let yn = if pending.default_yes { "[Y/n]" } else { "[y/N]" }
  let warning = "\u{1b}[38;2;255;255;85m⚠\u{1b}[0m" // Yellow warning symbol
  let tool = "\u{1b}[1m\{pending.tool_name}\u{1b}[0m" // Bold tool name
  let prompt = pending.prompt_text
  let yn_styled = "\u{1b}[38;2;255;255;85m\{yn}\u{1b}[0m" // Yellow y/n indicator
  let line = "\{warning} [\{tool}] \{prompt}  \{yn_styled}"
  [line]
}

///|
/// Render the confirmation dialog as a single line string.
///
/// Returns empty string if no confirmation is pending.
pub fn render_confirmation_line(state : TuiState) -> String {
  let lines = render_confirmation_lines(state)
  if lines.length() == 0 {
    ""
  } else {
    lines[0]
  }
}

///|
/// Clear the confirmation prompt (produce ANSI clear line sequence).
///
/// Returns the ANSI escape sequence to clear the confirmation line.
pub fn clear_confirmation_sequence() -> String {
  "\r\u{1b}[K" // Carriage return + clear line
}

///|
/// Build the prompt text for a tool confirmation.
///
/// Creates a human-readable summary of the tool call.
pub fn build_tool_prompt(tool_name : String, tool_args : String) -> String {
  // Truncate args if too long
  let max_args = 60
  let display_args = if tool_args.length() > max_args {
    tool_args[0:max_args].to_owned() + "..."
  } else {
    tool_args
  }
  // Special formatting for known tools
  match tool_name {
    "terminal" => "Run: \{display_args}"
    "write" | "edit" => "Modify file: \{display_args}"
    "trash_manager" => "Delete: \{display_args}"
    _ => "Execute \{display_args}"
  }
}
