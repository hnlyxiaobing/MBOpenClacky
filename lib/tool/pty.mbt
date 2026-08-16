///|
/// pty.mbt — PTY abstraction layer.
///
/// Provides a high-level interface to the pseudo-terminal,
/// including spawn, init, exec with marker, read, write, close, kill.
/// Uses the marker strategy for command completion detection.
///
/// S-FFI-08 (specs/completed/2026-07-25_ffi-08-residual-ffi-pty.md):
/// the local forkpty-based C stubs (pty_stubs.c, POSIX-only, Windows
/// unsupported) were replaced by moonbit-community/pty, which adds
/// Windows ConPTY support and async event-loop integration. This file
/// keeps the marker-based session logic; all process/TTY plumbing is
/// now maintained upstream.

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
/// Internal handle wrapping a community-pty `Pty` and the session cwd.
priv struct PtyHandle {
  pty : @pty.Pty
  cwd : String
}

///|
/// Result state of a read-until-marker operation.
pub(all) enum PtyReadState {
  Matched // marker found, command completed
  Idle // idle threshold exceeded, likely waiting for input
  Timeout // overall timeout exceeded
  Eof // child process exited (EOF on PTY)
} derive(Eq, Debug)

///|
pub extend PtyReadState with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend PtyReadState with Eq::{not_equal, equal}

///|
/// Result of executing a command in the PTY.
pub(all) struct PtyExecResult {
  output : String
  exit_code : Int?
  duration_ms : Int
  state : PtyReadState
} derive(Debug)

///|
pub extend PtyExecResult with @moonbitlang/core/debug.Debug::{to_repr}

// ---- Helpers ----

///|
/// Wall-clock milliseconds (used only for duration/timeout measurement).
fn pty_now_ms() -> Int {
  @env.now().reinterpret_as_int64().to_int()
}

///|
/// Get the default shell to run inside the PTY.
///
/// On Windows the community PTY spawns via CreateProcess, which cannot
/// resolve MSYS paths like /usr/bin/bash — use "bash.exe" (resolved via
/// PATH, e.g. Git for Windows). If no bash is on PATH, spawn fails and
/// the caller falls back to @process-based execution.
fn pty_get_default_shell() -> String {
  if is_windows_platform() {
    "bash.exe"
  } else {
    match @env.get_env_var("SHELL") {
      Some(shell) => shell
      None => "/bin/bash"
    }
  }
}

// ---- PtyHandle methods ----

///|
/// Spawn a new PTY running the given shell.
///
/// The community PTY 0.4.x API takes a `StringView` file path and an
/// `ArrayView[StringView]` argument list, plus an optional `cwd`. The
/// working directory is applied directly at spawn time; `init` no longer
/// needs to send a `cd` line, but does so anyway as a no-op fallback.
async fn[X] PtyHandle::spawn(
  group : @async.TaskGroup[X],
  shell : String,
  cwd : String,
) -> Result[PtyHandle, String] {
  // bash: --noediting disables readline line editing, whose bracketed-paste
  // / cursor-addressing escape sequences would otherwise interleave with
  // command output and break line-based marker/output parsing (observed
  // with WSL bash on ConPTY). --noprofile/--norc skip noisy startup files.
  // Other shells (sh/dash) get no flags — they have no readline anyway.
  let argv : Array[StringView] = if shell.contains("bash") {
    [shell[:], "--noprofile"[:], "--norc"[:], "--noediting"[:], "-s"[:]]
  } else {
    [shell[:]]
  }
  let pty = @pty.spawn(group, shell[:], argv[:], cwd=cwd[:]) catch {
    err => return Err("failed to spawn PTY: \{err}")
  }
  Ok(PtyHandle::{ pty, cwd })
}

///|
/// Read raw bytes from the PTY with timeout.
/// Returns (data, n): n > 0 bytes read; n == 0 timeout; n < 0 EOF/error.
async fn PtyHandle::read_raw(
  self : PtyHandle,
  timeout_ms : Int,
) -> (String, Int) {
  let buf : FixedArray[Byte] = FixedArray::make(pty_read_buffer_size, 0)
  // Map read errors (e.g. EIO on Linux after the child exits) to Some(-1)
  // so EOF surfaces promptly instead of burning the idle threshold.
  let result = @async.with_timeout_opt(timeout_ms, () => self.pty.read(buf)) catch {
    _ => Some(-1)
  }
  match result {
    Some(n) =>
      if n > 0 {
        (@utf8.decode_lossy(Bytes::from_array(buf[:n].iter().collect())), n)
      } else {
        // n <= 0: EOF on the master fd or read error
        ("", -1)
      }
    // None: poll timeout, no data available
    None => ("", 0)
  }
}

///|
/// Write raw data to the PTY. Returns bytes written or -1 on error.
async fn PtyHandle::write_raw(self : PtyHandle, data : String) -> Int {
  let bytes = @utf8.encode(data[:])
  self.pty.write(bytes) catch {
    _ => return -1
  }
  bytes.length()
}

///|
/// Close the PTY, releasing OS resources. Also cancels the child if it
/// is still running (upstream Pty::drop cancels before closing).
async fn PtyHandle::close(self : PtyHandle) -> Unit {
  let _ = self.pty.drop(0)
}

///|
/// Kill the child process (request cancellation via the async runtime).
async fn PtyHandle::kill(self : PtyHandle) -> Int {
  let _ = self.pty.drop(1)
  0
}

///|
/// Initialize the PTY: apply cwd, drain banner, send setup, verify with
/// a test marker.
async fn PtyHandle::init(self : PtyHandle) -> Result[Unit, String] {
  // Apply the working directory (the spawn API has no cwd parameter).
  // On Windows, bash.exe needs forward slashes.
  let cwd = if is_windows_platform() {
    self.cwd.replace_all(old="\\", new="/")
  } else {
    self.cwd
  }
  let _ = self.write_raw("cd '" + shell_escape_single(cwd) + "'\n")

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
async fn PtyHandle::exec_with_marker(
  self : PtyHandle,
  command : String,
  timeout_ms : Int,
) -> PtyExecResult {
  let start_time = pty_now_ms()
  let token = pty_generate_token()
  let _ = self.write_raw(pty_build_command_wrapper(command, token))

  let (output, exit_code, state) = self.read_until_marker(token, timeout_ms)

  let end_time = pty_now_ms()
  PtyExecResult::{
    output,
    exit_code,
    duration_ms: end_time - start_time,
    state,
  }
}

///|
/// Poll the PTY for output until the marker is found or timeout/idle.
async fn PtyHandle::read_until_marker(
  self : PtyHandle,
  token : String,
  timeout_ms : Int,
) -> (String, Int?, PtyReadState) {
  let start_time = pty_now_ms()
  let mut accumulated = ""
  let mut last_output_time = start_time
  let mut result_output = ""
  let mut result_exit_code : Int? = None
  let mut result_state : PtyReadState = Timeout
  let mut done = false

  while !done {
    let now = pty_now_ms()

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
        last_output_time = pty_now_ms()

        // Check for the marker. Detection is parse-based, not
        // prefix-based: an echoed wrapper line contains the marker
        // prefix with a `%s` placeholder instead of digits, and must
        // not count as completion.
        match pty_parse_exit_code(accumulated, token) {
          Some(exit_code) => {
            let cleaned = pty_clean_output(accumulated, token)
            result_output = cleaned
            result_exit_code = Some(exit_code)
            result_state = Matched
            done = true
          }
          None => ()
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

// ---- Output cleaning ----

///|
/// Clean PTY output: truncate at marker, remove wrapper echo, ANSI codes,
/// control chars.
fn pty_clean_output(output : String, token : String) -> String {
  // 1. Truncate at the real marker (cursor addressing can merge the
  //    marker into the output's last line — see pty_truncate_at_marker)
  let truncated = pty_truncate_at_marker(output, token)
  // 2. Remove echoed wrapper lines
  let without_echo = pty_strip_wrapper_echo(truncated)
  // 3. Strip ANSI codes
  let without_ansi = clean_ansi_output(without_echo)
  // 4. Strip control characters
  strip_control_chars(without_ansi)
}
