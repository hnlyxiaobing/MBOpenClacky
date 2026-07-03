///|
/// pty_ffi.mbt — Native FFI declarations for PTY operations.
///
/// Compiled only for the `native` target (see moon.pkg targets).
/// The wasm target uses pty_ffi_wasm.mbt which provides the same API as stubs.

// ---- Low-level C FFI declarations ----

#borrow(shell, cwd, out_pid)
extern "C" fn mb_pty_spawn_c(
  shell : String,
  cwd : String,
  cols : Int,
  rows : Int,
  out_pid : Ref[Int],
) -> Int = "mb_pty_spawn"

///|
#borrow(buf)
extern "C" fn mb_pty_read_c(
  fd : Int,
  buf : Bytes,
  max_bytes : Int,
  timeout_ms : Int,
) -> Int = "mb_pty_read"

///|
#borrow(data)
extern "C" fn mb_pty_write_c(fd : Int, data : String, len : Int) -> Int = "mb_pty_write"

///|
extern "C" fn mb_pty_close_fd_c(fd : Int) -> Unit = "mb_pty_close_fd"

///|
extern "C" fn mb_pty_wait_c(pid : Int, nohang : Int) -> Int = "mb_pty_wait"

///|
extern "C" fn mb_pty_kill_pid_c(pid : Int) -> Int = "mb_pty_kill_pid"

///|
extern "C" fn mb_pty_resize_c(fd : Int, cols : Int, rows : Int) -> Int = "mb_pty_resize"

///|
extern "C" fn mb_pty_available_c() -> Int = "mb_pty_available"

///|
extern "C" fn mb_pty_time_ms_c() -> Int = "mb_pty_time_ms"

// ---- High-level wrappers (shared API with pty_ffi_wasm.mbt) ----

///|
/// Check if PTY is supported on this platform.
fn pty_is_available() -> Bool {
  mb_pty_available_c() != 0
}

///|
/// Get monotonic time in milliseconds.
fn pty_ffi_time_ms() -> Int {
  mb_pty_time_ms_c()
}

///|
/// Spawn a new PTY process. Returns (master_fd, child_pid) on success.
fn pty_ffi_spawn(
  shell : String,
  cwd : String,
  cols : Int,
  rows : Int,
) -> Result[(Int, Int), String] {
  let pid_ref : Ref[Int] = Ref(0)
  let fd = mb_pty_spawn_c(shell, cwd, cols, rows, pid_ref)
  if fd < 0 {
    Err("failed to spawn PTY")
  } else {
    Ok((fd, pid_ref.val))
  }
}

///|
/// Read from PTY with timeout. Returns (data_string, bytes_read).
/// bytes_read > 0: data available; 0: timeout; -1: EOF/error.
fn pty_ffi_read(fd : Int, max_bytes : Int, timeout_ms : Int) -> (String, Int) {
  let buf = Bytes::make(max_bytes, 0)
  let n = mb_pty_read_c(fd, buf, max_bytes, timeout_ms)
  if n > 0 {
    (@utf8.decode_lossy(buf[:n]), n)
  } else {
    ("", n)
  }
}

///|
/// Write data to PTY. Returns bytes written or -1 on error.
fn pty_ffi_write(fd : Int, data : String) -> Int {
  mb_pty_write_c(fd, data, data.length())
}

///|
/// Close the PTY master file descriptor.
fn pty_ffi_close(fd : Int) -> Unit {
  mb_pty_close_fd_c(fd)
}

///|
/// Wait for child process. Returns exit status or -2 if still running.
fn pty_ffi_wait(pid : Int, nohang : Bool) -> Int {
  mb_pty_wait_c(pid, if nohang { 1 } else { 0 })
}

///|
/// Kill child process (SIGTERM then SIGKILL).
fn pty_ffi_kill(pid : Int) -> Int {
  mb_pty_kill_pid_c(pid)
}

///|
/// Resize the PTY window.
fn pty_ffi_resize(fd : Int, cols : Int, rows : Int) -> Int {
  mb_pty_resize_c(fd, cols, rows)
}
