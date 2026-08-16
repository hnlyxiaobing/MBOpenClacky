///| StdioTransport: communicates with MCP server via stdin/stdout of a child process.

///|
/// Maximum stderr buffer size in bytes.
const MAX_STDERR_BYTES : Int = 65536

///|
/// Transport that communicates with an MCP server process via stdio.
/// Each line on stdout is expected to be a complete JSON-RPC message.
pub(all) struct StdioTransport {
  command : String
  args : Array[String]
  env : Map[String, String]
  cwd : String?
  mut is_alive : Bool
  mut stderr_buffer : String
  mut message_handler : ((String) -> Unit)?
}

///|
/// Create a new StdioTransport from an McpServerSpec.
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

///|
pub extend StdioTransport with Transport::{
  start,
  stop,
  alive,
  send_message,
  on_message,
  stderr_tail,
}

///|
/// Start the child process.
/// TODO: FFI implementation needed - requires native process spawn capability.
pub impl Transport for StdioTransport with fn start(self) {
  // Placeholder: In production, this would spawn the child process
  // using the command, args, env, and cwd fields.
  self.is_alive = true
}

///|
/// Stop the child process.
pub impl Transport for StdioTransport with fn stop(self) {
  // Placeholder: In production, this would send SIGTERM to the child process,
  // close stdin/stdout/stderr pipes, and wait for exit.
  self.is_alive = false
}

///|
/// Check if the transport is still alive.
pub impl Transport for StdioTransport with fn alive(self) -> Bool {
  self.is_alive
}

///|
/// Send a JSON-RPC message to the child process stdin.
/// Messages are newline-delimited (JSON Lines protocol).
pub impl Transport for StdioTransport with fn send_message(self, message) {
  // Placeholder: In production, this would write `message + "\n"` to
  // the child process stdin pipe.
  if !self.is_alive {
    // Cannot raise here since trait method doesn't declare error type.
    // In production, this would be handled by the actual FFI layer.
    ignore(message)
    return
  }
  ignore(message)
}

///|
/// Register a message handler for incoming stdout lines.
pub impl Transport for StdioTransport with fn on_message(self, handler) {
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
/// Append data to the stderr buffer (used internally by the read loop).
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
