///|
/// Wraps a chrome-devtools-mcp child process with stdin/stdout pipes.
/// Uses `@async/process` for process management; falls back to stubs on wasm targets.

// ── BrowserProcess struct ───────────────────────────────────────────────────

///|
/// Wraps a chrome-devtools-mcp child process with stdin/stdout pipes.
/// Provides line-based I/O for JSON-RPC communication.
#cfg(target="native")
pub struct BrowserProcess {
  pid : Int
  priv mut alive : Bool
  priv stdin_writer : @process.WriteToProcess
  priv stdout_reader : @process.ReadFromProcess
}

///|
/// Wraps a chrome-devtools-mcp child process (WASM stub — not supported).
#cfg(any(target="wasm", target="wasm-gc", target="js"))
pub struct BrowserProcess {
  pid : Int
  priv mut alive : Bool
}

// ── Native implementation ───────────────────────────────────────────────────

///|
/// Spawn the MCP daemon process with the given command and arguments.
///
/// The child process is spawned as an orphan (`@process.spawn_orphan`), so it
/// is not tied to any task group and can outlive the spawning request. Its
/// stdin/stdout are redirected to pipes owned by this `BrowserProcess`.
#cfg(target="native")
pub async fn BrowserProcess::spawn(
  command : String,
  args : Array[String],
) -> Result[BrowserProcess, String] {
  let (stdout_reader, child_stdout) = @process.read_from_process() catch {
    _ => return Err("Failed to create stdout pipe for: \{command}")
  }
  let (child_stdin, stdin_writer) = @process.write_to_process() catch {
    _ => {
      stdout_reader.close()
      return Err("Failed to create stdin pipe for: \{command}")
    }
  }
  let pid = @process.spawn_orphan(
    command,
    args,
    stdin=child_stdin,
    stdout=child_stdout,
    no_console_window=true,
  ) catch {
    _ => {
      stdin_writer.close()
      stdout_reader.close()
      return Err("Failed to spawn process: \{command}")
    }
  }
  Ok({ pid, alive: true, stdin_writer, stdout_reader })
}

///|
/// Write a line to the process stdin (appends newline).
#cfg(target="native")
pub async fn BrowserProcess::write_line(
  self : BrowserProcess,
  line : String,
) -> Result[Unit, String] {
  if !self.alive {
    return Err("Process is not alive")
  }
  self.stdin_writer.write(line + "\n") catch {
    _ => {
      self.alive = false
      return Err("Failed to write to process stdin")
    }
  }
  Ok(())
}

///|
/// Read a line from the process stdout (blocking).
#cfg(target="native")
pub async fn BrowserProcess::read_line(
  self : BrowserProcess,
) -> Result[String, String] {
  if !self.alive {
    return Err("Process is not alive")
  }
  let line : String? = self.stdout_reader.read_until("\n") catch {
    _ => {
      self.alive = false
      return Err("Failed to read from process stdout")
    }
  }
  match line {
    Some(text) => Ok(text)
    None => {
      self.alive = false
      Err("Process stdout closed")
    }
  }
}

///|
/// Check if the process is still alive.
///
/// Probes with a bounded `wait_pid`: if the child already exited, its exit
/// code comes back immediately (and the child is reaped); if it is still
/// running, the probe times out and is cancelled without affecting the child.
#cfg(target="native")
pub async fn BrowserProcess::is_alive(self : BrowserProcess) -> Bool {
  if !self.alive {
    return false
  }
  let exited : Int? = Some(
    @async.with_timeout(10, () => @process.wait_pid(self.pid)),
  ) catch {
    @async.TimeoutError => None
    _ => Some(-1)
  }
  match exited {
    Some(_) => {
      self.alive = false
      false
    }
    None => true
  }
}

///|
/// Kill the process and release resources.
#cfg(target="native")
pub async fn BrowserProcess::kill(
  self : BrowserProcess,
) -> Result[Unit, String] {
  if !self.alive {
    return Ok(())
  }
  self.alive = false
  // Forceful termination, matching the old TerminateProcess/kill semantics.
  let terminate = @process.hard_cancel()
  (terminate.0)(self.pid) catch {
    _ => ()
  }
  // Reap the child so it does not linger as a zombie.
  let _ = @process.wait_pid(self.pid) catch { _ => -1 }
  self.stdin_writer.close()
  self.stdout_reader.close()
  Ok(())
}

// ── WASM fallback stubs ────────────────────────────────────────────────────

///|
/// Spawn the MCP daemon process (WASM stub — not supported).
#cfg(any(target="wasm", target="wasm-gc", target="js"))
pub async fn BrowserProcess::spawn(
  command : String,
  args : Array[String],
) -> Result[BrowserProcess, String] {
  let _ = command
  let _ = args
  Err("Process spawning not supported on wasm target")
}

///|
/// Write a line to process stdin (WASM stub — not supported).
#cfg(any(target="wasm", target="wasm-gc", target="js"))
pub async fn BrowserProcess::write_line(
  self : BrowserProcess,
  line : String,
) -> Result[Unit, String] {
  let _ = line
  Err("Process I/O not supported on wasm target")
}

///|
/// Read a line from process stdout (WASM stub — not supported).
#cfg(any(target="wasm", target="wasm-gc", target="js"))
pub async fn BrowserProcess::read_line(
  self : BrowserProcess,
) -> Result[String, String] {
  Err("Process I/O not supported on wasm target")
}

///|
/// Check if process is alive (WASM stub — always false).
#cfg(any(target="wasm", target="wasm-gc", target="js"))
pub async fn BrowserProcess::is_alive(self : BrowserProcess) -> Bool {
  false
}

///|
/// Kill the process (WASM stub — no-op).
#cfg(any(target="wasm", target="wasm-gc", target="js"))
pub async fn BrowserProcess::kill(
  self : BrowserProcess,
) -> Result[Unit, String] {
  self.alive = false
  Ok(())
}
