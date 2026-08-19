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
/// `timeout_ms` bounds the request/read phase, `open_timeout_ms` (default
/// 10s) bounds only the connect phase — mirroring Ruby's split
/// open_timeout/read_timeout.
pub async fn http_post_async(
  url : String,
  body : String,
  headers : Array[(String, String)],
  timeout_ms : Int,
  open_timeout_ms? : Int = 10000,
) -> Result[HttpResponse, HttpError] {
  send_request(Post, url, body, headers, timeout_ms, open_timeout_ms~)
}

// ── Streaming HTTP (SSE) ──────────────────────────────────────────

///|
/// Streaming HTTP POST: response bytes are delivered incrementally;
/// complete SSE frames are extracted at byte level (safe across arbitrary
/// transport-chunk boundaries) by `SseBytePump` and passed to `on_frame`
/// as they arrive. Returns the full accumulated body once the stream ends.
/// The connect phase (TCP + TLS) is bounded by `open_timeout_ms` (default
/// 10s) while the streaming read is bounded by `timeout_ms`, mirroring
/// Ruby's open_timeout/read_timeout split. The `Accept: text/event-stream`
/// header is set for every streaming request (Ruby client.rb sets it on
/// `send_anthropic_stream_request`).
pub async fn http_post_stream_async(
  url : String,
  body : String,
  headers : Array[(String, String)],
  timeout_ms : Int,
  on_frame : (SseFrame) -> Unit,
  open_timeout_ms? : Int = 10000,
) -> Result[HttpResponse, HttpError] {
  let headers_map = headers_to_map(headers)
  // Phase 1: connect within the open timeout window.
  let conn = @async.with_timeout_opt(open_timeout_ms, () => {
    stream_connect(url, headers_map)
  }) catch {
    err => return Err(ConnectionFailed("POST \{url}: \{err}"))
  }
  match conn {
    None =>
      Err(Timeout("POST \{url} connect timed out after \{open_timeout_ms}ms"))
    Some(client) => {
      // Phase 2: stream the request/response within the read timeout.
      let result = @async.with_timeout_opt(timeout_ms, () => {
        stream_request_with_client(client, url, body, on_frame)
      }) catch {
        err => {
          client.close()
          return Err(ConnectionFailed("POST \{url}: \{err}"))
        }
      }
      match result {
        None => Err(Timeout("POST \{url} timed out after \{timeout_ms}ms"))
        Some(resp) => Ok(resp)
      }
    }
  }
}

///|
/// Connect for a streaming POST and register the `Accept` SSE header.
async fn stream_connect(
  url : String,
  headers : Map[String, String],
) -> @http.Client {
  let (base, _path) = split_base_path(url)
  headers["Accept"] = "text/event-stream"
  @http.Client::Client(base, headers=string_headers_to_async_headers(headers))
}

///|
/// Perform a streaming POST on an already-connected client and drain the
/// response body through the SSE byte pump. Raises on transport errors;
/// HTTP error statuses are returned as normal responses (matching the
/// previous C transport semantics).
async fn stream_request_with_client(
  client : @http.Client,
  url : String,
  body : String,
  on_frame : (SseFrame) -> Unit,
) -> HttpResponse {
  let (_base, path) = split_base_path(url)
  defer client.close()
  client.request(@http.Post, path)
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
}
