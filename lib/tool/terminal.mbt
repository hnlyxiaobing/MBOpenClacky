///| Terminal tool: execute shell commands with safety checks.

///|

///| Five call shapes: run, background, continue, poll, kill.

///| All commands pass through Security.make_safe before execution.

///|
/// Reference: D:/MoonBit/openclacky/lib/clacky/tools/terminal.rb
pub(all) struct Terminal {
  timeout : Int
  max_output_chars : Int
} derive(Eq, Debug)

///|
pub fn Terminal::new() -> Terminal {
  { timeout: 30000, max_output_chars: 100000 }
}

///|
impl Tool for Terminal with fn name(_) -> String {
  "terminal"
}

///|
impl Tool for Terminal with fn description(_) -> String {
  "PROPOSE a command to run on behalf of the user.\n" +
  "If you have this tool, note that you DO have the ability to run commands directly on the USER's system.\n" +
  "In using these tools, adhere to the following guidelines:\n" +
  "1. Execute system commands directly, adapting to the user's OS and shell.\n" +
  "2. If in a new shell, cd to the appropriate directory first.\n" +
  "3. For commands that require user interaction, PASS THE NON-INTERACTIVE FLAGS.\n" +
  "4. For commands that use a pager, disable paging.\n" +
  "5. Dont include any newlines in the command.\n" +
  "6. CRITICAL: Commands touching files outside the workspace need user approval.\n\n" +
  "Git Safety Protocol:\n" +
  "- NEVER update the git config\n" +
  "- NEVER run destructive/irreversible git commands unless the user explicitly requests them\n" +
  "- NEVER skip hooks unless the user explicitly requests it\n" +
  "- NEVER run force push to main/master\n" +
  "- NEVER commit changes unless the user explicitly asks you to."
}

///|
impl Tool for Terminal with fn parameters(_) -> Json {
  Json::object({
    "type": "object".to_json(),
    "properties": Json::object({
      "command": Json::object({
        "type": "string".to_json(),
        "description": "The CLI command to execute".to_json(),
      }),
      "background": Json::object({
        "type": "boolean".to_json(),
        "description": "Set to true to run the command in the background".to_json(),
      }),
      "session_id": Json::object({
        "type": "integer".to_json(),
        "description": "Session ID to continue or kill a running session".to_json(),
      }),
      "input": Json::object({
        "type": "string".to_json(),
        "description": "Input to send to an existing session".to_json(),
      }),
      "cwd": Json::object({
        "type": "string".to_json(),
        "description": "Working directory for the command".to_json(),
      }),
      "timeout": Json::object({
        "type": "integer".to_json(),
        "description": "Maximum execution time in milliseconds (default: 30000)".to_json(),
      }),
      "kill": Json::object({
        "type": "boolean".to_json(),
        "description": "Set to true to kill a running session".to_json(),
      }),
    }),
  })
}

///|
impl Tool for Terminal with fn category(_) -> ToolCategory {
  Execution
}

///|
impl Tool for Terminal with fn execute(self, args : Map[String, Json]) -> ToolResult {
  let session_id = get_int_opt(args, "session_id")
  let kill_flag = get_bool_arg(args, "kill", false)

  // Shape 5: Kill session
  if kill_flag {
    match session_id {
      Some(id) =>
        return ToolResult::success(
          "Session \{id} killed (PTY sessions not yet implemented)",
        )
      None =>
        return ToolResult::error("session_id is required when kill is true")
    }
  }

  // Shape 3/4: Continue session
  match session_id {
    Some(id) => {
      let input = match args.get("input") {
        Some(String(s)) => s
        _ => ""
      }
      if input.is_empty() {
        return ToolResult::success(
          "Session \{id}: waiting (PTY not yet implemented)",
        )
      } else {
        return ToolResult::success(
          "Session \{id}: input sent (PTY not yet implemented)",
        )
      }
    }
    _ => ()
  }

  // Shape 1/2: New command
  let command = match args.get("command") {
    Some(String(s)) => s
    _ =>
      return ToolResult::error("command is required for new terminal sessions")
  }

  guard !command.trim().is_empty() else {
    return ToolResult::error("command cannot be empty")
  }

  let background = get_bool_arg(args, "background", false)
  let cwd = match args.get("cwd") {
    Some(String(s)) => s
    _ => "."
  }
  let timeout = get_int_arg(args, "timeout", self.timeout)

  // Security check
  let safe_cmd = make_safe(command) catch {
    _ => return ToolResult::error("[Security] command validation failed")
  }
  if background {
    let raw_output = "[Terminal] Background: \{safe_cmd}\nPTY not yet implemented. Command validated by Security layer."
    let (cleaned, _) = process_terminal_output(
      raw_output,
      max_chars=self.max_output_chars,
    )
    ToolResult::success(cleaned)
  } else {
    let raw_output = "[Terminal] Command: \{safe_cmd}\nPTY not yet implemented. Command validated by Security layer.\nCWD: \{cwd}, Timeout: \{timeout}ms"
    let (cleaned, was_truncated) = process_terminal_output(
      raw_output,
      max_chars=self.max_output_chars,
    )
    if was_truncated {
      ToolResult::success(cleaned)
    } else {
      ToolResult::success(cleaned)
    }
  }
}

///|
impl Tool for Terminal with fn format_call(_, args : Map[String, Json]) -> String {
  let kill_flag = get_bool_arg(args, "kill", false)
  let session_id = get_int_opt(args, "session_id")

  if kill_flag {
    match session_id {
      Some(id) => return "terminal(stop session \{id})"
      None => return "terminal(?)"
    }
  }

  match session_id {
    Some(id) => {
      let input = match args.get("input") {
        Some(String(s)) => s
        _ => ""
      }
      return if input.is_empty() {
        "terminal(check output, session \{id})"
      } else {
        "terminal(send input, session \{id})"
      }
    }
    _ => ()
  }

  match args.get("command") {
    Some(String(cmd)) => {
      let display = if cmd.length() > 60 {
        cmd[:60].to_owned() + "..."
      } else {
        cmd
      }
      "terminal(\{display})"
    }
    _ => "terminal(?)"
  }
}

///|
impl Tool for Terminal with fn format_result(_, result : ToolResult) -> String {
  if result.is_error {
    if result.content.find("[Security]") is Some(_) {
      result.content
    } else {
      "Terminal error: \{result.content}"
    }
  } else {
    "[OK] Terminal completed"
  }
}

///|
impl Tool for Terminal with fn to_function_definition(self) -> FunctionDefinition {
  FunctionDefinition::new(self.name(), self.description(), self.parameters())
}

///|
fn get_int_opt(args : Map[String, Json], key : String) -> Int? {
  match args.get(key) {
    Some(Number(n, ..)) if n >= -2147483648.0 && n <= 2147483647.0 =>
      Some(n.to_int())
    Some(String(s)) =>
      Some(@string.parse_int(s.to_string_view())) catch {
        _ => None
      }
    _ => None
  }
}
