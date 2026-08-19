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

///|
/// P6: timeout actually bounds execution (Ruby semantics: seconds).
/// A long-running sleep must be cut short and report a timeout marker
/// instead of blocking the loop forever.
async test "terminal execute: timeout bounds long commands" {
  let term = Terminal::new()
  let args : Map[String, Json] = {
    "command": "sleep 30".to_json(),
    "timeout": (1).to_json(),
  }
  let start = @env.now().reinterpret_as_int64()
  let result = term.execute(args)
  let elapsed_ms = @env.now().reinterpret_as_int64() - start
  assert_false(result.is_error)
  // Bounded: well under the 30s sleep, with margin for process teardown.
  assert_true(elapsed_ms < 20000)
  assert_true(
    result.content.contains("timed out after 1s"),
    msg="expected timeout marker, got: \{result.content}",
  )
}

///|
/// P6: background sessions run truly async — spawn returns immediately
/// with a session id and poll collects output incrementally.
async test "terminal execute: background session lifecycle" {
  let term = Terminal::new()
  let args : Map[String, Json] = {
    "command": "echo bg_hello && sleep 1 && echo bg_done".to_json(),
    "background": true.to_json(),
  }
  let result = term.execute(args)
  assert_false(result.is_error)
  assert_true(
    result.content.contains("Background session #"),
    msg="got: \{result.content}",
  )

  // Extract the session id from the hint: "session #N"
  let sid = match extract_session_id(result.content) {
    Some(id) => id
    None => {
      assert_true(false, msg="no session id in background hint")
      return
    }
  }

  // Poll until the marker appears (bounded loop).
  let mut saw_done = false
  for i in 0..<20 {
    let poll_args : Map[String, Json] = {
      "session_id": sid.to_json(),
      "input": "".to_json(),
    }
    let poll = term.execute(poll_args)
    if poll.content.contains("bg_done") || poll.content.contains("exited") {
      saw_done = poll.content.contains("bg_done")
      break
    }
    @async.sleep(200)
    if i == 19 {
      assert_true(
        false,
        msg="background session never completed: \{poll.content}",
      )
      return
    }
  }
  assert_true(saw_done, msg="background output missing")
  // Cleanup: ensure the session is not left tracked.
  let _ = TerminalSessionManager::forget(sid)
}

///|
/// P6: kill sends a real termination signal to the background process.
async test "terminal execute: kill terminates background session" {
  let term = Terminal::new()
  let args : Map[String, Json] = {
    "command": "sleep 60".to_json(),
    "background": true.to_json(),
  }
  let result = term.execute(args)
  assert_false(result.is_error)
  let sid = match extract_session_id(result.content) {
    Some(id) => id
    None => {
      assert_true(false, msg="no session id in background hint")
      return
    }
  }

  // Give the process a moment to spawn.
  @async.sleep(200)

  let kill_args : Map[String, Json] = {
    "session_id": sid.to_json(),
    "kill": true.to_json(),
  }
  let kill = term.execute(kill_args)
  assert_false(kill.is_error)
  assert_true(kill.content.contains("killed"), msg="got: \{kill.content}")

  // The session must now report as killed/exited on poll.
  let poll_args : Map[String, Json] = {
    "session_id": sid.to_json(),
    "input": "".to_json(),
  }
  let poll = term.execute(poll_args)
  assert_true(
    poll.is_error &&
    (poll.content.contains("killed") || poll.content.contains("exited")),
    msg="expected killed/exited after kill, got: \{poll.content}",
  )
  let _ = TerminalSessionManager::forget(sid)
}

///|
/// Extract "session #N" from a background hint.
fn extract_session_id(content : String) -> Int? {
  let marker = "session #"
  match content.find(marker) {
    Some(idx) => {
      let rest = content[idx + marker.length():].to_owned()
      let mut digits = ""
      for ch in rest {
        if ch >= '0' && ch <= '9' {
          digits = digits + ch.to_string()
        } else {
          break
        }
      }
      if digits.is_empty() {
        None
      } else {
        Some(@string.parse_int(digits) catch { _ => 0 })
      }
    }
    None => None
  }
}
