///|
/// Theme system for TUI color customization.
///
/// Provides predefined color themes (Default, Hacker, Minimal, Light) using ANSI
/// escape codes. Components use the active theme to render consistent colors.

///|
/// Available theme presets.
pub(all) enum ThemeName {
  Hacker
  Minimal
  Default
  Light
} derive(Eq, Debug)

///|
/// A color theme defined by ANSI escape code strings.
pub(all) struct Theme {
  name : ThemeName
  /// Primary text/accent color (ANSI escape code).
  primary_color : String
  /// Secondary/dim accent color.
  secondary_color : String
  /// Highlight/accent color.
  accent_color : String
  /// Error/warning color.
  error_color : String
  /// Dim/muted text color.
  dim_color : String
  /// Symbol for tool call entry (e.g. "[=>]").
  tool_call_symbol : String
  /// Symbol for tool result entry (e.g. "[<=]").
  tool_result_symbol : String
  /// Symbol for tool denied entry (e.g. "[!!]").
  tool_denied_symbol : String
  /// Symbol for shell command preview (e.g. "[C]").
  shell_preview_symbol : String
  /// Symbol for file preview entry (e.g. "[F]").
  file_preview_symbol : String
  /// Symbol for phase enter banner (e.g. "▼").
  phase_enter_symbol : String
  /// Symbol for phase exit banner (e.g. "▲").
  phase_exit_symbol : String
} derive(Eq, Debug)

///|
/// Create the default theme (blue/cyan tones).
pub fn Theme::default_() -> Theme {
  {
    name: Default,
    primary_color: "\u001b[34m",
    secondary_color: "\u001b[36m",
    accent_color: "\u001b[35m",
    error_color: "\u001b[31m",
    dim_color: "\u001b[90m",
    tool_call_symbol: "[=>]",
    tool_result_symbol: "[<=]",
    tool_denied_symbol: "[!!]",
    shell_preview_symbol: "[C]",
    file_preview_symbol: "[F]",
    phase_enter_symbol: "▼",
    phase_exit_symbol: "▲",
  }
}

///|
/// Create the hacker theme (green tones).
pub fn Theme::hacker() -> Theme {
  {
    name: Hacker,
    primary_color: "\u001b[32m",
    secondary_color: "\u001b[92m",
    accent_color: "\u001b[32m",
    error_color: "\u001b[31m",
    dim_color: "\u001b[90m",
    tool_call_symbol: "[=>]",
    tool_result_symbol: "[<=]",
    tool_denied_symbol: "[!!]",
    shell_preview_symbol: "[C]",
    file_preview_symbol: "[F]",
    phase_enter_symbol: "▼",
    phase_exit_symbol: "▲",
  }
}

///|
/// Create the minimal theme (white/gray tones).
pub fn Theme::minimal() -> Theme {
  {
    name: Minimal,
    primary_color: "\u001b[37m",
    secondary_color: "\u001b[97m",
    accent_color: "\u001b[37m",
    error_color: "\u001b[31m",
    dim_color: "\u001b[90m",
    tool_call_symbol: ">",
    tool_result_symbol: "<",
    tool_denied_symbol: "*",
    shell_preview_symbol: "$",
    file_preview_symbol: "#",
    phase_enter_symbol: ">",
    phase_exit_symbol: "<",
  }
}

///|
/// Create the light theme (dark text on light terminal backgrounds).
///
/// Uses darker ANSI colors so text remains legible against
/// a bright background.
pub fn Theme::light() -> Theme {
  {
    name: Light,
    primary_color: "\u001b[30m",
    secondary_color: "\u001b[34m",
    accent_color: "\u001b[35m",
    error_color: "\u001b[31m",
    dim_color: "\u001b[90m",
    tool_call_symbol: "[=>]",
    tool_result_symbol: "[<=]",
    tool_denied_symbol: "[!!]",
    shell_preview_symbol: "[C]",
    file_preview_symbol: "[F]",
    phase_enter_symbol: "▼",
    phase_exit_symbol: "▲",
  }
}

///|
/// Create a theme from a ThemeName.
pub fn Theme::from_name(name : ThemeName) -> Theme {
  match name {
    Hacker => Theme::hacker()
    Minimal => Theme::minimal()
    Default => Theme::default_()
    Light => Theme::light()
  }
}

///|
/// Return whether the terminal background is assumed to be light.
///
/// Currently returns `false` (dark background assumed). This stub can
/// be enhanced in the future with a terminal background-color query
/// (e.g., OSC 11 response) to auto-detect the actual background.
pub fn is_light_background() -> Bool {
  false
}

///|
/// Return all available theme presets.
pub fn all_themes() -> Array[Theme] {
  [Theme::default_(), Theme::hacker(), Theme::minimal(), Theme::light()]
}
