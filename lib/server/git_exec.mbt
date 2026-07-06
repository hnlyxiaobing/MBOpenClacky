///| Git command execution via popen FFI.
///  Provides native shell command output capture for git panel handlers.

// ── Native FFI declaration ──────────────────────────────────────────────────

///|
/// Execute a shell command and capture its stdout output.
/// Returns the captured output as a string (empty on error).
#cfg(target="native")
#borrow(command)
extern "C" fn git_exec_ffi(command : String) -> String = "mbopenclacky_git_exec"

// ── Public API ─────────────────────────────────────────────────────────────

///|
/// Run a git command and return its stdout output.
/// Returns empty string on failure.
#cfg(target="native")
pub fn run_git_command(command : String) -> String {
  git_exec_ffi(command)
}

///|
/// Run a git command and return its stdout output (WASM fallback).
#cfg(any(target="wasm", target="wasm-gc", target="js"))
pub fn run_git_command(command : String) -> String {
  ignore(command)
  ""
}
