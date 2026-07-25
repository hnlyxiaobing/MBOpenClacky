///|
/// Smoke tests for the full Terminal command-execution chain (S-FFI-08).
///
/// execute_command tries PTY (moonbit-community/pty, ConPTY on Windows)
/// first and falls back to @process-based execution when PTY is
/// unavailable — both paths must produce exit code 0 with the output.

///|
async test "terminal execute: simple echo succeeds (pty or fallback)" {
  let term = Terminal::new()
  let args : Map[String, Json] = {
    "command": "echo clacky_pty_smoke".to_json(),
  }
  let result = term.execute(args)
  assert_false(result.is_error)
  assert_true(result.content.contains("clacky_pty_smoke"))
  assert_true(result.content.contains("exit_code: 0"))
}

///|
async test "terminal execute: non-zero exit code propagates" {
  let term = Terminal::new()
  // (exit 3) works in cmd.exe (.bat fallback), sh, and PTY bash alike.
  let args : Map[String, Json] = { "command": "(exit 3)".to_json() }
  let result = term.execute(args)
  assert_false(result.is_error)
  assert_true(result.content.contains("exit_code: 3"))
}
