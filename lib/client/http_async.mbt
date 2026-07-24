///|
/// Async HTTP client: offloads synchronous HTTP calls to a C thread.
///
/// The C thread performs the HTTP request (WinHTTP/libcurl) and writes
/// the result to an OS pipe. MoonBit's async event loop reads from the
/// pipe without blocking, allowing other coroutines (terminal input,
/// spinner animation, etc.) to run during HTTP waits.
#cfg(target="native")
#borrow(http_method, url, headers, body)
extern "C" fn start_http_thread(
  http_method : String,
  url : String,
  headers : String,
  body : String,
  timeout_ms : Int,
  write_fd : Int,
) -> Int = "mbopenclacky_start_http_thread"

///|
/// Read a little-endian Int32 from a Bytes buffer at the given offset.
#cfg(not(platform="windows"))
fn read_le32(buf : Bytes, offset : Int) -> Int {
  let b0 = buf[offset].to_int()
  let b1 = buf[offset + 1].to_int()
  let b2 = buf[offset + 2].to_int()
  let b3 = buf[offset + 3].to_int()
  b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
}

///|
/// Asynchronous HTTP POST: runs the request in a C thread, reads the
/// result via an OS pipe. Does not block the async event loop.
#cfg(not(platform="windows"))
pub async fn http_post_async(
  url : String,
  body : String,
  headers : Array[(String, String)],
  timeout_ms : Int,
) -> Result[HttpResponse, HttpError] {
  let headers_str = format_headers_async(headers)
  // WSL1: pipe fds can collide with fds already registered in the event
  // loop (uncatchable panic in IoHandle::from_fd), so use slots there.
  if @utils.is_wsl1() {
    return http_post_slot_async(url, body, headers_str, timeout_ms)
  }
  let (read_end, write_end) = @pipe.pipe() catch {
    err => return Err(ConnectionFailed("pipe creation failed: \{err}"))
  }
  let write_fd = write_end.fd()
  let ffi_result = start_http_thread(
    "POST", url, headers_str, body, timeout_ms, write_fd,
  )
  if ffi_result != 0 {
    read_end.close()
    return Err(ConnectionFailed("failed to start HTTP thread"))
  }
  let data = read_end.read_all() catch {
    _ => {
      read_end.close()
      return Err(ConnectionFailed("pipe read failed"))
    }
  }
  read_end.close()
  let all_bytes = data.binary()
  if all_bytes.length() < 12 {
    return Err(ConnectionFailed("incomplete HTTP response from thread"))
  }
  let result_flag = read_le32(all_bytes, 0)
  let http_status = read_le32(all_bytes, 4)
  let body_len = read_le32(all_bytes, 8)
  let actual_body = if body_len > 0 && all_bytes.length() >= 12 + body_len {
    @utf8.decode_lossy(all_bytes[12:12 + body_len])
  } else {
    ""
  }
  if result_flag != 0 {
    return Err(ConnectionFailed(actual_body))
  }
  Ok(HttpResponse::{ status_code: http_status, body: actual_body, headers: [] })
}

///|
/// Slot-based async HTTP (Windows always; WSL1 as a pipe fallback): the
/// worker thread performs the request and stores the result in a
/// process-global slot; the coroutine polls the slot with @async.sleep
/// between checks, so the event loop never blocks.
///
/// A slot-based design is used instead of the Unix pipe because the pipe
/// HANDLEs handed out by moonbitlang/async are registered with the
/// runtime's IOCP — overlapped writes from a non-runtime thread would post
/// completion packets the event loop cannot interpret. On WSL1 the pipe
/// fd can additionally collide with an fd already registered in the event
/// loop, which makes IoHandle::from_fd panic (uncatchable).
#cfg(target="native")
#borrow(http_method, url, headers, body)
extern "C" fn http_start_ffi(
  http_method : String,
  url : String,
  headers : String,
  body : String,
  timeout_ms : Int,
) -> Int = "mbopenclacky_http_start"

///|
#cfg(target="native")
extern "C" fn http_poll_ffi(slot_id : Int) -> Int = "mbopenclacky_http_poll"

///|
#cfg(target="native")
extern "C" fn http_result_status_ffi(slot_id : Int) -> Int = "mbopenclacky_http_result_status"

///|
#cfg(target="native")
extern "C" fn http_result_body_ffi(slot_id : Int) -> String = "mbopenclacky_http_result_body"

///|
#cfg(target="native")
extern "C" fn http_abandon_ffi(slot_id : Int) -> Unit = "mbopenclacky_http_abandon"

///|
/// Poll the request slot until the worker thread completes, yielding to
/// the event loop between checks so the UI stays responsive.
#cfg(target="native")
async fn wait_http_slot(slot_id : Int) -> Unit {
  for ;; {
    let state = http_poll_ffi(slot_id)
    if state != 0 {
      return
    }
    @async.sleep(25)
  }
}

///|
/// Shared slot implementation: offload the request to a C worker thread
/// and poll its result slot — the async event loop (spinner, input,
/// Ctrl-C) keeps running while the request is in flight. If the coroutine
/// is cancelled, the slot is abandoned (the worker thread frees it on
/// completion).
#cfg(target="native")
async fn http_post_slot_async(
  url : String,
  body : String,
  headers_str : String,
  timeout_ms : Int,
) -> Result[HttpResponse, HttpError] {
  let slot_id = http_start_ffi("POST", url, headers_str, body, timeout_ms)
  if slot_id < 0 {
    return Err(ConnectionFailed("failed to start HTTP thread"))
  }
  wait_http_slot(slot_id) catch {
    err => {
      http_abandon_ffi(slot_id)
      raise err
    }
  }
  let status = http_result_status_ffi(slot_id)
  // Fetches the body AND frees the slot for reuse.
  let actual_body = http_result_body_ffi(slot_id)
  if status < 0 {
    return Err(ConnectionFailed(actual_body))
  }
  Ok(HttpResponse::{ status_code: status, body: actual_body, headers: [] })
}

///|
/// Windows always uses the slot path.
#cfg(platform="windows")
pub async fn http_post_async(
  url : String,
  body : String,
  headers : Array[(String, String)],
  timeout_ms : Int,
) -> Result[HttpResponse, HttpError] {
  http_post_slot_async(url, body, format_headers_async(headers), timeout_ms)
}

///|
fn format_headers_async(headers : Array[(String, String)]) -> String {
  let mut result = ""
  for pair in headers {
    let (k, v) = pair
    result = result + k + ": " + v + "\r\n"
  }
  result
}

// ── Streaming HTTP (SSE) ──────────────────────────────────────────

///|
/// Unix streaming FFI: the worker thread pushes length-prefixed frames
/// onto the pipe as response bytes arrive.
#cfg(not(platform="windows"))
#borrow(http_method, url, headers, body)
extern "C" fn start_http_stream_thread(
  http_method : String,
  url : String,
  headers : String,
  body : String,
  timeout_ms : Int,
  write_fd : Int,
) -> Int = "mbopenclacky_start_http_stream_thread"

///|
/// Slot streaming FFI (Windows always; WSL1 as a pipe fallback): the
/// worker appends response bytes to a slot, drained incrementally.
#cfg(target="native")
#borrow(http_method, url, headers, body)
extern "C" fn http_stream_start_ffi(
  http_method : String,
  url : String,
  headers : String,
  body : String,
  timeout_ms : Int,
) -> Int = "mbopenclacky_http_stream_start"

///|
#cfg(target="native")
extern "C" fn http_stream_drain_ffi(slot_id : Int) -> String = "mbopenclacky_http_stream_drain"

///|
/// Streaming HTTP POST (Unix): response bytes are delivered incrementally;
/// complete SSE frames are extracted at byte level (safe across arbitrary
/// transport-chunk boundaries) and passed to `on_frame` as they arrive.
/// Returns the full accumulated body once the stream ends.
#cfg(not(platform="windows"))
pub async fn http_post_stream_async(
  url : String,
  body : String,
  headers : Array[(String, String)],
  timeout_ms : Int,
  on_frame : (SseFrame) -> Unit,
) -> Result[HttpResponse, HttpError] {
  let headers_str = format_headers_async(headers)
  // WSL1: pipe fds can collide with fds already registered in the event
  // loop (uncatchable panic in IoHandle::from_fd), so use slots there.
  if @utils.is_wsl1() {
    return http_post_stream_slot_async(
      url, body, headers_str, timeout_ms, on_frame,
    )
  }
  let (read_end, write_end) = @pipe.pipe() catch {
    err => return Err(ConnectionFailed("pipe creation failed: \{err}"))
  }
  let write_fd = write_end.fd()
  let ffi_result = start_http_stream_thread(
    "POST", url, headers_str, body, timeout_ms, write_fd,
  )
  if ffi_result != 0 {
    read_end.close()
    return Err(ConnectionFailed("failed to start HTTP thread"))
  }
  let pump = SseBytePump::new()
  let full : Array[Byte] = []
  let trailer = read_stream_frames(read_end, pump, full, on_frame) catch {
    err => {
      read_end.close()
      raise err
    }
  }
  read_end.close()
  match trailer {
    None => Err(ConnectionFailed("stream ended unexpectedly"))
    Some(t) => {
      let result_flag = read_le32(t, 0)
      let http_status = read_le32(t, 4)
      let body_text = @utf8.decode_lossy(Bytes::from_array(full))
      if result_flag != 0 {
        return Err(ConnectionFailed(body_text))
      }
      Ok(HttpResponse::{
        status_code: http_status,
        body: body_text,
        headers: [],
      })
    }
  }
}

///|
/// Read length-prefixed stream frames until the end marker, then the
/// 8-byte trailer. Returns None on unexpected EOF.
#cfg(not(platform="windows"))
async fn read_stream_frames(
  read_end : @pipe.PipeRead,
  pump : SseBytePump,
  full : Array[Byte],
  on_frame : (SseFrame) -> Unit,
) -> Bytes? {
  for ;; {
    let hdr = read_end.read_exactly(4) catch { _ => return None }
    let len = read_le32(hdr, 0)
    if len == 0 {
      break
    }
    let data = read_end.read_exactly(len) catch { _ => return None }
    for b in data {
      full.push(b)
    }
    for frame in pump.feed(data) {
      on_frame(frame)
    }
  }
  // Flush any unterminated trailing frame, then read the trailer.
  for frame in pump.finish() {
    on_frame(frame)
  }
  let t = read_end.read_exactly(8) catch { _ => return None }
  Some(t)
}

///|
/// Shared slot streaming implementation: the worker thread appends
/// response bytes to a slot; the coroutine drains them between event-loop
/// yields and extracts SSE frames. Drain boundaries are UTF-8-safe
/// (guaranteed by the C side). If the coroutine is cancelled the slot is
/// abandoned.
#cfg(target="native")
async fn http_post_stream_slot_async(
  url : String,
  body : String,
  headers_str : String,
  timeout_ms : Int,
  on_frame : (SseFrame) -> Unit,
) -> Result[HttpResponse, HttpError] {
  let slot_id = http_stream_start_ffi(
    "POST", url, headers_str, body, timeout_ms,
  )
  if slot_id < 0 {
    return Err(ConnectionFailed("failed to start HTTP thread"))
  }
  let pump = SseBytePump::new()
  let full = StringBuilder::new()
  wait_stream_slot(slot_id, pump, full, on_frame) catch {
    err => {
      http_abandon_ffi(slot_id)
      raise err
    }
  }
  let status = http_result_status_ffi(slot_id)
  // Fetches the error body (if any) AND frees the slot for reuse.
  let err_body = http_result_body_ffi(slot_id)
  if status < 0 {
    return Err(ConnectionFailed(err_body))
  }
  Ok(HttpResponse::{ status_code: status, body: full.to_string(), headers: [] })
}

///|
/// Windows always uses the slot streaming path.
#cfg(platform="windows")
pub async fn http_post_stream_async(
  url : String,
  body : String,
  headers : Array[(String, String)],
  timeout_ms : Int,
  on_frame : (SseFrame) -> Unit,
) -> Result[HttpResponse, HttpError] {
  http_post_stream_slot_async(
    url,
    body,
    format_headers_async(headers),
    timeout_ms,
    on_frame,
  )
}

///|
/// Poll + drain a streaming slot until the worker thread completes.
#cfg(target="native")
async fn wait_stream_slot(
  slot_id : Int,
  pump : SseBytePump,
  full : StringBuilder,
  on_frame : (SseFrame) -> Unit,
) -> Unit {
  for ;; {
    let state = http_poll_ffi(slot_id)
    let chunk = http_stream_drain_ffi(slot_id)
    if chunk.length() > 0 {
      full.write_string(chunk)
      for frame in pump.feed_string(chunk) {
        on_frame(frame)
      }
    }
    if state != 0 {
      break
    }
    @async.sleep(25)
  }
  // Final drain + flush any unterminated trailing frame.
  let chunk = http_stream_drain_ffi(slot_id)
  if chunk.length() > 0 {
    full.write_string(chunk)
    for frame in pump.feed_string(chunk) {
      on_frame(frame)
    }
  }
  for frame in pump.finish() {
    on_frame(frame)
  }
}
