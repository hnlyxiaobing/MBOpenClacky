///|
/// Async HTTP client built on `@async/http`.
///
/// The transport is native async I/O (IOCP + Schannel on Windows,
/// epoll/kqueue + OpenSSL on POSIX), so no worker threads, pipes or
/// polling slots are involved: the event loop stays responsive while a
/// request is in flight, and plain async concurrency (`@async` task
/// groups) replaces the old C-side slot thread pool.

///|
/// Asynchronous HTTP POST: non-blocking request via `@async/http`.
/// `timeout_ms` bounds the whole request; on expiry the in-flight
/// request is cancelled and `HttpError::Timeout` is returned.
pub async fn http_post_async(
  url : String,
  body : String,
  headers : Array[(String, String)],
  timeout_ms : Int,
) -> Result[HttpResponse, HttpError] {
  send_request(Post, url, body, headers, timeout_ms)
}

// ── Streaming HTTP (SSE) ──────────────────────────────────────────

///|
/// Streaming HTTP POST: response bytes are delivered incrementally;
/// complete SSE frames are extracted at byte level (safe across arbitrary
/// transport-chunk boundaries) by `SseBytePump` and passed to `on_frame`
/// as they arrive. Returns the full accumulated body once the stream ends.
pub async fn http_post_stream_async(
  url : String,
  body : String,
  headers : Array[(String, String)],
  timeout_ms : Int,
  on_frame : (SseFrame) -> Unit,
) -> Result[HttpResponse, HttpError] {
  let headers_map = headers_to_map(headers)
  let result = @async.with_timeout_opt(timeout_ms, () => {
    stream_request(url, body, headers_map, on_frame)
  }) catch {
    err => return Err(ConnectionFailed("POST \{url}: \{err}"))
  }
  match result {
    None => Err(Timeout("POST \{url} timed out"))
    Some(resp) => Ok(resp)
  }
}

///|
/// Perform a streaming POST via `@http.post_stream` and drain the
/// response body through the SSE byte pump. Raises on transport errors;
/// HTTP error statuses are returned as normal responses (matching the
/// previous C transport semantics).
async fn stream_request(
  url : String,
  body : String,
  headers : Map[String, String],
  on_frame : (SseFrame) -> Unit,
) -> HttpResponse {
  let client = @http.post_stream(url, headers~)
  try {
    client.write(@utf8.encode(body))
    let resp = client.end_request()
    let pump = SseBytePump::new()
    let full : Array[Byte] = []
    for ;; {
      match client.read_some() {
        None => break
        Some(chunk) => {
          for b in chunk {
            full.push(b)
          }
          for frame in pump.feed(chunk) {
            on_frame(frame)
          }
        }
      }
    }
    // Flush any unterminated trailing frame.
    for frame in pump.finish() {
      on_frame(frame)
    }
    HttpResponse::{
      status_code: resp.code,
      body: @utf8.decode_lossy(Bytes::from_array(full)),
      headers: [],
    }
  } catch {
    err => {
      client.close()
      raise err
    }
  } noraise {
    result => {
      client.close()
      result
    }
  }
}
