///| Login shell detection utilities.
/// Detects the current shell type, configuration paths, and interactive status.

///|
/// Shell type enumeration.
pub enum ShellType {
  Bash
  Zsh
  Fish
  Pwsh
  Cmd
  Unknown(String)
} derive(Debug, Eq)

///|
impl Show for ShellType with fn output(self, logger) {
  match self {
    Bash => logger.write_string("Bash")
    Zsh => logger.write_string("Zsh")
    Fish => logger.write_string("Fish")
    Pwsh => logger.write_string("PowerShell")
    Cmd => logger.write_string("Cmd")
    Unknown(s) => {
      logger.write_string("Unknown(")
      logger.write_string(s)
      logger.write_string(")")
    }
  }
}

///|
/// Detect the current login shell.
pub fn detect_login_shell() -> ShellType {
  // Check SHELL env var first (Unix-like systems)
  match env_var("SHELL") {
    Some(shell_path) => {
      let lower = shell_path.to_lower()
      if lower.contains("zsh") {
        Zsh
      } else if lower.contains("fish") {
        Fish
      } else if lower.contains("bash") {
        Bash
      } else {
        Unknown(shell_path)
      }
    }
    None =>
      // Check Windows shells
      match env_var("COMSPEC") {
        Some(_) => Cmd
        None =>
          match env_var("PSModulePath") {
            Some(_) => Pwsh
            None => Unknown("unknown")
          }
      }
  }
}

///|
/// Get shell configuration file path.
pub fn shell_config_path(shell : ShellType) -> String? {
  match home_dir() {
    Some(home) =>
      match shell {
        Bash => Some(home + "/.bashrc")
        Zsh => Some(home + "/.zshrc")
        Fish => Some(home + "/.config/fish/config.fish")
        Pwsh =>
          Some(home + "/Documents/PowerShell/Microsoft.PowerShell_profile.ps1")
        Cmd => None
        Unknown(_) => None
      }
    None => None
  }
}

///|
/// Get possible shell RC files (login + interactive rc).
pub fn shell_rc_files(shell : ShellType) -> Array[String] {
  match home_dir() {
    Some(home) =>
      match shell {
        Bash =>
          [
            home + "/.bash_profile",
            home + "/.bash_login",
            home + "/.profile",
            home + "/.bashrc",
          ]
        Zsh =>
          [
            home + "/.zprofile",
            home + "/.zshrc",
            home + "/.zshenv",
            home + "/.zlogin",
          ]
        Fish =>
          [home + "/.config/fish/config.fish", home + "/.config/fish/conf.d"]
        Pwsh => {
          let doc_profile = home +
            "/Documents/PowerShell/Microsoft.PowerShell_profile.ps1"
          let allusers = "/etc/powershell/profile.ps1"
          [doc_profile, allusers]
        }
        Cmd => [home + "/autoexec.bat"]
        Unknown(_) => []
      }
    None => []
  }
}

///|
/// Check if the login shell is interactive.
pub fn is_login_shell_interactive() -> Bool {
  // Check PS1 (set in interactive shells on Bash/Zsh)
  if env_var("PS1") is Some(_) {
    return true
  }
  // Check PROMPT (set in interactive cmd.exe)
  if env_var("PROMPT") is Some(_) {
    return true
  }
  false
}

///|
/// Get shell summary string.
pub fn shell_summary() -> String {
  let shell = detect_login_shell()
  let interactive = if is_login_shell_interactive() {
    "interactive"
  } else {
    "non-interactive"
  }
  "Shell: \{shell_name(shell)} (\{interactive})"
}

///|
/// Shell display name.
pub fn shell_name(shell : ShellType) -> String {
  match shell {
    Bash => "Bash"
    Zsh => "Zsh"
    Fish => "Fish"
    Pwsh => "PowerShell"
    Cmd => "Cmd"
    Unknown(s) => "Unknown(\{s})"
  }
}
