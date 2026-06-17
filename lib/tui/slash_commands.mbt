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
  Help
  Exit
} derive(Eq, Debug, Show)

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
    {
      name: "skills",
      description: "Manage skills",
      usage: "/skills <list|enable|disable>",
    },
    { name: "help", description: "Show available commands", usage: "/help" },
    { name: "exit", description: "Exit the application", usage: "/exit" },
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
  let trimmed = input.trim().to_string()
  let trimmed_chars = trimmed.to_array()
  if trimmed_chars.length() == 0 || trimmed_chars[0] != '/' {
    return Err("Input is not a slash command")
  }

  // Remove leading '/'
  let body = trimmed.substring(start=1)
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

  let search = prefix.substring(start=1).to_string()
  for cmd in self.commands {
    if cmd.name.has_prefix(search) {
      results.push("/\{cmd.name}")
    }
  }
  results
}

///|
/// Execute a slash command, returning a descriptive result string.
///
/// Note: Actual I/O operations are deferred; this returns descriptions
/// of what would happen.
pub fn execute(cmd : SlashCommand) -> Result[String, String] {
  match cmd {
    Config(key~, value~) => Ok("Configuration set: \{key} = \{value}")
    Model(name~) => Ok("Model switched to: \{name}")
    Clear => Ok("Message history cleared")
    New(title~) => Ok("New session created: \{title}")
    Skills(action~) =>
      match action {
        "list" => Ok("Skills: (none loaded)")
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
