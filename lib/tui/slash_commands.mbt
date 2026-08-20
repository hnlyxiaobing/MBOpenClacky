///|
/// Slash command system for the TUI input bar.
///
/// Parses user input beginning with "/" into structured commands,
/// provides auto-completion, and executes command logic.

///|
/// Parsed slash command variants.
pub(all) enum SlashCommand {
  /// No-arg `/config`: open the config menu (with-arg form was removed —
  /// the catch-all silently accepted unknown keys without effect).
  Config
  Model(name~ : String)
  Clear
  Help
  Exit
  Quit
  Theme(name~ : String)
  /// Open the time-machine undo menu.
  Undo
} derive(Eq, Debug)

///|
pub extend SlashCommand with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend SlashCommand with Eq::{not_equal, equal}

///|
/// Definition of a registered slash command.
pub(all) struct SlashCommandDef {
  name : String
  description : String
  usage : String
} derive(Eq, Debug)

///|
pub extend SlashCommandDef with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend SlashCommandDef with Eq::{not_equal, equal}

///|
/// Parser for slash commands with registered command definitions.
pub(all) struct SlashCommandParser {
  commands : Array[SlashCommandDef]
} derive(Debug)

///|
pub extend SlashCommandParser with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// Create a new SlashCommandParser with the default set of commands.
pub fn SlashCommandParser::new() -> SlashCommandParser {
  let commands : Array[SlashCommandDef] = [
    {
      name: "config",
      description: "Open configuration (models, API keys, settings)",
      usage: "/config",
    },
    {
      name: "model",
      description: "Open model selector or switch model (persisted)",
      usage: "/model [name]",
    },
    {
      name: "clear",
      description: "Start a fresh session (new session id)",
      usage: "/clear",
    },
    { name: "help", description: "Show available commands", usage: "/help" },
    { name: "exit", description: "Exit the application", usage: "/exit" },
    { name: "quit", description: "Quit (alias for exit)", usage: "/quit" },
    {
      name: "theme",
      description: "Switch the color theme",
      usage: "/theme <default|hacker|minimal|light>",
    },
    {
      name: "undo",
      description: "Open task history for undo/redo",
      usage: "/undo",
    },
  ]
  { commands, }
}

///|
/// Parse a user input string into a SlashCommand.
///
/// Returns Err if the input doesn't start with "/" or the command is unknown.
pub fn SlashCommandParser::parse(
  self : SlashCommandParser,
  input : String,
) -> Result[SlashCommand, String] {
  let trimmed = input.trim().to_owned()
  let trimmed_chars = trimmed.to_array()
  if trimmed_chars.length() == 0 || trimmed_chars[0] != '/' {
    return Err("Input is not a slash command")
  }

  // Remove leading '/'
  let body = trimmed[1:].to_owned()
  let parts = split_whitespace_impl(body)
  if parts.length() == 0 {
    return Err("Empty command")
  }

  let cmd_name = parts[0]
  match cmd_name {
    "config" => {
      // /config with arguments was removed (SPEC-03): configuration is
      // edited through the /config menu only, so any args are a usage
      // error rather than a silent no-op success.
      if parts.length() < 2 {
        return Ok(Config)
      }
      return Err("Usage: /config (opens the configuration menu)")
    }
    "model" => {
      if parts.length() < 2 {
        // No args: signal controller to open model selector
        return Ok(Model(name=""))
      }
      let name = parts[1]
      Ok(Model(name~))
    }
    "clear" => Ok(Clear)
    "help" => Ok(Help)
    "exit" => Ok(Exit)
    "quit" => Ok(Quit)
    "undo" => Ok(Undo)
    "theme" => {
      if parts.length() < 2 {
        return Err("Usage: /theme <default|hacker|minimal|light>")
      }
      let name = parts[1]
      match name {
        "default" | "hacker" | "minimal" | "light" => Ok(Theme(name~))
        _ =>
          Err(
            "Unknown theme: \{name}. Available: default, hacker, minimal, light",
          )
      }
    }
    _ => {
      // Check if this is a known command (for better error messages)
      let known = self.commands.iter().any(fn(c) { c.name == cmd_name })
      if known {
        Err("Failed to parse command: /\{cmd_name}")
      } else {
        Err("Unknown command: /\{cmd_name}")
      }
    }
  }
}

///|
/// Parse user input into a SlashCommand using the default command set.
///
/// Shared entry point used by both TuiController and the eval simulator so
/// slash-command routing stays consistent between them.
pub fn parse_slash_command(text : String) -> Result[SlashCommand, String] {
  SlashCommandParser::new().parse(text)
}

///|
/// Get auto-completion suggestions for a prefix string.
///
/// The prefix should start with "/" (e.g. "/he" -> ["/help"]).
pub fn SlashCommandParser::get_completions(
  self : SlashCommandParser,
  prefix : String,
) -> Array[String] {
  let results : Array[String] = []
  let prefix_chars = prefix.to_array()
  if prefix_chars.length() == 0 || prefix_chars[0] != '/' {
    return results
  }

  let search = prefix[1:].to_owned()
  for cmd in self.commands {
    if cmd.name.has_prefix(search) {
      results.push("/\{cmd.name}")
    }
  }
  results
}

///|
/// Execute a slash command with real agent operations.
///
/// Performs actual I/O where possible (model switch, history clear, etc.).
/// Falls back to descriptive text if the API doesn't support an operation.
pub fn execute(
  cmd : SlashCommand,
  agent : @agent.Agent,
) -> Result[String, String] {
  match cmd {
    Config =>
      // /config is handled by the controller (opens the config menu);
      // this fallback keeps `execute` total.
      Ok("Use /config to open the configuration menu")
    Model(name~) => {
      // Match a configured model card by card id or model name, then take
      // the same path as the menu selector: switch_model_by_id (session
      // switch) + set_default_model_by_id (pin the default badge, Ruby
      // cli.rb:304-335) + client rebuild. Persistence is layered on top
      // by the controller (it owns the config path and saves after execute).
      let mut matched : @config.ModelConfig? = None
      for m in agent.config.models {
        if m.id == name || m.model == name {
          matched = Some(m)
          break
        }
      }
      match matched {
        Some(m) =>
          match agent.config.switch_model_by_id(m.id) {
            Ok(_) => {
              ignore(agent.config.set_default_model_by_id(m.id))
              agent.rebuild_client_from_config()
              // Switching cards invalidates the per-session sub-model
              // overlay (it was pinned for the previous card).
              agent.set_session_sub_model(None)
              Ok("Model switched to: \{m.model}")
            }
            Err(msg) => Err(msg)
          }
        None =>
          Err("Unknown model: \{name}. Run /model to pick a configured model.")
      }
    }
    Clear => {
      // New-session semantics (Ruby cli.rb:998-1026): the agent resets in
      // place — cancel idle timer, new session_id, client rebuilt from the
      // current config, history/todo/cost cleared, idle timer rebound.
      agent.reset_session()
      Ok("Session cleared. Starting fresh.")
    }
    Help => {
      let name_col = 12
      let lines : Array[String] = ["Available commands:"]
      let parser = SlashCommandParser::new()
      for cmd_def in parser.commands {
        let padded_name = "/\{cmd_def.name}"
        let pad_count = name_col - padded_name.length()
        let pad = if pad_count > 0 { " ".repeat(pad_count) } else { "" }
        lines.push("  \{padded_name}\{pad}\{cmd_def.description}")
      }
      lines.push("")
      lines.push("Keyboard shortcuts:")
      let key_col = 12
      let shortcuts : Array[(String, String)] = [
        ("Enter", "Send message"),
        ("Ctrl+J", "Insert newline"),
        ("Ctrl+V", "Paste text (folds to [#N Paste Text])"),
        ("Ctrl+C", "Cancel / Quit"),
        ("Ctrl+D", "Quit (when input empty)"),
        ("Ctrl+L", "Redraw screen"),
        ("Ctrl+K", "Kill to end of line"),
        ("Ctrl+U", "Kill to start of line"),
        ("Ctrl+W", "Kill previous word"),
        ("Tab", "Complete command / Insert newline"),
        ("Up/Down", "Browse history / Navigate"),
        ("Escape", "Dismiss suggestions / Time Machine menu"),
        ("Shift+Tab", "Cycle permission mode"),
      ]
      for i = 0; i < shortcuts.length(); i = i + 1 {
        let (key, desc) = shortcuts[i]
        let pad_count = key_col - key.length()
        let pad = if pad_count > 0 { " ".repeat(pad_count) } else { "" }
        lines.push("  \{key}\{pad}\{desc}")
      }
      // User-invocable skills are callable as slash commands (Ruby
      // skills_by_command) — list them so /help stays truthful.
      let skills = agent.skill_registry.list_user_invocable()
      if skills.length() > 0 {
        lines.push("")
        lines.push("Skill commands:")
        for skill in skills {
          let padded_name = "/\{skill.name}"
          let pad_count = name_col - padded_name.length()
          let pad = if pad_count > 0 { " ".repeat(pad_count) } else { "" }
          let desc = match skill.description {
            Some(d) => d
            None => "(skill)"
          }
          lines.push("  \{padded_name}\{pad}\{desc}")
        }
      }
      Ok(lines.join("\n"))
    }
    Exit => Ok("Exiting application")
    Quit => Ok("Exiting application")
    Theme(name~) =>
      // Theme switching is handled by the controller (it owns the Theme
      // instance); this fallback keeps `execute` total.
      Ok("Theme switched to: \{name}")
    Undo =>
      // /undo is handled by the controller (opens a menu); fallback text.
      Ok("Time machine: use the controller to open the undo menu")
  }
}

///|
/// Generate context-aware command suggestions based on current TUI state.
///
/// Returns an array of command suggestion strings (with "/" prefix)
/// prioritized by relevance to the current context.
pub fn context_aware_suggestions(state : TuiState) -> Array[String] {
  let has_error = match state.last_error {
    Some(_) => true
    None => false
  }
  let last_tool_was_write = state.tool_history.length() > 0 &&
    state.tool_history[state.tool_history.length() - 1].name == "write_file"
  if has_error {
    // After an error: start fresh, undo file changes, or read help.
    ["/clear", "/undo", "/help"]
  } else if last_tool_was_write {
    // After a file write: undo is the most relevant follow-up.
    ["/undo", "/help"]
  } else {
    ["/help", "/model", "/clear"]
  }
}

///|
/// Split a string on whitespace into non-empty parts.
fn split_whitespace_impl(s : String) -> Array[String] {
  let parts : Array[String] = []
  let chars = s.to_array()
  let current = StringBuilder::new()
  for i = 0; i < chars.length(); i = i + 1 {
    let c = chars[i]
    if c == ' ' || c == '\t' {
      if current.to_string().length() > 0 {
        parts.push(current.to_string())
        current.reset()
      }
    } else {
      current.write_char(c)
    }
  }
  if current.to_string().length() > 0 {
    parts.push(current.to_string())
  }
  parts
}
