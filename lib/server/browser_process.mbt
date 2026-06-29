///|
/// Wraps a chrome-devtools-mcp child process with stdin/stdout pipes.
/// Uses native FFI for process management; falls back to stubs on wasm targets.

// ── Native FFI declarations ──────────────────────────────────────────────────

///|
/// Spawn a child process, returns handle index (>= 0) or -1 on error.
#cfg(target="native")
#borrow(command, args)
extern "C" fn spawn_browser_process_ffi(
  command : String,
  args : Array[String],
  arg_count : Int,
) -> Int = "mbopenclacky_spawn_process"

///|
/// Check if a process handle is still alive.
#cfg(target="native")
extern "C" fn is_process_alive_ffi(handle : Int) -> Bool = "mbopenclacky_is_process_alive"

///|
/// Terminate a process by handle. Returns 0 on success, -1 on error.
#cfg(target="native")
extern "C" fn terminate_process_ffi(handle : Int) -> Int = "mbopenclacky_terminate_process"

///|
/// Write bytes to process stdin. Returns 0 on success, -1 on error.
#cfg(target="native")
#borrow(data)
extern "C" fn write_process_stdin_ffi(
  handle : Int,
  data : Bytes,
  length : Int,
) -> Int = "mbopenclacky_write_process_stdin"

///|
/// Read a line from process stdout into buffer.
/// Returns number of bytes read (excluding newline), or -1 on error.
#cfg(target="native")
#borrow(buffer)
extern "C" fn read_process_stdout_line_ffi(
  handle : Int,
  buffer : Bytes,
  buffer_size : Int,
) -> Int = "mbopenclacky_read_process_stdout_line"

///|
/// Get the PID of a spawned process by handle.
#cfg(target="native")
extern "C" fn get_process_pid_ffi(handle : Int) -> Int = "mbopenclacky_get_process_pid"

///|
/// Close a process handle and release resources.
#cfg(target="native")
extern "C" fn close_process_handle_ffi(handle : Int) -> Int = "mbopenclacky_close_process_handle"

// ── BrowserProcess struct ───────────────────────────────────────────────────

///|
/// Wraps a chrome-devtools-mcp child process with stdin/stdout pipes.
/// Provides synchronous line-based I/O for JSON-RPC communication.
pub(all) struct BrowserProcess {
  mut handle : Int
  mut pid : Int
  mut alive : Bool
}

// ── Native implementation ───────────────────────────────────────────────────

///|
/// Maximum line buffer size for reading process stdout (8 KB).
let process_read_buffer_size : Int = 8192

///|
/// Spawn the MCP daemon process with the given command and arguments.
#cfg(target="native")
pub fn BrowserProcess::spawn(
  command : String,
  args : Array[String],
) -> Result[BrowserProcess, String] {
  let handle = spawn_browser_process_ffi(command, args, args.length())
  if handle < 0 {
    return Err("Failed to spawn process: \{command}")
  }
  let pid = get_process_pid_ffi(handle)
  Ok({ handle, pid, alive: true })
}

///|
/// Write a line to the process stdin (appends newline).
#cfg(target="native")
pub fn BrowserProcess::write_line(
  self : BrowserProcess,
  line : String,
) -> Result[Unit, String] {
  if !self.alive {
    return Err("Process is not alive")
  }
  let data = (line + "\n").to_bytes()
  let result = write_process_stdin_ffi(self.handle, data, data.length())
  if result < 0 {
    self.alive = false
    return Err("Failed to write to process stdin")
  }
  Ok(())
}

///|
/// Read a line from the process stdout (blocking).
#cfg(target="native")
pub fn BrowserProcess::read_line(
  self : BrowserProcess,
) -> Result[String, String] {
  if !self.alive {
    return Err("Process is not alive")
  }
  let buffer = Bytes::make(process_read_buffer_size, 0)
  let bytes_read = read_process_stdout_line_ffi(
    self.handle,
    buffer,
    process_read_buffer_size,
  )
  if bytes_read < 0 {
    self.alive = false
    return Err("Failed to read from process stdout")
  }
  if bytes_read == 0 {
    return Err("Process stdout returned empty line")
  }
  Ok(buffer[:bytes_read].to_string())
}

///|
/// Check if the process is still alive.
#cfg(target="native")
pub fn BrowserProcess::is_alive(self : BrowserProcess) -> Bool {
  if !self.alive {
    return false
  }
  let alive = is_process_alive_ffi(self.handle)
  self.alive = alive
  alive
}

///|
/// Kill the process and release resources.
#cfg(target="native")
pub fn BrowserProcess::kill(self : BrowserProcess) -> Result[Unit, String] {
  if !self.alive {
    return Ok(())
  }
  let result = terminate_process_ffi(self.handle)
  self.alive = false
  let _ = close_process_handle_ffi(self.handle)
  if result < 0 {
    return Err("Failed to terminate process")
  }
  Ok(())
}

// ── WASM fallback stubs ────────────────────────────────────────────────────

///|
/// Spawn the MCP daemon process (WASM stub — not supported).
#cfg(any(target="wasm", target="wasm-gc", target="js"))
pub fn BrowserProcess::spawn(
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
pub fn BrowserProcess::write_line(
  self : BrowserProcess,
  line : String,
) -> Result[Unit, String] {
  let _ = line
  Err("Process I/O not supported on wasm target")
}

///|
/// Read a line from process stdout (WASM stub — not supported).
#cfg(any(target="wasm", target="wasm-gc", target="js"))
pub fn BrowserProcess::read_line(
  self : BrowserProcess,
) -> Result[String, String] {
  Err("Process I/O not supported on wasm target")
}

///|
/// Check if process is alive (WASM stub — always false).
#cfg(any(target="wasm", target="wasm-gc", target="js"))
pub fn BrowserProcess::is_alive(self : BrowserProcess) -> Bool {
  false
}

///|
/// Kill the process (WASM stub — no-op).
#cfg(any(target="wasm", target="wasm-gc", target="js"))
pub fn BrowserProcess::kill(self : BrowserProcess) -> Result[Unit, String] {
  self.alive = false
  Ok(())
}
