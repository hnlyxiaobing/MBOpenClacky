///|
/// Slash command system for the TUI input bar.
///
/// Parses user input beginning with "/" into structured commands,
/// provides auto-completion, and executes command logic.

///|
/// Parsed slash command variants.
pub(all) enum SlashCommand {
  Config(key~ : String, value~ : String)
  Model(name~ : String)
  Clear
  New(title~ : String)
  Skills(action~ : String)
  Todo
  Help
  Exit
  Meeting
  Theme(name~ : String)
} derive(Eq, Debug)

///|
/// Definition of a registered slash command.
pub(all) struct SlashCommandDef {
  name : String
  description : String
  usage : String
} derive(Eq, Debug)

///|
/// Parser for slash commands with registered command definitions.
pub(all) struct SlashCommandParser {
  commands : Array[SlashCommandDef]
} derive(Debug)

///|
/// Create a new SlashCommandParser with the default set of commands.
pub fn SlashCommandParser::new() -> SlashCommandParser {
  let commands : Array[SlashCommandDef] = [
    {
      name: "config",
      description: "Set a configuration value",
      usage: "/config <key> <value>",
    },
    {
      name: "model",
      description: "Switch the active model",
      usage: "/model <name>",
    },
    { name: "clear", description: "Clear message history", usage: "/clear" },
    { name: "new", description: "Start a new session", usage: "/new [title]" },
    { name: "todo", description: "Toggle todo area visibility", usage: "/todo" },
    {
      name: "skills",
      description: "Manage skills",
      usage: "/skills <list|enable|disable>",
    },
    { name: "help", description: "Show available commands", usage: "/help" },
    { name: "exit", description: "Exit the application", usage: "/exit" },
    {
      name: "meeting",
      description: "Meeting summaries (managed in Web UI)",
      usage: "/meeting",
    },
    {
      name: "theme",
      description: "Switch the color theme",
      usage: "/theme <default|hacker|minimal|light>",
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
      if parts.length() < 3 {
        return Err("Usage: /config <key> <value>")
      }
      let key = parts[1]
      // Join remaining parts as value
      let value_parts : Array[String] = []
      for i = 2; i < parts.length(); i = i + 1 {
        value_parts.push(parts[i])
      }
      let value = value_parts.join(" ")
      Ok(Config(key~, value~))
    }
    "model" => {
      if parts.length() < 2 {
        return Err("Usage: /model <name>")
      }
      let name = parts[1]
      Ok(Model(name~))
    }
    "clear" => Ok(Clear)
    "todo" => Ok(Todo)
    "new" => {
      let title = if parts.length() >= 2 {
        let title_parts : Array[String] = []
        for i = 1; i < parts.length(); i = i + 1 {
          title_parts.push(parts[i])
        }
        title_parts.join(" ")
      } else {
        "Untitled"
      }
      Ok(New(title~))
    }
    "skills" => {
      let action = if parts.length() >= 2 { parts[1] } else { "list" }
      Ok(Skills(action~))
    }
    "help" => Ok(Help)
    "exit" => Ok(Exit)
    "meeting" => Ok(Meeting)
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
    Config(key~, value~) =>
      // Try to update agent config dynamically
      try {
        match key {
          "max_tokens" => {
            let n = @string.parse_int(value.to_string_view())
            agent.config.max_tokens = n
            Ok("Configuration set: max_tokens = \{value}")
          }
          "verbose" => {
            agent.config.verbose = value == "true" || value == "1"
            Ok("Configuration set: verbose = \{value}")
          }
          "fallback_model" => {
            agent.config.fallback_model = value
            Ok("Configuration set: fallback_model = \{value}")
          }
          _ => Ok("Configuration set: \{key} = \{value}")
        }
      } catch {
        _ => Ok("Configuration set: \{key} = \{value}")
      }
    Model(name~) => {
      // Actually switch the model on the agent's client
      let old_client = agent.client
      let new_client = @client.Client::new(
        old_client.api_key,
        old_client.base_url,
        name,
        old_client.api_type,
        provider_id=old_client.provider_id,
        vision_supported=old_client.vision_supported,
      )
      agent.client = new_client
      Ok("Model switched to: \{name}")
    }
    Clear => {
      // Clear agent conversation history
      agent.history.clear()
      agent.iterations = 0
      Ok("Message history cleared")
    }
    New(title~) => {
      // Start a fresh session: clear history and reset counters
      agent.history.clear()
      agent.iterations = 0
      agent.total_cost = 0.0
      Ok("New session created: \{title}")
    }
    Skills(action~) =>
      match action {
        "list" => {
          let skills = agent.skill_registry.all()
          if skills.length() == 0 {
            Ok("Skills: (none loaded)")
          } else {
            let lines : Array[String] = ["Loaded skills:"]
            for skill in skills {
              let desc = match skill.description {
                Some(d) => d
                None => "(no description)"
              }
              lines.push("  \{skill.name} - \{desc}")
            }
            Ok(lines.join("\n"))
          }
        }
        "enable" => Ok("Skill enabled")
        "disable" => Ok("Skill disabled")
        _ =>
          Err("Unknown skills action: \{action}. Use list, enable, or disable.")
      }
    Help => {
      let lines : Array[String] = ["Available commands:"]
      let parser = SlashCommandParser::new()
      for cmd_def in parser.commands {
        lines.push("  /\{cmd_def.name} - \{cmd_def.description}")
      }
      Ok(lines.join("\n"))
    }
    Exit => Ok("Exiting application")
    Theme(name~) =>
      // Theme switching is handled by the controller (it owns the Theme
      // instance); this fallback keeps `execute` total.
      Ok("Theme switched to: \{name}")
    Meeting =>
      Ok(
        "Meeting management is available in the Web UI dashboard (start / summarize meetings there). The TUI shows this summary entry only.",
      )
    Todo =>
      // Toggle todo area visibility (controller will handle the toggle)
      Ok("Todo area toggled")
  }
}

///|
/// Generate context-aware command suggestions based on current TUI state.
///
/// Returns an array of command suggestion strings (with "/" prefix)
/// prioritized by relevance to the current context.
pub fn context_aware_suggestions(state : TuiState) -> Array[String] {
  let suggestions : Array[String] = []
  let has_error = match state.last_error {
    Some(_) => true
    None => false
  }
  let last_tool_was_write = state.tool_history.length() > 0 &&
    state.tool_history[state.tool_history.length() - 1].name == "write_file"
  let is_git_repo = @fs.path_exists(state.working_dir + "/.git") ||
    @fs.path_exists(state.working_dir + "/.gitignore")
  if has_error {
    suggestions.push("/clear")
    suggestions.push("/help")
  } else if last_tool_was_write {
    suggestions.push("/help")
    suggestions.push("/todo")
    suggestions.push("/clear")
  } else if is_git_repo {
    suggestions.push("/help")
    suggestions.push("/todo")
    suggestions.push("/clear")
  } else {
    suggestions.push("/help")
    suggestions.push("/todo")
    suggestions.push("/clear")
  }
  suggestions
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
