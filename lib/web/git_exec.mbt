///| Native FFI for executing system commands (used by git handlers).

///|
/// FFI to C's system() for synchronous command execution.
#borrow(_cmd)
extern "C" fn git_system_ffi(_cmd : Bytes) -> Int = "git_system"

///|
/// Run a system command and return the exit code.
fn git_run_command(command : String) -> Int {
  let cmd_bytes = command.to_bytes()
  git_system_ffi(cmd_bytes)
}

///|
/// Run a command and capture its stdout (stderr merged). Returns the output string.
fn git_capture_output(command : String) -> String {
  let output_file = ".git_panel_output.tmp"
  let is_win = @sys.get_env_var("OS") is Some(v) && v == "Windows_NT"
  let cmd = if is_win {
    "cmd.exe /c \"" + command + " > \"" + output_file + "\" 2>&1\""
  } else {
    "sh -c '" + command + " > \"" + output_file + "\" 2>&1'"
  }
  let _ = git_run_command(cmd)
  @fs.read_file_to_string(output_file) catch {
    _ => ""
  }
}

///|
/// Run a git command and capture output. Returns the output string.
fn git_run(args : String) -> String {
  git_capture_output("git " + args)
}

///|
/// Check if git output indicates an error (heuristic: common error prefixes).
fn git_output_is_error(output : String) -> Bool {
  let trimmed = output.trim().to_owned()
  trimmed.has_prefix("fatal:") ||
  trimmed.has_prefix("error:") ||
  trimmed.has_prefix("ERROR:") ||
  trimmed.contains("not a git repository")
}
