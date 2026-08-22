///| StdioTransport: communicates with MCP server via stdin/stdout of a child process.
///  Real implementation spawns the child via `@process` pipes (same pattern as
///  lib/server/browser_process.mbt) and runs persistent read loops that
///  correlate JSON-RPC responses to pending requests by id.

///|
/// Maximum stderr buffer size in bytes.
const MAX_STDERR_BYTES : Int = 65536

// ── Native struct ───────────────────────────────────────────────────────────

///|
/// Transport that communicates with an MCP server process via stdio.
/// Each line on stdout is expected to be a complete JSON-RPC message.
#cfg(target="native")
pub(all) struct StdioTransport {
  command : String
  args : Array[String]
  env : Map[String, String]
  cwd : String?
  mut is_alive : Bool
  mut stderr_buffer : String
  mut message_handler : ((String) -> Unit)?
  mut pid : Int?
  mut stdin_writer : @process.WriteToProcess?
  mut stdout_reader : @process.ReadFromProcess?
  mut stderr_reader : @process.ReadFromProcess?
  mut read_task : @async.Task[Unit]?
  mut stderr_task : @async.Task[Unit]?
  mut pending : Map[Int, @aqueue.Queue[Result[String, String]]]
}

///|
/// Transport that communicates with an MCP server process via stdio
/// (WASM stub - process spawning not supported).
#cfg(any(target="wasm", target="wasm-gc", target="js"))
pub(all) struct StdioTransport {
  command : String
  args : Array[String]
  env : Map[String, String]
  cwd : String?
  mut is_alive : Bool
  mut stderr_buffer : String
  mut message_handler : ((String) -> Unit)?
}

// ── Constructors ────────────────────────────────────────────────────────────

///|
/// Create a new StdioTransport from an McpServerSpec.
#cfg(target="native")
pub fn StdioTransport::new(spec : McpServerSpec) -> StdioTransport {
  let command = match spec.command {
    Some(cmd) => cmd
    None => ""
  }
  let args = match spec.args {
    Some(a) => a
    None => []
  }
  let env : Map[String, String] = match spec.env {
    Some(e) => e
    None => Map([])
  }
  {
    command,
    args,
    env,
    cwd: spec.cwd,
    is_alive: false,
    stderr_buffer: "",
    message_handler: None,
    pid: None,
    stdin_writer: None,
    stdout_reader: None,
    stderr_reader: None,
    read_task: None,
    stderr_task: None,
    pending: Map([]),
  }
}

///|
/// Create a new StdioTransport from an McpServerSpec (WASM variant).
#cfg(any(target="wasm", target="wasm-gc", target="js"))
pub fn StdioTransport::new(spec : McpServerSpec) -> StdioTransport {
  let command = match spec.command {
    Some(cmd) => cmd
    None => ""
  }
  let args = match spec.args {
    Some(a) => a
    None => []
  }
  let env : Map[String, String] = match spec.env {
    Some(e) => e
    None => Map([])
  }
  {
    command,
    args,
    env,
    cwd: spec.cwd,
    is_alive: false,
    stderr_buffer: "",
    message_handler: None,
  }
}

// ── Trait wiring ────────────────────────────────────────────────────────────

///|
pub extend StdioTransport with Transport::{
  start,
  stop,
  alive,
  send_message,
  send_request,
  on_message,
  stderr_tail,
}

// ── Target-independent sync implementations ────────────────────────────────

///|
/// Check if the transport is still alive.
pub impl Transport for StdioTransport with fn alive(self) -> Bool {
  self.is_alive
}

///|
/// Register a message handler for incoming stdout lines that are not
/// responses to pending requests (notifications, server-initiated
/// requests, unmatched/late responses).
pub impl Transport for StdioTransport with fn on_message(self, handler) -> Unit {
  self.message_handler = Some(handler)
}

///|
/// Get the tail of stderr output (limited to MAX_STDERR_BYTES).
pub impl Transport for StdioTransport with fn stderr_tail(self) -> String {
  if self.stderr_buffer.length() > MAX_STDERR_BYTES {
    let start = self.stderr_buffer.length() - MAX_STDERR_BYTES
    self.stderr_buffer[start:].to_owned()
  } else {
    self.stderr_buffer
  }
}

///|
/// Append data to the stderr buffer (used internally by the stderr read loop).
pub fn StdioTransport::append_stderr(
  self : StdioTransport,
  data : String,
) -> Unit {
  self.stderr_buffer = self.stderr_buffer + data
  // Trim if exceeds max
  if self.stderr_buffer.length() > MAX_STDERR_BYTES {
    let start = self.stderr_buffer.length() - MAX_STDERR_BYTES
    self.stderr_buffer = self.stderr_buffer[start:].to_owned()
  }
}

///|
/// Simulate receiving a message (for testing/mock purposes).
pub fn StdioTransport::receive_message(
  self : StdioTransport,
  message : String,
) -> Unit {
  match self.message_handler {
    Some(handler) => handler(message)
    None => ()
  }
}

// ── Native implementation ───────────────────────────────────────────────────

///|
/// Start the child process: create pipes, spawn the command, and launch
/// the stdout/stderr read loops. Requires a registered MCP task group
/// (see set_mcp_task_group) to host the persistent read loops.
#cfg(target="native")
pub impl Transport for StdioTransport with fn start(self) -> Result[
  Unit,
  String,
] {
  if self.is_alive {
    return Ok(())
  }
  if self.command.is_empty() {
    return Err("stdio transport has no command configured")
  }
  if mcp_task_group.val is None {
    return Err(
      "MCP task group not registered - call set_mcp_task_group first (the web server does this at startup)",
    )
  }
  let (stdout_reader, child_stdout) = @process.read_from_process() catch {
    _ => return Err("Failed to create stdout pipe for: \{self.command}")
  }
  let (child_stdin, stdin_writer) = @process.write_to_process() catch {
    _ => {
      stdout_reader.close()
      return Err("Failed to create stdin pipe for: \{self.command}")
    }
  }
  let (stderr_reader, child_stderr) = @process.read_from_process() catch {
    _ => {
      stdin_writer.close()
      stdout_reader.close()
      return Err("Failed to create stderr pipe for: \{self.command}")
    }
  }
  let pid : Int = match self.cwd {
    Some(c) =>
      @process.spawn_orphan(
        self.command,
        self.args,
        stdin=child_stdin,
        stdout=child_stdout,
        stderr=child_stderr,
        extra_env=self.env,
        cwd=c,
        no_console_window=true,
      ) catch {
        _ => -1
      }
    None =>
      @process.spawn_orphan(
        self.command,
        self.args,
        stdin=child_stdin,
        stdout=child_stdout,
        stderr=child_stderr,
        extra_env=self.env,
        no_console_window=true,
      ) catch {
        _ => -1
      }
  }
  if pid < 0 {
    stdin_writer.close()
    stdout_reader.close()
    stderr_reader.close()
    return Err("Failed to spawn process: \{self.command}")
  }
  self.pid = Some(pid)
  self.stdin_writer = Some(stdin_writer)
  self.stdout_reader = Some(stdout_reader)
  self.stderr_reader = Some(stderr_reader)
  self.pending = Map([])
  self.is_alive = true
  match spawn_mcp_task(() => self.run_read_loop()) {
    Some(task) => self.read_task = Some(task)
    None => {
      self.stop()
      return Err("Failed to spawn MCP read loop (no task group)")
    }
  }
  match spawn_mcp_task(() => self.run_stderr_loop()) {
    Some(task) => self.stderr_task = Some(task)
    None => {
      self.stop()
      return Err("Failed to spawn MCP stderr loop (no task group)")
    }
  }
  Ok(())
}

///|
/// Stop the child process: fail all pending waiters, cancel the read
/// loops, close the pipes synchronously, and terminate the child in a
/// background task. Idempotent.
#cfg(target="native")
pub impl Transport for StdioTransport with fn stop(self) -> Unit {
  let was_alive = self.is_alive
  self.is_alive = false
  self.fail_all_pending("MCP transport stopped")
  match self.read_task {
    Some(task) => {
      task.cancel()
      self.read_task = None
    }
    None => ()
  }
  match self.stderr_task {
    Some(task) => {
      task.cancel()
      self.stderr_task = None
    }
    None => ()
  }
  match self.stdin_writer {
    Some(w) => {
      w.close()
      self.stdin_writer = None
    }
    None => ()
  }
  match self.stdout_reader {
    Some(r) => {
      r.close()
      self.stdout_reader = None
    }
    None => ()
  }
  match self.stderr_reader {
    Some(r) => {
      r.close()
      self.stderr_reader = None
    }
    None => ()
  }
  match (was_alive, self.pid) {
    (true, Some(pid)) => {
      self.pid = None
      // Terminate + reap the child off the hot path.
      let _ = spawn_mcp_bg(() => {
        let terminate = @process.hard_cancel()
        (terminate.0)(pid) catch {
          _ => ()
        }
        let _ = @process.wait_pid(pid) catch { _ => -1 }
      })
    }
    _ => self.pid = None
  }
}

///|
/// Send a JSON-RPC message (notification, no response expected) to the
/// child process stdin. Messages are newline-delimited.
#cfg(target="native")
pub impl Transport for StdioTransport with fn send_message(self, message) -> Result[
  Unit,
  String,
] {
  self.write_line(message)
}

///|
/// Send a JSON-RPC request and wait for the response correlated by id.
/// Wakes whoever is waiting on `id`; late responses, notifications and
/// invalid lines never complete a pending request.
#cfg(target="native")
pub impl Transport for StdioTransport with fn send_request(
  self,
  id,
  message,
  timeout_s,
) -> Result[String, String] {
  if !self.is_alive {
    return Err("MCP transport is not started")
  }
  let q : @aqueue.Queue[Result[String, String]] = Queue(kind=Unbounded)
  self.pending[id] = q
  match self.write_line(message) {
    Ok(_) => ()
    Err(e) => {
      self.pending.remove(id) |> ignore
      return Err(e)
    }
  }
  let resp : Result[String, String] = @async.with_timeout(timeout_s * 1000, () => {
    q.get()
  }) catch {
    @async.TimeoutError => {
      self.pending.remove(id) |> ignore
      return Err(
        "MCP request timed out after \{timeout_s}s (id: \{id}, command: \{self.command})",
      )
    }
    _ => {
      self.pending.remove(id) |> ignore
      return Err("MCP request wait failed (id: \{id})")
    }
  }
  self.pending.remove(id) |> ignore
  resp
}

// ── Native internals ────────────────────────────────────────────────────────

///|
/// Write one line (newline-terminated) to the child's stdin.
#cfg(target="native")
async fn StdioTransport::write_line(
  self : StdioTransport,
  line : String,
) -> Result[Unit, String] {
  if !self.is_alive {
    return Err("MCP transport is not started")
  }
  match self.stdin_writer {
    Some(w) => {
      w.write(line + "\n") catch {
        _ => {
          self.is_alive = false
          return Err("Failed to write to MCP server stdin")
        }
      }
      Ok(())
    }
    None => Err("MCP transport has no stdin pipe")
  }
}

///|
/// Persistent stdout read loop. Runs until the transport stops or the
/// child closes its stdout; on exit it fails every pending waiter.
#cfg(target="native")
async fn StdioTransport::run_read_loop(self : StdioTransport) -> Unit {
  while self.is_alive {
    let line : String? = match self.stdout_reader {
      Some(reader) => reader.read_until("\n") catch { _ => None }
      None => break
    }
    match line {
      None => break
      Some(text) => self.dispatch_line(text)
    }
  }
  if self.is_alive {
    self.is_alive = false
  }
  self.fail_all_pending("MCP server closed the connection")
}

///|
/// Persistent stderr drain loop. Keeps the child's stderr pipe from
/// filling up and records the tail for diagnostics.
#cfg(target="native")
async fn StdioTransport::run_stderr_loop(self : StdioTransport) -> Unit {
  while self.is_alive {
    let line : String? = match self.stderr_reader {
      Some(reader) => reader.read_until("\n") catch { _ => None }
      None => break
    }
    match line {
      None => break
      Some(text) => self.append_stderr(text + "\n")
    }
  }
}

///|
/// Route one stdout line: responses complete the pending request with a
/// matching id; anything else (notifications, server requests, late or
/// invalid frames) is forwarded to the message handler if registered.
#cfg(target="native")
fn StdioTransport::dispatch_line(self : StdioTransport, text : String) -> Unit {
  let trimmed = text.trim().to_owned()
  if trimmed.length() == 0 {
    return
  }
  let json : Json = @json.parse(trimmed) catch {
    // Not valid JSON (e.g. server banner/noise): skip without killing
    // the connection.
    _ => return
  }
  if !is_jsonrpc_response_line(json) {
    match self.message_handler {
      Some(handler) => handler(trimmed)
      None => ()
    }
    return
  }
  match parse_jsonrpc_response(trimmed) {
    Some(resp) =>
      match resp.id {
        Some(id) =>
          match self.pending.get(id) {
            Some(q) => {
              self.pending.remove(id) |> ignore
              ignore(q.try_put(Ok(trimmed)) catch { _ => false })
            }
            // Late response for a request that already timed out.
            None =>
              match self.message_handler {
                Some(handler) => handler(trimmed)
                None => ()
              }
          }
        None =>
          match self.message_handler {
            Some(handler) => handler(trimmed)
            None => ()
          }
      }
    None =>
      match self.message_handler {
        Some(handler) => handler(trimmed)
        None => ()
      }
  }
}

///|
/// Wake every pending waiter with an error and clear the pending table.
#cfg(target="native")
fn StdioTransport::fail_all_pending(
  self : StdioTransport,
  reason : String,
) -> Unit {
  let ids : Array[Int] = []
  self.pending.each(fn(id, _q) { ids.push(id) })
  for id in ids {
    match self.pending.get(id) {
      Some(q) => {
        ignore(q.try_put(Err(reason)) catch { _ => false })
        self.pending.remove(id) |> ignore
      }
      None => ()
    }
  }
}

// ── WASM fallback stubs ────────────────────────────────────────────────────

///|
/// Start the child process (WASM stub - not supported).
#cfg(any(target="wasm", target="wasm-gc", target="js"))
pub impl Transport for StdioTransport with fn start(self) -> Result[
  Unit,
  String,
] {
  let _ = self.command
  Err("Process spawning not supported on wasm target")
}

///|
/// Stop the child process (WASM stub - no-op).
#cfg(any(target="wasm", target="wasm-gc", target="js"))
pub impl Transport for StdioTransport with fn stop(self) -> Unit {
  self.is_alive = false
}

///|
/// Send a JSON-RPC message (WASM stub - not supported).
#cfg(any(target="wasm", target="wasm-gc", target="js"))
pub impl Transport for StdioTransport with fn send_message(self, message) -> Result[
  Unit,
  String,
] {
  let _ = message
  Err("Process I/O not supported on wasm target")
}

///|
/// Send a JSON-RPC request (WASM stub - not supported).
#cfg(any(target="wasm", target="wasm-gc", target="js"))
pub impl Transport for StdioTransport with fn send_request(
  self,
  id,
  message,
  timeout_s,
) -> Result[String, String] {
  let _ = id
  let _ = message
  let _ = timeout_s
  Err("Process I/O not supported on wasm target")
}
