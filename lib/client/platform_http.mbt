///| Platform HTTP Client with domain failover and exponential backoff retry.

// ── Configuration ────────────────────────────────────────────────────────────

///|
/// Platform HTTP client configuration.
pub struct PlatformHttpConfig {
  primary_host : String
  fallback_host : String
  open_timeout_ms : Int
  read_timeout_ms : Int
  max_retries : Int
  initial_backoff_ms : Int
  proxy_url : String
} derive(Debug, Eq)

///|
/// Create a new platform HTTP config with sensible defaults.
pub fn PlatformHttpConfig::new(
  primary_host~ : String,
  fallback_host? : String = "",
  open_timeout_ms? : Int = 8000,
  read_timeout_ms? : Int = 15000,
  max_retries? : Int = 2,
  initial_backoff_ms? : Int = 500,
  proxy_url? : String = "",
) -> PlatformHttpConfig {
  {
    primary_host,
    fallback_host,
    open_timeout_ms,
    read_timeout_ms,
    max_retries,
    initial_backoff_ms,
    proxy_url,
  }
}

// ── HTTP Types ───────────────────────────────────────────────────────────────

///|
/// HTTP response returned from platform requests.
pub(all) struct HttpResponse {
  status_code : Int
  body : String
  headers : Array[(String, String)]
} derive(Debug)

///|
/// HTTP request method.
pub enum HttpMethod {
  Get
  Post
  Put
  Delete
} derive(Debug)

///|
/// HTTP request error types.
pub enum HttpError {
  Timeout(String)
  ConnectionFailed(String)
  ServerError(Int, String)
  ClientError(Int, String)
  AllHostsFailed(String)
} derive(Debug)

// ── Platform HTTP Client ─────────────────────────────────────────────────────

///|
/// Platform HTTP client with domain failover and retry.
pub struct PlatformHttpClient {
  config : PlatformHttpConfig
  mut current_host : String
  mut consecutive_failures : Int
  mut last_failover_epoch : Int
}

///|
/// Create a new platform HTTP client.
pub fn PlatformHttpClient::new(
  config : PlatformHttpConfig,
) -> PlatformHttpClient {
  {
    config,
    current_host: config.primary_host,
    consecutive_failures: 0,
    last_failover_epoch: 0,
  }
}

///|
/// Send a GET request.
pub fn PlatformHttpClient::get(
  self : PlatformHttpClient,
  path : String,
  headers? : Array[(String, String)] = [],
) -> Result[HttpResponse, HttpError] {
  self.execute_with_retry(Get, path, "", headers)
}

///|
/// Send a POST request.
pub fn PlatformHttpClient::post(
  self : PlatformHttpClient,
  path : String,
  body : String,
  headers? : Array[(String, String)] = [],
) -> Result[HttpResponse, HttpError] {
  self.execute_with_retry(Post, path, body, headers)
}

///|
/// Send a PUT request.
pub fn PlatformHttpClient::put(
  self : PlatformHttpClient,
  path : String,
  body : String,
  headers? : Array[(String, String)] = [],
) -> Result[HttpResponse, HttpError] {
  self.execute_with_retry(Put, path, body, headers)
}

///|
/// Send a DELETE request.
pub fn PlatformHttpClient::delete(
  self : PlatformHttpClient,
  path : String,
  headers? : Array[(String, String)] = [],
) -> Result[HttpResponse, HttpError] {
  self.execute_with_retry(Delete, path, "", headers)
}

///|
/// Execute request with retry and failover logic.
fn PlatformHttpClient::execute_with_retry(
  self : PlatformHttpClient,
  http_method : HttpMethod,
  path : String,
  body : String,
  headers : Array[(String, String)],
) -> Result[HttpResponse, HttpError] {
  let max_attempts = self.config.max_retries + 1
  let mut last_error : HttpError = ConnectionFailed("no attempt made")
  // Try current host
  for attempt = 0; attempt < max_attempts; attempt = attempt + 1 {
    if attempt > 0 {
      let _backoff = self.calculate_backoff(attempt - 1)
      // In a real implementation, we would sleep for backoff ms here
    }
    let url = build_request_url(self.current_host, path)
    let result = send_request(
      http_method,
      url,
      body,
      headers,
      self.config.read_timeout_ms,
    )
    match result {
      Ok(response) => {
        self.consecutive_failures = 0
        return Ok(response)
      }
      Err(err) => {
        last_error = err
        self.consecutive_failures = self.consecutive_failures + 1
        if !is_retryable(last_error) {
          return Err(last_error)
        }
      }
    }
  }
  // If we can failover, try the other host
  if self.should_failover(last_error) {
    self.do_failover()
    // Only retry on failover host if we actually switched
    if self.current_host != self.config.primary_host ||
      self.config.fallback_host == "" {
      // We switched hosts, try again
      for attempt = 0; attempt < max_attempts; attempt = attempt + 1 {
        if attempt > 0 {
          let _backoff = self.calculate_backoff(attempt - 1)
        }
        let url = build_request_url(self.current_host, path)
        let result = send_request(
          http_method,
          url,
          body,
          headers,
          self.config.read_timeout_ms,
        )
        match result {
          Ok(response) => {
            self.consecutive_failures = 0
            return Ok(response)
          }
          Err(err) => {
            last_error = err
            self.consecutive_failures = self.consecutive_failures + 1
            if !is_retryable(last_error) {
              return Err(last_error)
            }
          }
        }
      }
    }
  }
  Err(
    AllHostsFailed("All hosts exhausted after retries: \{last_error.to_repr()}"),
  )
}

///|
/// Calculate exponential backoff with cap at 30000ms.
fn PlatformHttpClient::calculate_backoff(
  self : PlatformHttpClient,
  attempt : Int,
) -> Int {
  let base = self.config.initial_backoff_ms
  let multiplier = pow2(attempt)
  let backoff = base * multiplier
  if backoff > 30000 {
    30000
  } else {
    backoff
  }
}

///|
/// Determine if an error warrants failover to another host.
fn PlatformHttpClient::should_failover(
  self : PlatformHttpClient,
  error : HttpError,
) -> Bool {
  guard self.config.fallback_host.length() > 0 else { return false }
  match error {
    Timeout(_) => true
    ConnectionFailed(_) => true
    ServerError(_, _) => true
    ClientError(_, _) => false
    AllHostsFailed(_) => false
  }
}

///|
/// Execute failover: switch to the other host.
fn PlatformHttpClient::do_failover(self : PlatformHttpClient) -> Unit {
  if self.config.fallback_host == "" {
    return
  }
  if self.current_host == self.config.primary_host {
    self.current_host = self.config.fallback_host
  } else {
    self.current_host = self.config.primary_host
  }
  self.last_failover_epoch = 1
  self.consecutive_failures = 0
}

///|
/// Maximum response body buffer size (4 MB).
let http_response_buf_size : Int = 4 * 1024 * 1024

///|
/// C FFI: synchronous HTTP request via WinHTTP (Windows) or libcurl (Linux).
/// meta_buf layout: [0..3] = HTTP status (LE int32), [4..7] = body size (LE int32).
#cfg(target="native")
#borrow(http_method, url, headers, body, resp_buf, meta_buf, err_buf)
extern "C" fn http_post_ffi(
  http_method : String,
  url : String,
  headers : String,
  body : String,
  timeout_ms : Int,
  resp_buf : Bytes,
  meta_buf : Bytes,
  err_buf : Bytes,
) -> Int = "mbopenclacky_http_post"

///|
/// Read a little-endian Int32 from a Bytes buffer at the given offset.
fn read_le_int32(buf : Bytes, offset : Int) -> Int {
  let b0 = buf[offset].to_int()
  let b1 = buf[offset + 1].to_int()
  let b2 = buf[offset + 2].to_int()
  let b3 = buf[offset + 3].to_int()
  b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
}

///|
/// Convert an HttpMethod enum to its HTTP method string.
fn http_method_str(m : HttpMethod) -> String {
  match m {
    Get => "GET"
    Post => "POST"
    Put => "PUT"
    Delete => "DELETE"
  }
}

///|
/// Format request headers as "Key: Value\r\n" pairs for the C FFI.
fn format_headers(headers : Array[(String, String)]) -> String {
  let mut result = ""
  for pair in headers {
    let (k, v) = pair
    result = result + k + ": " + v + "\r\n"
  }
  result
}

///|
/// Actual HTTP transport via C FFI (WinHTTP on Windows, libcurl on Linux/macOS).
/// The C side handles UTF-16→UTF-8 conversion for MoonBit String parameters.
pub fn send_request(
  http_method : HttpMethod,
  url : String,
  body : String,
  headers : Array[(String, String)],
  timeout_ms : Int,
) -> Result[HttpResponse, HttpError] {
  let method_str = http_method_str(http_method)
  let headers_str = format_headers(headers)
  // Allocate output buffers
  let resp_buf = Bytes::make(http_response_buf_size, 0)
  let meta_buf = Bytes::make(8, 0)
  let err_buf = Bytes::make(1024, 0)
  // Call C FFI (C handles String→UTF-8 conversion internally)
  let ffi_result = http_post_ffi(
    method_str, url, headers_str, body, timeout_ms, resp_buf, meta_buf, err_buf,
  )
  // Parse metadata from meta_buf
  let http_status = read_le_int32(meta_buf, 0)
  let body_size = read_le_int32(meta_buf, 4)
  if ffi_result != 0 {
    let err_msg = @utf8.decode_lossy(err_buf[:1024])
    return Err(ConnectionFailed(err_msg))
  }
  let resp_body = if body_size > 0 {
    @utf8.decode_lossy(resp_buf[:body_size])
  } else {
    ""
  }
  // Build response headers array (empty for now; not parsed from C response)
  let resp_headers : Array[(String, String)] = []
  Ok(HttpResponse::{
    status_code: http_status,
    body: resp_body,
    headers: resp_headers,
  })
}

///|
/// Convenience wrapper: send an HTTP POST request with the given URL, body, and headers.
/// Designed for external callers (e.g. agent package) who don't have direct access to HttpMethod.
pub fn http_post(
  url : String,
  body : String,
  headers : Array[(String, String)],
  timeout_ms : Int,
) -> Result[HttpResponse, HttpError] {
  send_request(Post, url, body, headers, timeout_ms)
}

///|
/// Convenience wrapper: send an HTTP GET request with the given URL and headers.
/// Designed for external callers (e.g. web_fetch, web_search tools) who need simple GET requests.
pub fn http_get(
  url : String,
  headers : Array[(String, String)],
  timeout_ms : Int,
) -> Result[HttpResponse, HttpError] {
  send_request(Get, url, "", headers, timeout_ms)
}

// ── Public Helpers ───────────────────────────────────────────────────────────

///|
/// Reset failover state, returning to primary host.
pub fn PlatformHttpClient::reset_failover(self : PlatformHttpClient) -> Unit {
  self.current_host = self.config.primary_host
  self.consecutive_failures = 0
  self.last_failover_epoch = 0
}

///|
/// Get the currently active host.
pub fn PlatformHttpClient::active_host(self : PlatformHttpClient) -> String {
  self.current_host
}

///|
/// Check if an error is retryable.
pub fn is_retryable(error : HttpError) -> Bool {
  match error {
    Timeout(_) => true
    ConnectionFailed(_) => true
    ServerError(_, _) => true
    ClientError(_, _) => false
    AllHostsFailed(_) => false
  }
}

// ── Internal Utilities ───────────────────────────────────────────────────────

///|
/// Build a full URL from host and path.
fn build_request_url(host : String, path : String) -> String {
  let trimmed_host = if host.length() > 0 &&
    host[host.length() - 1:].to_owned() == "/" {
    host[:host.length() - 1].to_owned()
  } else {
    host
  }
  let trimmed_path = if path.length() > 0 && path[:1].to_owned() == "/" {
    path[1:].to_owned()
  } else {
    path
  }
  "\{trimmed_host}/\{trimmed_path}"
}

///|
/// Compute 2^n for small non-negative n.
fn pow2(n : Int) -> Int {
  if n <= 0 {
    1
  } else {
    let mut result = 1
    for _i = 0; _i < n; _i = _i + 1 {
      result = result * 2
    }
    result
  }
}
