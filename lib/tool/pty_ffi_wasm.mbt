///|
/// pty_ffi_wasm.mbt — Wasm stubs for PTY operations.
///
/// Compiled for `wasm` and `wasm-gc` targets (see moon.pkg targets).
/// PTY is not available on wasm; all operations return error/empty values.
/// The native target uses pty_ffi.mbt with real C FFI declarations.
/// These functions have the same signatures as the native versions.

///|
/// Check if PTY is supported on this platform. Always false on wasm.
fn pty_is_available() -> Bool {
  false
}

///|
/// Get monotonic time in milliseconds. Returns 0 on wasm.
fn pty_ffi_time_ms() -> Int {
  0
}

///|
/// Spawn a PTY child process. Always fails on wasm.
fn pty_ffi_spawn(
  shell : String,
  cwd : String,
  cols : Int,
  rows : Int,
) -> Result[(Int, Int), String] {
  Err("PTY not available on wasm")
}

///|
/// Read from PTY with timeout. Returns empty on wasm.
fn pty_ffi_read(fd : Int, max_bytes : Int, timeout_ms : Int) -> (String, Int) {
  ("", -1)
}

///|
/// Write data to PTY. Returns -1 on wasm.
fn pty_ffi_write(fd : Int, data : String) -> Int {
  -1
}

///|
/// Close PTY fd. No-op on wasm.
fn pty_ffi_close(fd : Int) -> Unit {
  ()
}

///|
/// Wait for child process. Returns -2 (still running) on wasm.
fn pty_ffi_wait(pid : Int, nohang : Bool) -> Int {
  -2
}

///|
/// Kill child process. Returns 0 on wasm.
fn pty_ffi_kill(pid : Int) -> Int {
  0
}

///|
/// Resize PTY window. Returns -1 on wasm.
fn pty_ffi_resize(fd : Int, cols : Int, rows : Int) -> Int {
  -1
}
