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
/// Commands that are irreversibly destructive and must require user
/// confirmation even when the rest of the command line passes `make_safe`.
/// MB 超集: Ruby 靠 PTY shell 函数拦截 `rm`（进回收站），MB 的 terminal
/// 层无该保护，故在静态层要求确认（spec 验收标准 2）。
let destructive_commands : Array[String] = [
  "rm", "shutdown", "reboot", "halt", "poweroff", "mkfs", "dd", "fdisk", "parted",
  "kill", "killall", "init",
]

///|
/// Commands considered safe for auto-execution in `:confirm_safes` mode.
/// Only the base command name is checked (first word of the command line).
let safe_readonly_commands : Array[String] = [
  "ls", "pwd", "cat", "less", "more", "head", "tail", "grep", "find", "which", "whereis",
  "whoami", "ps", "top", "htop", "df", "du", "git", "echo", "printf", "wc", "date",
  "file", "stat", "env", "printenv", "curl", "wget",
  // Windows-specific read-only commands
  // NOTE: `set` (can assign env vars) and `wmic` (supports `process call
  // create` etc.) were removed — both have write semantics and do not belong
  // in a read-only whitelist.
   "dir", "type", "where", "tasklist", "systeminfo", "ipconfig", "hostname", "ver",
  "vol",
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
    is_pattern_match(trimmed, "\\bkill[[:space:]]+.*clacky") {
    audit_log("block", "Killing the clacky process: \{trimmed}")
    raise SecurityError(
      "Killing the clacky process is not allowed. Please restart manually.",
    )
  }

  // Block: managing clacky server from within
  if is_pattern_match(trimmed, "clacky[[:space:]]+server") {
    audit_log("block", "Managing clacky server: \{trimmed}")
    raise SecurityError(
      "Managing clacky server from within a session is not allowed.",
    )
  }

  // Block: sudo (MB 超集 — 保留硬拦截并审计；Ruby 原语义为允许+记录，
  // 但 MB 含 server/无人值守场景，拦截更符合部署面。裁决记录见 spec 变更记录)
  if is_pattern_match(trimmed, "^sudo[[:space:]]+") {
    audit_log("block", "sudo command blocked: \{trimmed}")
    raise SecurityError("sudo is not allowed for safety reasons.")
  }

  // chmod +x: aligned with Ruby Replacer#replace_chmod_command — allowed,
  // but targets must not be credential/secret files.
  // NOTE: Ruby's `/^chmod\s+x/` does not actually match real-world
  // `chmod +x` usage (space then `+x`); MB intentionally matches
  // `^chmod[[:space:]]*\+x` as a safety enhancement (secret-file check).
  if is_pattern_match(trimmed, "^chmod[[:space:]]*\\+x") {
    validate_chmod_targets(trimmed)
    audit_log("allow", "chmod +x allowed: \{trimmed}")
    return trimmed
  }

  // Block: curl piped to sh/bash (MB 超集 — 保留硬拦截并审计；
  // Ruby 为"下载到文件供人工审查"，MB 无强制审查 UI 流，拒绝更符合场景)
  if is_pattern_match(trimmed, "^curl.*\\|[[:space:]]*(sh|bash)") {
    audit_log("block", "curl|sh blocked: \{trimmed}")
    raise SecurityError(
      "Piping curl to shell is not allowed. Download the script first and review it manually.",
    )
  }

  // Check for dangerous patterns
  try {
    validate_general_command(trimmed)
    trimmed
  } catch {
    SecurityError(msg) => {
      audit_log("block", "Dangerous pattern (\{msg}): \{trimmed}")
      raise SecurityError(msg)
    }
  }
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

  // Destructive commands always require confirmation (MB 超集，见 destructive_commands)
  for dcmd in destructive_commands {
    if cmd_name == dcmd {
      return false
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
/// Filename-level (path-segment) matching: `.ssh` directory, `.aws`
/// directory, and `.env` files (`.env` or `.env.*` as a path segment).
/// Segment matching avoids substring false positives such as
/// `release.env.bak` or a directory literally named `something.env.stuff`.
pub fn is_secret_path(path : String) -> Bool {
  let expanded = expand_path(path)
  let normalized = expanded.to_lower().replace_all(old="\\", new="/")
  for seg in normalized.split("/") {
    let s = seg.trim()
    if s == ".ssh" || s == ".aws" {
      return true
    }
    if s == ".env" || s.has_prefix(".env.") {
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
  if is_pattern_match(stripped, "eval[[:space:]]*\\(") {
    raise SecurityError("eval() is not allowed.")
  }
  // exec(...) - code execution
  if is_pattern_match(stripped, "exec[[:space:]]*\\(") {
    raise SecurityError("exec() is not allowed.")
  }
  // system(...) - system call
  if is_pattern_match(stripped, "system[[:space:]]*\\(") {
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
  if is_pattern_match(stripped, "\\|[[:space:]]*sh[[:space:]]*$") ||
    is_pattern_match(stripped, "\\|[[:space:]]*bash[[:space:]]*$") {
    raise SecurityError("Piping to sh/bash is not allowed.")
  }
  // Redirect to system directories
  if is_pattern_match(stripped, ">[[:space:]]*/etc/") ||
    is_pattern_match(stripped, ">[[:space:]]*/usr/") ||
    is_pattern_match(stripped, ">[[:space:]]*/bin/") {
    raise SecurityError(
      "Redirecting output to system directories is not allowed.",
    )
  }
}

///|
/// Regex pattern matching using the standard-library regex engine.
/// Falls back to literal matching if the pattern fails to compile, so a
/// malformed pattern can never silently disable a protection branch.
fn is_pattern_match(text : String, pattern : String) -> Bool {
  let re = @string.Regex::Regex(pattern) catch {
    _ => @string.Regex::string(pattern)
  }
  re.execute(text) is Some(_)
}

///|
/// Validate `chmod +x` targets: only credential/secret paths are blocked.
/// Mirrors Ruby Replacer#replace_chmod_command (skips the command and its
/// first argument `+x`, plus any other `-`/`+` prefixed flags).
fn validate_chmod_targets(command : String) -> Unit raise SecurityError {
  let parts = command.split(" ")
  let mut idx = 0
  for part in parts {
    if idx >= 2 && !part.has_prefix("-") && !part.has_prefix("+") {
      validate_secret_write(part.to_owned())
    }
    idx = idx + 1
  }
}

///|
/// Append a JSON-line entry to the safety audit log.
/// Location: ~/.clacky/safety_logs/<sanitized-cwd>/safety.log
/// Logging must never break main functionality — all failures are swallowed.
/// Timestamp uses ISO 8601 (aligned with Ruby `Time.now.iso8601`).
fn audit_log(action : String, message : String) -> Unit {
  let home = match home_dir() {
    Some(h) => h
    None => return
  }
  let cwd = match @env.current_dir() {
    Some(d) => d
    None => "default"
  }
  let hash = cwd
    .replace_all(old="/", new="_")
    .replace_all(old="\\", new="_")
    .replace_all(old=":", new="_")
  let log_dir = @path.Path(home)
    .join(@path.Path(".clacky"))
    .join(@path.Path("safety_logs"))
    .join(@path.Path(hash))
    .to_string()
  if !@fs.path_exists(log_dir) {
    @fs.create_dir(log_dir) catch {
      _ => return
    }
  }
  let log_file = @path.Path(log_dir).join(@path.Path("safety.log")).to_string()
  let ts = iso8601_now()
  let entry = Json::object({
      "timestamp": ts.to_json(),
      "action": action.to_json(),
      "message": message.to_json(),
    }).stringify() +
    "\n"
  // Append via read-modify-write (x/fs has no append API; audit logs stay small).
  let existing = @fs.read_file_to_string(log_file) catch { _ => "" }
  @fs.write_string_to_file(log_file, existing + entry) catch {
    _ => ()
  }
}

///|
/// Current wall-clock time as ISO 8601 (e.g. "2026-08-18T04:34:56Z").
/// Format aligned with Ruby `Time.now.iso8601` used by Security#write_log;
/// MB emits UTC (Z) — local-offset FFI is intentionally NOT extended here
/// (S-FFI-08: retain only the one local-offset FFI in lib/agent/time_stub.c).
fn iso8601_now() -> String {
  let ms = @env.now().reinterpret_as_int64()
  let sec = ms / 1000
  let dt = @time.PlainDateTime::from_unix_second(sec, 0, @time.utc_offset) catch {
    _ => return "1970-01-01T00:00:00Z"
  }
  dt.to_string() + "Z"
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
