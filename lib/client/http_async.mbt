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

// ── Binary transport (media downloads, multipart uploads) ─────────

///|
/// HTTP response carrying a binary body, for generated-media downloads
/// and multipart uploads where a text round-trip would corrupt bytes.
pub(all) struct HttpResponseBytes {
  status_code : Int
  body : Bytes
  headers : Array[(String, String)]
} derive(Debug)

///|
pub extend HttpResponseBytes with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// Perform a binary-bodied request on an already-connected client.
/// Raises on transport errors; HTTP error statuses are returned as
/// normal responses.
async fn perform_request_bytes(
  client : @http.Client,
  http_method : HttpMethod,
  url : String,
  body : Bytes,
) -> HttpResponseBytes {
  let (_base, path) = split_base_path(url)
  defer client.close()
  client.request(http_request_method(http_method), path)
  if body.length() > 0 {
    client.write(body)
  }
  let resp = client.end_request()
  HttpResponseBytes::{
    status_code: resp.code,
    body: client.read_all().binary(),
    headers: map_to_headers(resp.headers),
  }
}

///|
/// Binary transport via `@async/http`, mirroring `send_request`:
/// `open_timeout_ms` bounds the connect phase, `timeout_ms` the whole
/// request.
pub async fn send_request_bytes(
  http_method : HttpMethod,
  url : String,
  body : Bytes,
  headers : Array[(String, String)],
  timeout_ms : Int,
  open_timeout_ms? : Int = 10000,
) -> Result[HttpResponseBytes, HttpError] {
  let headers_map = headers_to_map(headers)
  let conn = @async.with_timeout_opt(open_timeout_ms, () => {
    connect_client(url, headers_map)
  }) catch {
    err =>
      return Err(
        ConnectionFailed("\{http_method_str(http_method)} \{url}: \{err}"),
      )
  }
  match conn {
    None =>
      Err(
        Timeout(
          "\{http_method_str(http_method)} \{url} connect timed out after \{open_timeout_ms}ms",
        ),
      )
    Some(client) => {
      let result = @async.with_timeout_opt(timeout_ms, () => {
        perform_request_bytes(client, http_method, url, body)
      }) catch {
        err => {
          client.close()
          return Err(
            ConnectionFailed("\{http_method_str(http_method)} \{url}: \{err}"),
          )
        }
      }
      match result {
        None =>
          Err(
            Timeout(
              "\{http_method_str(http_method)} \{url} timed out after \{timeout_ms}ms",
            ),
          )
        Some(resp) => Ok(resp)
      }
    }
  }
}

///|
/// Binary GET: download a resource as raw bytes.
pub async fn http_get_bytes(
  url : String,
  headers : Array[(String, String)],
  timeout_ms : Int,
) -> Result[HttpResponseBytes, HttpError] {
  send_request_bytes(Get, url, Bytes::from_array([]), headers, timeout_ms)
}

///|
/// Binary POST: upload raw bytes (e.g. multipart form bodies).
pub async fn http_post_bytes(
  url : String,
  body : Bytes,
  headers : Array[(String, String)],
  timeout_ms : Int,
) -> Result[HttpResponseBytes, HttpError] {
  send_request_bytes(Post, url, body, headers, timeout_ms)
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
