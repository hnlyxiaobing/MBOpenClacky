///|
/// Shared shell execution for hooks, patches, and extension handlers.
/// Spawns the platform shell via @process.run (see terminal_exec.mbt;
/// the C system() FFI was removed in S-FFI-08) and uses the
/// output-file + completion-marker pattern from lib/tool/terminal.mbt.
///
/// Concurrency safety: env vars are INLINED into the command prefix
/// (export VAR='val' on Unix, set "VAR=val" on Windows) rather than
/// modifying the parent process environment. This is safe for concurrent
/// web server requests.

///|
priv struct ShellExecCounter {
  mut value : Int
}

///|
let shell_exec_counter : ShellExecCounter = { value: 0 }

///|
pub(all) struct ShellExecResult {
  output : String
  exit_code : Int
} derive(Debug)

///|
pub extend ShellExecResult with @moonbitlang/core/debug.Debug::{to_repr}

///|
fn shell_temp_dir() -> String {
  match @env.get_env_var("TEMP") {
    Some(d) => d
    None =>
      match @env.get_env_var("TMPDIR") {
        Some(d) => d
        None => "/tmp"
      }
  }
}

///|
/// Detect whether the current process runs on Windows (cmd.exe semantics).
/// Public so that cross-package tests can write platform-aware commands.
pub fn shell_is_windows() -> Bool {
  @env.get_env_var("OS") is Some(v) && v == "Windows_NT"
}

///|
/// The temp directory used for shell output files (TEMP / TMPDIR / /tmp).
/// Public so that tests can construct platform-appropriate temp paths.
pub fn shell_temp_dir_pub() -> String {
  shell_temp_dir()
}

///|
/// Escape a value for single-quoted context on Unix (sh).
/// Replaces ' with '\'' — the standard idiom for embedding single quotes.
fn shell_escape_single(value : String) -> String {
  let buf : Array[String] = []
  for c in value {
    if c == '\'' {
      buf.push("'\\''")
    } else {
      buf.push(c.to_string())
    }
  }
  buf.join("")
}

///|
/// Build the env-var prefix for the command.
/// Unix:  export VAR='val' && export VAR2='val2' &&
/// Win:   set "VAR=val" && set "VAR2=val2" &&
fn build_env_prefix(
  env_vars : Array[(String, String)],
  is_win : Bool,
) -> String {
  if env_vars.length() == 0 {
    return ""
  }
  let parts : Array[String] = []
  for kv in env_vars {
    let key = kv.0
    let val = kv.1
    if is_win {
      parts.push("set \"\{key}=\{val}\"")
    } else {
      parts.push("export \{key}='\{shell_escape_single(val)}'")
    }
  }
  parts.join(" && ") + " && "
}

///|
/// Execute a shell command, capturing combined stdout/stderr and the real
/// exit code via a completion marker. Environment variables are inlined
/// into the command prefix (concurrency-safe — no parent env mutation).
pub async fn run_shell_command(
  command : String,
  env_vars? : Array[(String, String)] = [],
  working_dir? : String? = None,
) -> ShellExecResult {
  shell_exec_counter.value = shell_exec_counter.value + 1
  let token = "cmdhook\{shell_exec_counter.value}"
  let output_file = @path.Path::join(
    shell_temp_dir(),
    @path.Path("clacky_cmd_\{token}.out"),
  ).to_string()
  let is_win = shell_is_windows()
  let cwd = match working_dir {
    Some(d) if !d.is_empty() && d != "." => Some(d)
    _ => None
  }
  let env_prefix = build_env_prefix(env_vars, is_win)
  let shell_cmd = if is_win {
    let cd_part = match cwd {
      Some(d) => "cd /d \"" + d + "\" && "
      None => ""
    }
    cd_part +
    env_prefix +
    "(" +
    command +
    ") > \"" +
    output_file +
    "\" 2>&1 & " +
    "echo __CLACKY_DONE_" +
    token +
    // Delayed expansion (!ERRORLEVEL!): %ERRORLEVEL% would be expanded by
    // cmd.exe when the whole /c line is parsed — BEFORE the command runs —
    // so it would always capture the wrong (previous) exit code. Requires
    // the /v:on flag on the cmd.exe wrapper below.
    "_!ERRORLEVEL!__ >> \"" +
    output_file +
    "\""
  } else {
    let cd_part = match cwd {
      Some(d) => "cd '" + d + "' && "
      None => ""
    }
    cd_part +
    env_prefix +
    "( " +
    command +
    " ) > '" +
    output_file +
    "' 2>&1; " +
    "echo '__CLACKY_DONE_" +
    token +
    "_'$?'__' >> '" +
    output_file +
    "'"
  }
  // Spawn the platform shell directly via @process.run (no C system()).
  // On Windows the command runs from a temp .bat under cmd.exe /v:on so
  // that !ERRORLEVEL! above is expanded AFTER the command completes
  // (see terminal_exec.mbt for why a batch file is needed).
  let sys_exit = run_system_command(shell_cmd, Map([]))
  let raw = @fs.read_file_to_string(output_file) catch { _ => "" }
  @fs.remove_file(output_file) catch {
    _ => ()
  }
  let exit_code = match parse_shell_marker(raw, token) {
    Some(code) => code
    // @process.run returns the child's real exit code on both platforms.
    None => sys_exit
  }
  { output: strip_shell_marker(raw, token), exit_code }
}

///|
fn parse_shell_marker(output : String, token : String) -> Int? {
  let prefix = "__CLACKY_DONE_\{token}_"
  match output.find(prefix) {
    Some(pos) => {
      let rest = output[pos + prefix.length():].to_owned()
      match rest.find("__") {
        Some(end) => {
          let code_str = rest[:end].to_owned()
          Some(@string.parse_int(code_str)) catch {
            _ => None
          }
        }
        None => None
      }
    }
    None => None
  }
}

///|
fn strip_shell_marker(output : String, token : String) -> String {
  let marker_prefix = "__CLACKY_DONE_\{token}_"
  let result : Array[String] = []
  for line in output.split("\n") {
    let trimmed = line.trim().to_owned()
    if trimmed.has_prefix(marker_prefix) && trimmed.has_suffix("__") {
      continue
    }
    result.push(line.to_owned())
  }
  result.join("\n")
}
