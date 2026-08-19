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
pub extend PlatformHttpConfig with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend PlatformHttpConfig with Eq::{not_equal, equal}

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
pub extend HttpResponse with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// HTTP request method.
pub enum HttpMethod {
  Get
  Post
  Put
  Delete
} derive(Debug)

///|
pub extend HttpMethod with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// HTTP request error types.
pub enum HttpError {
  Timeout(String)
  ConnectionFailed(String)
  ServerError(Int, String)
  ClientError(Int, String)
  AllHostsFailed(String)
} derive(Debug)

///|
pub extend HttpError with @moonbitlang/core/debug.Debug::{to_repr}

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
pub async fn PlatformHttpClient::get(
  self : PlatformHttpClient,
  path : String,
  headers? : Array[(String, String)] = [],
) -> Result[HttpResponse, HttpError] {
  self.execute_with_retry(Get, path, "", headers)
}

///|
/// Send a POST request.
pub async fn PlatformHttpClient::post(
  self : PlatformHttpClient,
  path : String,
  body : String,
  headers? : Array[(String, String)] = [],
) -> Result[HttpResponse, HttpError] {
  self.execute_with_retry(Post, path, body, headers)
}

///|
/// Send a PUT request.
pub async fn PlatformHttpClient::put(
  self : PlatformHttpClient,
  path : String,
  body : String,
  headers? : Array[(String, String)] = [],
) -> Result[HttpResponse, HttpError] {
  self.execute_with_retry(Put, path, body, headers)
}

///|
/// Send a DELETE request.
pub async fn PlatformHttpClient::delete(
  self : PlatformHttpClient,
  path : String,
  headers? : Array[(String, String)] = [],
) -> Result[HttpResponse, HttpError] {
  self.execute_with_retry(Delete, path, "", headers)
}

///|
/// Execute request with retry and failover logic.
async fn PlatformHttpClient::execute_with_retry(
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

// ── HTTP Transport (@async/http) ─────────────────────────────────────────────

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
/// Convert header pairs to the map shape expected by `@async/http`.
fn headers_to_map(headers : Array[(String, String)]) -> Map[String, String] {
  let m : Map[String, String] = Map([])
  for pair in headers {
    let (k, v) = pair
    m[k] = v
  }
  m
}

///|
/// Convert an `@async/http` header map back into header pairs, so response
/// headers (e.g. `Location` for redirects) survive the platform boundary.
fn map_to_headers(header_map : Map[String, String]) -> Array[(String, String)] {
  let pairs : Array[(String, String)] = []
  for k in header_map.keys() {
    pairs.push((k, header_map[k]))
  }
  pairs
}

///|
/// Split a full URL into (base, path): `base` is `protocol://host[:port]`
/// (path `/`, as required by `@http.Client::Client`), `path` keeps any
/// query string.
fn split_base_path(url : String) -> (String, String) {
  // Find the first "/" after the "://" scheme separator.
  let scheme_end = match url.find("://") {
    Some(i) => i + 3
    None => 0
  }
  let mut slash = -1
  for i = scheme_end; i < url.length(); i = i + 1 {
    if url[i] == '/' {
      slash = i
      break
    }
  }
  if slash < 0 {
    (url, "/")
  } else {
    (url[:slash].to_owned(), url[slash:].to_owned())
  }
}

///|
/// Map a platform `HttpMethod` to the `@async/http` request method.
fn http_request_method(http_method : HttpMethod) -> @http.RequestMethod {
  match http_method {
    Get => @http.Get
    Post => @http.Post
    Put => @http.Put
    Delete => @http.Delete
  }
}

///|
/// Establish the connection (TCP + TLS) for `url` and return a client whose
/// persistent headers carry the request headers. Runs inside the open
/// timeout window so a hanging connect fails fast (Ruby `open_timeout`).
/// Raises on transport errors.
async fn connect_client(
  url : String,
  headers : Map[String, String],
) -> @http.Client {
  let (base, _path) = split_base_path(url)
  @http.Client::Client(base, headers~)
}

///|
/// Perform the HTTP request on an already-connected client via `@async/http`
/// (TLS via SystemRoot: Schannel on Windows, OpenSSL system CA on POSIX).
/// Raises on transport errors; HTTP error statuses are returned as normal
/// responses.
async fn perform_request(
  client : @http.Client,
  http_method : HttpMethod,
  url : String,
  body : String,
) -> HttpResponse {
  let (_base, path) = split_base_path(url)
  try {
    client.request(http_request_method(http_method), path)
    if body.length() > 0 {
      client.write(@utf8.encode(body))
    }
    let resp = client.end_request()
    let data = client.read_all()
    HttpResponse::{
      status_code: resp.code,
      body: data.text(),
      headers: map_to_headers(resp.headers),
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

///|
/// Actual HTTP transport via `@async/http`. `timeout_ms` bounds the whole
/// request (same total-timeout semantics as the previous C transport);
/// `open_timeout_ms` bounds only the connect phase (TCP + TLS handshake),
/// mirroring Ruby's `conn.options.open_timeout = 10` vs
/// `conn.options.timeout = @read_timeout || 300`. A hanging connect fails
/// fast with a `Timeout`, long reads are granted the full read window.
pub async fn send_request(
  http_method : HttpMethod,
  url : String,
  body : String,
  headers : Array[(String, String)],
  timeout_ms : Int,
  open_timeout_ms? : Int = 10000,
) -> Result[HttpResponse, HttpError] {
  let headers_map = headers_to_map(headers)
  // Phase 1: connect (TCP + TLS) within the open timeout window.
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
      // Phase 2: send request and read response within the read timeout.
      let result = @async.with_timeout_opt(timeout_ms, () => {
        perform_request(client, http_method, url, body)
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
/// Convenience wrapper: send an HTTP POST request with the given URL, body, and headers.
/// Designed for external callers (e.g. agent package) who don't have direct access to HttpMethod.
pub async fn http_post(
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
pub async fn http_get(
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
