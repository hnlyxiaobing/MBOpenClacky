///|
/// pty_session.mbt — High-level command execution with PTY support.
///
/// Provides the main `execute_command` function that tries PTY first,
/// falling back to system()-based execution if PTY is unavailable or fails.
/// This function is called by the Terminal tool in place of execute_command_sync.

///|
/// Execute a command using PTY if available, falling back to system().
///
/// This is the main entry point called by the Terminal tool.
/// Returns (output, exit_code, output_file_path).
fn execute_command(
  user_command : String,
  cwd : String,
  timeout_ms : Int,
  session_id : Int,
) -> (String, Int, String) {
  // Try PTY first
  match execute_command_pty(user_command, cwd, timeout_ms) {
    Ok((output, exit_code)) =>
      // PTY succeeded — return output without file path
      (output, exit_code, "")
    Err(_) =>
      // Fall back to system()-based execution
      execute_command_sync(user_command, cwd, timeout_ms, session_id)
  }
}

///|
/// Execute a command using PTY (pseudo-terminal).
///
/// Returns Ok((output, exit_code)) on success, Err(msg) if PTY
/// is unavailable or the command fails to execute.
fn execute_command_pty(
  user_command : String,
  cwd : String,
  timeout_ms : Int,
) -> Result[(String, Int), String] {
  // Check if PTY is available on this platform
  if !pty_is_available() {
    return Err("PTY not available")
  }

  // Get default shell
  let shell = pty_get_default_shell()

  // Spawn PTY
  match PtyHandle::spawn(shell, cwd) {
    Err(msg) => Err(msg)
    Ok(handle) =>
      // Initialize PTY (drain banner, setup, verify)
      match handle.init() {
        Err(msg) => {
          ignore(handle.kill())
          handle.close()
          Err(msg)
        }
        Ok(_) => {
          // Execute command with marker
          let result = handle.exec_with_marker(user_command, timeout_ms)

          // Clean up based on result state
          match result.state {
            Matched | Eof => handle.close()
            _ => {
              ignore(handle.kill())
              handle.close()
            }
          }

          // Return result
          match result.exit_code {
            Some(code) => Ok((result.output, code))
            None => Ok((result.output, 1))
          }
        }
      }
  }
}
