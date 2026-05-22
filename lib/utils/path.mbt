///| Path utilities for MBOpenClacky configuration and data directories.

///|
/// The configuration directory name under the user's home directory.
let config_dir_name : String = ".mbopenclacky"

///|
/// Resolve the user's home directory from environment variables.
/// Returns USERPROFILE on Windows, HOME on Unix-like systems.
pub fn home_dir() -> String? {
  // Try USERPROFILE first (Windows)
  match @sys.get_env_var("USERPROFILE") {
    Some(p) if !p.is_empty() => return Some(p)
    _ => ()
  }
  // Fall back to HOME (Unix/macOS)
  match @sys.get_env_var("HOME") {
    Some(p) if !p.is_empty() => return Some(p)
    _ => ()
  }
  None
}

///|
/// Get the configuration directory path: `~/.mbopenclacky/`.
/// Returns None if home directory cannot be determined.
pub fn config_dir() -> String? {
  match home_dir() {
    Some(home) =>
      Some(@path.Path::join(home, @path.Path(config_dir_name)).to_string())
    None => None
  }
}

///|
/// Get the default configuration file path: `~/.mbopenclacky/config.toml`.
/// Returns None if home directory cannot be determined.
pub fn config_file() -> String? {
  match config_dir() {
    Some(dir) =>
      Some(@path.Path::join(dir, @path.Path("config.toml")).to_string())
    None => None
  }
}

///|
/// Get the sessions directory path: `~/.mbopenclacky/sessions/`.
/// Returns None if home directory cannot be determined.
pub fn sessions_dir() -> String? {
  match config_dir() {
    Some(dir) => Some(@path.Path::join(dir, @path.Path("sessions")).to_string())
    None => None
  }
}

///|
/// Get the global skills directory path: `~/.mbopenclacky/skills/`.
/// Returns None if home directory cannot be determined.
pub fn skills_dir() -> String? {
  match config_dir() {
    Some(dir) => Some(@path.Path::join(dir, @path.Path("skills")).to_string())
    None => None
  }
}

///|
/// Ensure a directory exists, creating it (and any missing parents) if needed.
/// Unlike `@fs.create_dir`, this creates intermediate directories.
pub fn ensure_dir(dir : String) -> Unit {
  if @fs.path_exists(dir) {
    return
  }
  // Create parent directories first
  let parent = @path.Path::dirname(@path.Path(dir)).to_string()
  if !parent.is_empty() && parent != dir && !@fs.path_exists(parent) {
    ensure_dir(parent)
  }
  @fs.create_dir(dir) catch {
    _ => ()
  }
}
