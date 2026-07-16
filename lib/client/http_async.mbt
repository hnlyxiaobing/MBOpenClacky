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
/// Windows fallback: the async pipe + C-thread path relies on Unix-style
/// file descriptors, so we delegate to the synchronous HTTP client. This
/// blocks the current coroutine until the response arrives, but keeps the
/// public API available on Windows native builds.
#cfg(platform="windows")
pub async fn http_post_async(
  url : String,
  body : String,
  headers : Array[(String, String)],
  timeout_ms : Int,
) -> Result[HttpResponse, HttpError] {
  http_post(url, body, headers, timeout_ms)
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
