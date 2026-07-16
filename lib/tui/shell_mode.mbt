///|
/// Shell mode switching helpers for TUI-05.

///|
/// Cycle to the next shell mode: Chat -> FileBrowser -> Config -> Chat.
pub fn cycle_shell_mode(mode : ShellMode) -> ShellMode {
  match mode {
    Chat => FileBrowser
    FileBrowser => Config
    Config => Chat
  }
}

///|
/// Get a human-readable label for a shell mode.
pub fn shell_mode_label(mode : ShellMode) -> String {
  match mode {
    Chat => "Chat"
    FileBrowser => "File Browser"
    Config => "Config"
  }
}

///|
/// Get a short indicator string for the mode bar.
pub fn shell_mode_indicator(mode : ShellMode) -> String {
  match mode {
    Chat => "[Chat]"
    FileBrowser => "[Files]"
    Config => "[Config]"
  }
}

///|
/// Get the help text for the current shell mode.
pub fn shell_mode_help(mode : ShellMode) -> String {
  match mode {
    Chat =>
      "Enter Send  Ctrl-C Cancel  Tab Switch Mode  ↑↓ Scroll  /help Commands"
    FileBrowser =>
      "↑↓ Navigate  Enter Open/Preview  Backspace Up Dir  Esc Back to Chat  Tab Switch Mode"
    Config => "↑↓ Navigate  Enter Edit  Esc Back to Chat  Tab Switch Mode"
  }
}
