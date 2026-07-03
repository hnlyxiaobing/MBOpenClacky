///|
/// pty.mbt — PTY abstraction layer.
///
/// Provides a high-level interface to the pseudo-terminal,
/// including spawn, init, exec with marker, read, write, close, kill, resize.
/// Uses the marker strategy for command completion detection.

// ---- Constants ----

///|
/// Idle threshold: if no output for this many ms, assume waiting for input.
let pty_idle_threshold_ms : Int = 10_000

///|
/// Poll interval: check for output every this many ms.
let pty_poll_interval_ms : Int = 100

///|
/// Read buffer size per read call.
let pty_read_buffer_size : Int = 4096

///|
/// Initial banner drain time in ms.
let pty_init_drain_ms : Int = 500

///|
/// Timeout for init test marker in ms.
let pty_test_timeout_ms : Int = 2000

// ---- Types ----

///|
/// Internal handle wrapping a PTY master fd and child PID.
priv struct PtyHandle {
  fd : Int
  pid : Int
} derive(Debug)

///|
/// Result state of a read-until-marker operation.
pub(all) enum PtyReadState {
  Matched // marker found, command completed
  Idle // idle threshold exceeded, likely waiting for input
  Timeout // overall timeout exceeded
  Eof // child process exited (EOF on PTY)
} derive(Eq, Debug)

///|
/// Result of executing a command in the PTY.
pub(all) struct PtyExecResult {
  output : String
  exit_code : Int?
  duration_ms : Int
  state : PtyReadState
} derive(Debug)

// ---- PtyHandle methods ----

///|
/// Spawn a new PTY with the given shell and working directory.
fn PtyHandle::spawn(shell : String, cwd : String) -> Result[PtyHandle, String] {
  match pty_ffi_spawn(shell, cwd, 80, 24) {
    Err(msg) => Err(msg)
    Ok((fd, pid)) => Ok(PtyHandle::{ fd, pid })
  }
}

///|
/// Read raw bytes from the PTY with timeout.
fn PtyHandle::read_raw(self : PtyHandle, timeout_ms : Int) -> (String, Int) {
  pty_ffi_read(self.fd, pty_read_buffer_size, timeout_ms)
}

///|
/// Write raw data to the PTY.
fn PtyHandle::write_raw(self : PtyHandle, data : String) -> Int {
  pty_ffi_write(self.fd, data)
}

///|
/// Close the PTY master fd.
fn PtyHandle::close(self : PtyHandle) -> Unit {
  pty_ffi_close(self.fd)
}

///|
/// Wait for the child process to exit.
fn PtyHandle::wait(self : PtyHandle, nohang : Bool) -> Int {
  pty_ffi_wait(self.pid, nohang)
}

///|
/// Kill the child process.
fn PtyHandle::kill(self : PtyHandle) -> Int {
  pty_ffi_kill(self.pid)
}

///|
/// Resize the PTY window.
fn PtyHandle::resize(self : PtyHandle, cols : Int, rows : Int) -> Int {
  pty_ffi_resize(self.fd, cols, rows)
}

///|
/// Initialize the PTY: drain banner, send setup, verify with test marker.
fn PtyHandle::init(self : PtyHandle) -> Result[Unit, String] {
  // Drain initial banner (shell startup output)
  let _ = self.read_raw(pty_init_drain_ms)

  // Send setup line to suppress echo, prompt, history
  let _ = self.write_raw(pty_build_setup_line())

  // Drain any response to setup
  let _ = self.read_raw(pty_init_drain_ms)

  // Verify the PTY is working by sending a test marker
  let test_token = pty_generate_token()
  let _ = self.write_raw(pty_build_command_wrapper("true", test_token))

  // Wait for the test marker
  let (_, _, state) = self.read_until_marker(test_token, pty_test_timeout_ms)
  match state {
    Matched => Ok(())
    _ => Err("PTY init failed: no response to test marker")
  }
}

///|
/// Execute a command and wait for the marker.
fn PtyHandle::exec_with_marker(
  self : PtyHandle,
  command : String,
  timeout_ms : Int,
) -> PtyExecResult {
  let start_time = pty_ffi_time_ms()
  let token = pty_generate_token()
  let _ = self.write_raw(pty_build_command_wrapper(command, token))

  let (output, exit_code, state) = self.read_until_marker(token, timeout_ms)

  let end_time = pty_ffi_time_ms()
  PtyExecResult::{
    output,
    exit_code,
    duration_ms: end_time - start_time,
    state,
  }
}

///|
/// Poll the PTY for output until the marker is found or timeout/idle.
fn PtyHandle::read_until_marker(
  self : PtyHandle,
  token : String,
  timeout_ms : Int,
) -> (String, Int?, PtyReadState) {
  let start_time = pty_ffi_time_ms()
  let mut accumulated = ""
  let mut last_output_time = start_time
  let mut result_output = ""
  let mut result_exit_code : Int? = None
  let mut result_state : PtyReadState = Timeout
  let mut done = false

  while !done {
    let now = pty_ffi_time_ms()

    // Check overall timeout
    if now - start_time >= timeout_ms {
      result_output = accumulated
      result_state = Timeout
      done = true
    } else if now - last_output_time >= pty_idle_threshold_ms {
      // Check idle threshold
      result_output = accumulated
      result_state = Idle
      done = true
    } else {
      // Read with short timeout
      let (data, n) = self.read_raw(pty_poll_interval_ms)

      if n > 0 {
        accumulated = accumulated + data
        last_output_time = pty_ffi_time_ms()

        // Check for marker
        let marker_prefix = "__CLACKY_DONE_" + token + "_"
        if accumulated.contains(marker_prefix) {
          let exit_code = pty_parse_exit_code(accumulated, token)
          let cleaned = pty_clean_output(accumulated, token)
          result_output = cleaned
          result_exit_code = exit_code
          result_state = Matched
          done = true
        }
      } else if n < 0 {
        // EOF or error — child likely exited
        let exit_code = pty_parse_exit_code(accumulated, token)
        match exit_code {
          Some(_) => {
            let cleaned = pty_clean_output(accumulated, token)
            result_output = cleaned
            result_exit_code = exit_code
            result_state = Matched
          }
          None => {
            result_output = accumulated
            result_state = Eof
          }
        }
        done = true
      }
      // n == 0: timeout, continue polling
    }
  }

  (result_output, result_exit_code, result_state)
}

// ---- Helper functions ----

///|
/// Clean PTY output: remove marker, wrapper echo, ANSI codes, control chars.
fn pty_clean_output(output : String, token : String) -> String {
  // 1. Remove marker line
  let without_marker = pty_remove_marker(output, token)
  // 2. Remove echoed wrapper lines
  let without_echo = pty_strip_wrapper_echo(without_marker)
  // 3. Strip ANSI codes
  let without_ansi = clean_ansi_output(without_echo)
  // 4. Strip control characters
  strip_control_chars(without_ansi)
}

///|
/// Get the default shell path from $SHELL environment variable.
fn pty_get_default_shell() -> String {
  match @sys.get_env_var("SHELL") {
    Some(shell) => shell
    None => "/bin/bash"
  }
}
