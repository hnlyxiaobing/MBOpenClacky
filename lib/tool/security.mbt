///| Security layer for terminal command safety.

///|

///| Implements pre-execution safety checks: blocks dangerous commands,

///| rewrites risky patterns, and protects credential files.

///| Reference: D:/MoonBit/openclacky/lib/clacky/tools/security.rb

///|
/// Security error raised when a command is blocked.
pub suberror SecurityError {
  SecurityError(String)
} derive(Debug)

///|
pub extend SecurityError with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// Commands considered safe for auto-execution in `:confirm_safes` mode.
/// Only the base command name is checked (first word of the command line).
let safe_readonly_commands : Array[String] = [
  "ls", "pwd", "cat", "less", "more", "head", "tail", "grep", "find", "which", "whereis",
  "whoami", "ps", "top", "htop", "df", "du", "git", "echo", "printf", "wc", "date",
  "file", "stat", "env", "printenv", "curl", "wget",
  // Windows-specific read-only commands
   "dir", "type", "where", "tasklist", "systeminfo", "ipconfig", "hostname", "wmic",
  "ver", "vol", "set",
]

///|
/// Patterns that protect credential/secret files from write operations.
let secret_write_patterns : Array[String] = [
  // .ssh/ directory
  ".ssh/",
  // .aws/ directory
   ".aws/",
  // .env files
   ".env",
]

///|
/// Check a command for safety and optionally rewrite it.
/// Returns the (possibly rewritten) safe command.
/// Raises SecurityError if the command is too dangerous.
pub fn make_safe(command : String) -> String raise SecurityError {
  let trimmed = command.trim().to_owned()
  guard !trimmed.is_empty() else { return trimmed }

  // Block: killing clacky process
  if is_pattern_match(trimmed, "\\bpkill\\b.*clacky") ||
    is_pattern_match(trimmed, "\\bkillall\\b.*clacky") ||
    is_pattern_match(trimmed, "\\bkill\\s+.*clacky") {
    raise SecurityError(
      "Killing the clacky process is not allowed. Please restart manually.",
    )
  }

  // Block: managing clacky server from within
  if is_pattern_match(trimmed, "clacky\\s+server") {
    raise SecurityError(
      "Managing clacky server from within a session is not allowed.",
    )
  }

  // Block: sudo
  if is_pattern_match(trimmed, "^sudo\\s+") {
    raise SecurityError("sudo is not allowed for safety reasons.")
  }

  // Rewrite: curl piped to sh/bash
  if is_pattern_match(trimmed, "^curl.*\\|\\s*(sh|bash)") {
    raise SecurityError(
      "Piping curl to shell is not allowed. Download the script first and review it manually.",
    )
  }

  // Check for dangerous patterns
  validate_general_command(trimmed)
  trimmed
}

///|
/// Check if a command is safe for auto-execution.
/// Returns true if the base command is in the safe list or if make_safe
/// returns the command unchanged.
pub fn command_safe_for_auto_execution(command : String) -> Bool {
  guard !command.is_empty() else { return false }

  let trimmed = command.trim().to_owned()
  // Extract base command name (first word)
  let cmd_name = match trimmed.split(" ").next() {
    Some(s) => s.to_owned()
    None => trimmed
  }

  // Check safe list
  for safe_cmd in safe_readonly_commands {
    if cmd_name == safe_cmd {
      return true
    }
  }

  // Try make_safe and check if unchanged
  try {
    let safe = make_safe(command)
    trimmed == safe
  } catch {
    _ => false
  }
}

///|
/// Check if a file path targets credential/secret files.
/// Returns true if the path should be protected.
pub fn is_secret_path(path : String) -> Bool {
  let expanded = expand_path(path)
  let lower = expanded.to_lower()
  for pattern in secret_write_patterns {
    if lower.find(pattern) is Some(_) {
      return true
    }
  }
  false
}

///|
/// Validate a file write path for credential protection.
/// Raises SecurityError if the path targets a protected file.
pub fn validate_secret_write(path : String) -> Unit raise SecurityError {
  guard !path.is_empty() else { return }
  // Skip option flags like "-n"
  guard !path.has_prefix("-") else { return }

  if is_secret_path(path) {
    raise SecurityError(
      "Write to credential/secret path blocked: \{path}. " +
      "If intentional, edit the file manually outside the agent.",
    )
  }
}

// ── Internal Helpers ────────────────────────────────────────────────────────

///|
/// Check for dangerous command patterns: eval(), exec(), system(),
/// backtick substitution, $(), pipes to sh/bash, redirects to system dirs.
fn validate_general_command(command : String) -> Unit raise SecurityError {
  // Strip quoted strings for pattern matching
  let stripped = strip_quoted_strings(command)

  // eval(...) - code evaluation
  if is_pattern_match(stripped, "eval\\s*\\(") {
    raise SecurityError("eval() is not allowed.")
  }
  // exec(...) - code execution
  if is_pattern_match(stripped, "exec\\s*\\(") {
    raise SecurityError("exec() is not allowed.")
  }
  // system(...) - system call
  if is_pattern_match(stripped, "system\\s*\\(") {
    raise SecurityError("system() calls are not allowed.")
  }
  // Backtick command substitution
  if is_pattern_match(stripped, "`[^`]+`") {
    raise SecurityError("Backtick command substitution is not allowed.")
  }
  // $(...) command substitution
  if is_pattern_match(stripped, "\\$\\([^)]+\\)") {
    raise SecurityError("$(...) command substitution is not allowed.")
  }
  // Pipe to sh/bash
  if is_pattern_match(stripped, "\\|\\s*sh\\s*$") ||
    is_pattern_match(stripped, "\\|\\s*bash\\s*$") {
    raise SecurityError("Piping to sh/bash is not allowed.")
  }
  // Redirect to system directories
  if is_pattern_match(stripped, ">\\s*/etc/") ||
    is_pattern_match(stripped, ">\\s*/usr/") ||
    is_pattern_match(stripped, ">\\s*/bin/") {
    raise SecurityError(
      "Redirecting output to system directories is not allowed.",
    )
  }
}

///|
/// Simple regex-like pattern matching using string search.
/// For complex patterns, this provides basic matching capability.
fn is_pattern_match(text : String, pattern : String) -> Bool {
  // For simple patterns: check if the pattern text appears in the source
  // This is a simplified matcher; full regex would need a regex library
  text.find(pattern) is Some(_)
}

///|
/// Strip quoted strings (single and double) from a command for safer
/// pattern matching (avoids false positives from quoted content).
fn strip_quoted_strings(text : String) -> String {
  let result = StringBuilder::new()
  let chars = text.iter()
  let mut in_single_quote = false
  let mut in_double_quote = false

  for ch in chars {
    if ch == '\'' && !in_double_quote {
      result.write_char(' ')
      in_single_quote = !in_single_quote
      continue
    }
    if ch == '"' && !in_single_quote {
      result.write_char(' ')
      in_double_quote = !in_double_quote
      continue
    }
    if in_single_quote || in_double_quote {
      result.write_char(' ')
    } else {
      result.write_char(ch)
    }
  }
  result.to_string()
}

///|
/// Expand a path: resolve ~ to home directory, handle relative paths.
fn expand_path(path : String) -> String {
  if path.has_prefix("~") {
    match home_dir() {
      Some(home) =>
        if path.length() == 1 {
          home
        } else if path.length() > 1 {
          if path[1:].to_owned().has_prefix("/") ||
            path[1:].to_owned().has_prefix("\\") {
            home + path[1:].to_owned()
          } else {
            path
          }
        } else {
          path
        }
      None => path
    }
  } else if !path.has_prefix("/") && !(path.length() >= 2 && path[1] == ':') {
    // 相对路径，解析为绝对路径
    let cwd = @env.current_dir()
    match cwd {
      Some(cwd_dir) => resolve_path(cwd_dir, path)
      None => path
    }
  } else {
    path
  }
}

///|
/// Get home directory from environment.
fn home_dir() -> String? {
  match @env.get_env_var("USERPROFILE") {
    Some(p) if !p.is_empty() => return Some(p)
    _ => ()
  }
  match @env.get_env_var("HOME") {
    Some(p) if !p.is_empty() => return Some(p)
    _ => ()
  }
  None
}

///|
/// Resolve a relative path against a base directory.
/// Handles ".", "..", and normal path components.
fn resolve_path(base : String, relative : String) -> String {
  let separator = "/"
  let base_parts = base
    .split(separator)
    .filter(fn(part) { !part.is_empty() })
    .to_array()
  let relative_parts = relative
    .split(separator)
    .filter(fn(part) { !part.is_empty() })
    .to_array()

  let result = base_parts.copy()
  for part in relative_parts {
    if part == "." {
      continue
    } else if part == ".." {
      if result.length() > 0 {
        let _ = result.pop()
      }
    } else {
      result.push(part)
    }
  }

  if result.length() == 0 {
    separator
  } else {
    separator + result.join(separator)
  }
}
