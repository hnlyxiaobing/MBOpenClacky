///|
/// Command suggestions dropdown for the TUI input bar.
///
/// Provides an auto-completion dropdown that appears when the user types
/// a "/" prefix. Shows matching slash commands with Tab/Up/Down navigation,
/// Enter to accept, and Escape to dismiss.

///|
/// A single suggestion item displayed in the dropdown.
pub(all) struct SuggestionItem {
  /// The command name including the "/" prefix (e.g. "/help").
  name : String
  /// Short description shown next to the command.
  description : String
  /// Usage hint (e.g. "/config <key> <value>").
  usage : String
} derive(Debug)

///|
/// A dropdown list of command suggestions with keyboard navigation.
///
/// Supports filtering by prefix, cycling through results with Tab/Up/Down,
/// and selecting with Enter. Renders as a bordered box with up to
/// `max_visible` items shown at once (with scroll indicator).
pub(all) struct CommandSuggestions {
  /// All registered commands (system + skill commands).
  commands : Array[SuggestionItem]
  /// Currently filtered (visible) items.
  mut filtered : Array[SuggestionItem]
  /// Index of the currently selected item in `filtered`.
  mut selected_index : Int
  /// Whether the dropdown is visible.
  mut visible : Bool
  /// Maximum number of items visible at once.
  max_visible : Int
} derive(Debug)

///|
/// Create a new CommandSuggestions with the default system commands.
pub fn CommandSuggestions::new() -> CommandSuggestions {
  let commands = default_system_commands()
  { commands, filtered: [], selected_index: 0, visible: false, max_visible: 5 }
}

///|
/// Create a CommandSuggestions with additional skill commands.
pub fn CommandSuggestions::with_skills(
  skill_commands : Array[SuggestionItem],
) -> CommandSuggestions {
  let commands = default_system_commands()
  for sc in skill_commands {
    commands.push(sc)
  }
  { commands, filtered: [], selected_index: 0, visible: false, max_visible: 5 }
}

///|
/// Update the filtered list based on a prefix string.
///
/// The prefix should start with "/" (e.g. "/he" matches "/help").
/// If the prefix is empty or doesn't start with "/", the dropdown is hidden.
pub fn CommandSuggestions::update_filter(
  self : CommandSuggestions,
  prefix : String,
) -> Unit {
  let trimmed = prefix.trim().to_owned()
  let chars = trimmed.to_array()
  if chars.length() == 0 || chars[0] != '/' {
    self.visible = false
    self.filtered = []
    self.selected_index = 0
    return
  }
  let search = trimmed[1:].to_owned().to_lower()
  let results : Array[SuggestionItem] = []
  for cmd in self.commands {
    let name_body = cmd.name[1:].to_owned().to_lower()
    if name_body.has_prefix(search) {
      results.push(cmd)
    }
  }
  self.filtered = results
  self.selected_index = 0
  self.visible = results.length() > 0
}

///|
/// Move selection to the next item (Tab / Down arrow).
pub fn CommandSuggestions::select_next(self : CommandSuggestions) -> Unit {
  if self.filtered.length() > 0 {
    self.selected_index = (self.selected_index + 1) % self.filtered.length()
  }
}

///|
/// Move selection to the previous item (Shift+Tab / Up arrow).
pub fn CommandSuggestions::select_prev(self : CommandSuggestions) -> Unit {
  if self.filtered.length() > 0 {
    if self.selected_index == 0 {
      self.selected_index = self.filtered.length() - 1
    } else {
      self.selected_index = self.selected_index - 1
    }
  }
}

///|
/// Accept the currently selected suggestion.
///
/// Returns the selected command name (with "/" prefix) if visible,
/// or None if the dropdown is not showing.
pub fn CommandSuggestions::accept(self : CommandSuggestions) -> String? {
  if self.visible &&
    self.filtered.length() > 0 &&
    self.selected_index < self.filtered.length() {
    Some(self.filtered[self.selected_index].name)
  } else {
    None
  }
}

///|
/// Accept the selected suggestion, returning the full SuggestionItem.
pub fn CommandSuggestions::accept_item(
  self : CommandSuggestions,
) -> SuggestionItem? {
  if self.visible &&
    self.filtered.length() > 0 &&
    self.selected_index < self.filtered.length() {
    Some(self.filtered[self.selected_index])
  } else {
    None
  }
}

///|
/// Show the dropdown (if there are filtered results).
pub fn CommandSuggestions::show(self : CommandSuggestions) -> Unit {
  if self.filtered.length() > 0 {
    self.visible = true
  }
}

///|
/// Hide the dropdown and reset selection.
pub fn CommandSuggestions::hide(self : CommandSuggestions) -> Unit {
  self.visible = false
  self.selected_index = 0
}

///|
/// Check if the dropdown is currently visible.
pub fn CommandSuggestions::is_visible(self : CommandSuggestions) -> Bool {
  self.visible
}

///|
/// Get the number of filtered results.
pub fn CommandSuggestions::result_count(self : CommandSuggestions) -> Int {
  self.filtered.length()
}

///|
/// Render the dropdown as an array of display strings.
///
/// Returns lines suitable for rendering above the input bar.
/// Uses Unicode box-drawing characters for the border and highlights
/// the selected item. The output includes a scroll indicator if
/// there are more results than `max_visible`.
pub fn CommandSuggestions::render(self : CommandSuggestions) -> Array[String] {
  if !self.visible || self.filtered.length() == 0 {
    return []
  }
  let lines : Array[String] = []
  // Top border
  lines.push(
    "┌─────────────────────────────────────┐",
  )
  // Calculate visible window
  let total = self.filtered.length()
  let window_start = if self.selected_index >= self.max_visible {
    self.selected_index - self.max_visible + 1
  } else {
    0
  }
  let window_end = if window_start + self.max_visible > total {
    total
  } else {
    window_start + self.max_visible
  }
  // Render visible items
  for i = window_start; i < window_end; i = i + 1 {
    let item = self.filtered[i]
    let marker = if i == self.selected_index { "▸" } else { " " }
    let name_padded = sugg_pad_right(item.name, 12)
    let desc = sugg_truncate(item.description, 20)
    let content = "│ \{marker} \{name_padded} \{desc} │"
    lines.push(sugg_pad_box_line(content))
  }
  // Scroll indicator
  if total > self.max_visible {
    let remaining = total - window_end
    let hint = if remaining > 0 {
      "│   \{remaining} more...                  │"
    } else {
      "│                               │"
    }
    lines.push(sugg_pad_box_line(hint))
  }
  // Bottom border with usage hint
  lines.push(
    "├─────────────────────────────────────┤",
  )
  let selected_item = self.filtered[self.selected_index]
  let usage_line = "│ \{selected_item.usage} │"
  lines.push(sugg_pad_box_line(usage_line))
  lines.push(
    "└─────────────────────────────────────┘",
  )
  lines
}

///|
/// Add a custom command to the suggestion list.
pub fn CommandSuggestions::add_command(
  self : CommandSuggestions,
  item : SuggestionItem,
) -> Unit {
  self.commands.push(item)
}

///|
/// Replace all commands with a new set.
pub fn CommandSuggestions::set_commands(
  self : CommandSuggestions,
  commands : Array[SuggestionItem],
) -> Unit {
  self.commands.clear()
  for cmd in commands {
    self.commands.push(cmd)
  }
}

// ── Internal helpers ────────────────────────────────────────────────

///|
/// Build the default system command list.
fn default_system_commands() -> Array[SuggestionItem] {
  [
    { name: "/clear", description: "Clear message history", usage: "/clear" },
    {
      name: "/config",
      description: "Set a configuration value",
      usage: "/config <key> <value>",
    },
    {
      name: "/model",
      description: "Switch the active model",
      usage: "/model <name>",
    },
    { name: "/new", description: "Start a new session", usage: "/new [title]" },
    {
      name: "/skills",
      description: "Manage skills",
      usage: "/skills <list|enable|disable>",
    },
    { name: "/help", description: "Show available commands", usage: "/help" },
    { name: "/exit", description: "Exit the application", usage: "/exit" },
    { name: "/quit", description: "Quit (alias for exit)", usage: "/quit" },
  ]
}

///|
/// Pad a string to a minimum width with spaces.
fn sugg_pad_right(s : String, min_width : Int) -> String {
  let current = string_display_width(s)
  if current >= min_width {
    s
  } else {
    let padding = min_width - current
    let sb = StringBuilder::new()
    sb.write_string(s)
    for j = 0; j < padding; j = j + 1 {
      sb.write_char(' ')
    }
    sb.to_string()
  }
}

///|
/// Truncate a string to a maximum display width, adding "..." if truncated.
fn sugg_truncate(s : String, max_width : Int) -> String {
  let width = string_display_width(s)
  if width <= max_width {
    s
  } else {
    let sb = StringBuilder::new()
    let mut current_width = 0
    let target = max_width - 3 // room for "..."
    for c in s.iter() {
      let cw = char_display_width(c)
      if current_width + cw > target {
        break
      }
      sb.write_char(c)
      current_width = current_width + cw
    }
    sb.write_string("...")
    sb.to_string()
  }
}

///|
/// Pad a box line to the standard width (39 columns between borders).
fn sugg_pad_box_line(line : String) -> String {
  let target_width = 39 // total box width including borders
  let current = string_display_width(line)
  if current >= target_width {
    line
  } else {
    // Insert spaces before the last character (the right border │)
    let chars = line.to_array()
    if chars.length() < 2 {
      return line
    }
    let sb = StringBuilder::new()
    for i = 0; i < chars.length() - 1; i = i + 1 {
      sb.write_char(chars[i])
    }
    let padding = target_width - current
    for j = 0; j < padding; j = j + 1 {
      sb.write_char(' ')
    }
    sb.write_char(chars[chars.length() - 1])
    sb.to_string()
  }
}
