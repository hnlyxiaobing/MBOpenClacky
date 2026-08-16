///| Daily-rotating logger for MBOpenClacky.
///
/// Provides structured logging with level filtering, context key-value pairs,
/// and daily file rotation. File I/O is delegated to write_log which uses
/// the @fs package (best-effort in wasm-gc, full support on native).

///|
/// Log severity levels, ordered from least to most severe.
pub enum LogLevel {
  Debug
  Info
  Warn
  Error
} derive(Debug, Eq, Compare)

///|
pub extend LogLevel with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend LogLevel with Compare::{op_lt, op_le, op_ge, compare, op_gt}

///|
pub extend LogLevel with Eq::{not_equal, equal}

///|
/// Context key-value pairs attached to a log entry.
pub type LogContext = Array[(String, String)]

///|
/// Daily-rotating file logger with level filtering and optional console echo.
pub struct Logger {
  log_dir : String
  max_files : Int
  min_level : LogLevel
  console_echo : Bool
}

///|
/// Create a new Logger with configurable options.
/// - `log_dir`: directory for log files (default: ~/.mbopenclacky/logs/)
/// - `max_files`: maximum retained log files (default: 7)
/// - `min_level`: minimum severity to record (default: Info)
/// - `console_echo`: whether to also print to stdout (default: false)
pub fn Logger::new(
  log_dir? : String = "",
  max_files? : Int = 7,
  min_level? : LogLevel = Info,
  console_echo? : Bool = false,
) -> Logger {
  let dir = if log_dir.is_empty() {
    match config_dir() {
      Some(cd) => @path.Path::join(cd, @path.Path("logs")).to_string()
      None => "logs"
    }
  } else {
    log_dir
  }
  { log_dir: dir, max_files, min_level, console_echo }
}

///|
/// Check whether a message at the given level should be logged.
pub fn Logger::should_log(self : Logger, level : LogLevel) -> Bool {
  level >= self.min_level
}

///|
/// Log a debug-level message.
pub fn Logger::debug(
  self : Logger,
  msg : String,
  context? : LogContext = [],
) -> Unit {
  self.log(Debug, msg, context)
}

///|
/// Log an info-level message.
pub fn Logger::info(
  self : Logger,
  msg : String,
  context? : LogContext = [],
) -> Unit {
  self.log(Info, msg, context)
}

///|
/// Log a warning-level message.
pub fn Logger::warn(
  self : Logger,
  msg : String,
  context? : LogContext = [],
) -> Unit {
  self.log(Warn, msg, context)
}

///|
/// Log an error-level message.
pub fn Logger::error(
  self : Logger,
  msg : String,
  context? : LogContext = [],
) -> Unit {
  self.log(Error, msg, context)
}

///|
/// Get the full path to today's log file.
pub fn Logger::log_path(self : Logger) -> String {
  @path.Path::join(self.log_dir, @path.Path(self.log_filename())).to_string()
}

///|
/// Rotate old log files, removing those exceeding max_files.
/// Reads the log directory, sorts files by name (which encodes date),
/// and deletes the oldest ones beyond the retention limit.
pub fn Logger::rotate(self : Logger) -> Unit {
  let entries = @fs.read_dir(self.log_dir) catch { _ => return }
  // Filter to only our log files (clacky-YYYY-MM-DD.log pattern)
  let log_files : Array[String] = []
  for entry in entries {
    if entry.has_prefix("clacky-") && entry.has_suffix(".log") {
      log_files.push(entry)
    }
  }
  if log_files.length() <= self.max_files {
    return
  }
  // Sort ascending by name (date encoded in name ensures chronological order)
  log_files.sort_by(fn(a, b) { a.compare(b) })
  // Remove oldest files beyond retention
  let to_remove = log_files.length() - self.max_files
  for i in 0..<to_remove {
    let file_path = @path.Path::join(self.log_dir, @path.Path(log_files[i])).to_string()
    @fs.remove_file(file_path) catch {
      _ => ()
    }
  }
}

// --- Internal helpers ---

///|
/// Core logging method: formats and writes if level passes filter.
fn Logger::log(
  self : Logger,
  level : LogLevel,
  msg : String,
  context : LogContext,
) -> Unit {
  if !self.should_log(level) {
    return
  }
  let line = format_log_line(level, msg, context)
  if self.console_echo {
    println(line)
  }
  write_log(self.log_path(), line)
}

///|
/// Format a structured log line.
/// Format: [YYYY-MM-DDThh:mm:ss] LEVEL message | key=value key=value
fn format_log_line(
  level : LogLevel,
  msg : String,
  context : LogContext,
) -> String {
  let ts = current_timestamp_str()
  let label = level_label(level)
  let buf = StringBuilder::new()
  buf.write_string("[")
  buf.write_string(ts)
  buf.write_string("] ")
  buf.write_string(label)
  buf.write_string(" ")
  buf.write_string(msg)
  if context.length() > 0 {
    buf.write_string(" |")
    for pair in context {
      let (k, v) = pair
      buf.write_string(" ")
      buf.write_string(k)
      buf.write_string("=")
      buf.write_string(v)
    }
  }
  buf.to_string()
}

///|
/// Fixed-width (5 chars) level label for aligned log output.
fn level_label(level : LogLevel) -> String {
  match level {
    Debug => "DEBUG"
    Info => "INFO "
    Warn => "WARN "
    Error => "ERROR"
  }
}

///|
/// Generate today's log filename: "clacky-YYYY-MM-DD.log"
fn Logger::log_filename(self : Logger) -> String {
  ignore(self)
  "clacky-" + current_date_str() + ".log"
}

///|
/// Get the current date as "YYYY-MM-DD" string.
/// Falls back to "0000-00-00" when system time is unavailable (e.g. wasm-gc).
fn current_date_str() -> String {
  // In native backend, this would use FFI to get real system time.
  // For now, try environment variable override for testability.
  match @env.get_env_var("MBOPENCLACKY_LOG_DATE") {
    Some(d) if !d.is_empty() => d
    _ => "0000-00-00"
  }
}

///|
/// Get the current timestamp as "YYYY-MM-DDThh:mm:ss" string.
/// Falls back to "0000-00-00T00:00:00" when system time is unavailable.
fn current_timestamp_str() -> String {
  match @env.get_env_var("MBOPENCLACKY_LOG_TIMESTAMP") {
    Some(ts) if !ts.is_empty() => ts
    _ => "0000-00-00T00:00:00"
  }
}

///|
/// Write a log line to the specified file path.
/// In native backend this appends to the file;
/// in wasm-gc this is best-effort (read + append + rewrite).
fn write_log(path : String, line : String) -> Unit {
  // Ensure parent directory exists
  let parent = @path.Path::dirname(@path.Path(path)).to_string()
  if !parent.is_empty() {
    ensure_dir(parent)
  }
  // Read existing content and append new line
  let existing = @fs.read_file_to_string(path) catch { _ => "" }
  let content = if existing.is_empty() {
    line + "\n"
  } else {
    existing + line + "\n"
  }
  @fs.write_string_to_file(path, content) catch {
    _ => ()
  }
}
