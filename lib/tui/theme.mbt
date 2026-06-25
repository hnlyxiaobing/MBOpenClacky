///|
/// Theme system for TUI color customization.
///
/// Provides predefined color themes (Default, Hacker, Minimal) using ANSI
/// escape codes. Components use the active theme to render consistent colors.

///|
/// Available theme presets.
pub(all) enum ThemeName {
  Hacker
  Minimal
  Default
} derive(Eq, Debug, Show)

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
} derive(Eq, Debug, Show)

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
  }
}

///|
/// Create a theme from a ThemeName.
pub fn Theme::from_name(name : ThemeName) -> Theme {
  match name {
    Hacker => Theme::hacker()
    Minimal => Theme::minimal()
    Default => Theme::default_()
  }
}
