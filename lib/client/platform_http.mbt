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
} derive(Show, Eq)

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
pub struct HttpResponse {
  status_code : Int
  body : String
  headers : Array[(String, String)]
} derive(Show)

///|
/// HTTP request method.
pub enum HttpMethod {
  Get
  Post
  Put
  Delete
} derive(Show)

///|
/// HTTP request error types.
pub enum HttpError {
  Timeout(String)
  ConnectionFailed(String)
  ServerError(Int, String)
  ClientError(Int, String)
  AllHostsFailed(String)
} derive(Show)

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
  method : HttpMethod,
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
      method,
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
        if not(is_retryable(last_error)) {
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
          method,
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
            if not(is_retryable(last_error)) {
              return Err(last_error)
            }
          }
        }
      }
    }
  }
  Err(AllHostsFailed("All hosts exhausted after retries: \{last_error}"))
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
/// Actual HTTP transport (stub - returns ConnectionFailed until wired).
fn send_request(
  _method : HttpMethod,
  _url : String,
  _body : String,
  _headers : Array[(String, String)],
  _timeout_ms : Int,
) -> Result[HttpResponse, HttpError] {
  Err(ConnectionFailed("HTTP transport not yet wired"))
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
    host[host.length() - 1:].to_string() == "/" {
    host[:host.length() - 1].to_string()
  } else {
    host
  }
  let trimmed_path = if path.length() > 0 && path[:1].to_string() == "/" {
    path[1:].to_string()
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
