///|
/// API Key authentication middleware with enhanced security.
/// Supports Bearer header, query parameter, and cookie fallback.
/// Implements IP-based rate limiting and a public-path allowlist.
/// Loopback bypass is opt-in (dev only) and disabled by default.

///|
/// Constant-time string comparison to prevent timing attacks.
/// Compares all bytes regardless of where differences occur.
pub fn secure_string_compare(a : String, b : String) -> Bool {
  if a.length() != b.length() {
    return false
  }
  let mut diff : Int = 0
  for i = 0; i < a.length(); i = i + 1 {
    diff = diff | (a[i].to_int() ^ b[i].to_int())
  }
  diff == 0
}

///|
/// Check if an IP address is a loopback address.
pub fn is_loopback_ip(ip : String) -> Bool {
  ip == "127.0.0.1" || ip == "::1" || ip == "localhost" || ip == "[::1]"
}

///|
/// IP rate limiter state.
/// Tracks failed authentication attempts per IP address.
pub(all) struct IpRateLimiter {
  mut failures : Map[String, RateLimitEntry]
  max_failures : Int
  window_seconds : Int64
}

///|
/// Rate limit entry for a single IP.
pub(all) struct RateLimitEntry {
  mut count : Int
  mut first_failure_at : Int64
}

///|
/// Create a new rate limiter with the given thresholds.
pub fn IpRateLimiter::new(
  max_failures? : Int = 10,
  window_seconds? : Int64 = 300L,
) -> IpRateLimiter {
  { failures: Map([]), max_failures, window_seconds }
}

///|
/// Check if an IP is currently rate-limited.
pub fn IpRateLimiter::is_limited(
  self : IpRateLimiter,
  ip : String,
  now_ms : Int64,
) -> Bool {
  guard self.failures.contains(ip) else { return false }
  let entry = self.failures[ip]
  let elapsed = (now_ms - entry.first_failure_at) / 1000L
  if elapsed >= self.window_seconds {
    self.failures.remove(ip)
    false
  } else {
    entry.count >= self.max_failures
  }
}

///|
/// Record a failed authentication attempt for an IP.
pub fn IpRateLimiter::record_failure(
  self : IpRateLimiter,
  ip : String,
  now_ms : Int64,
) -> Unit {
  if self.failures.contains(ip) {
    let entry = self.failures[ip]
    let elapsed = (now_ms - entry.first_failure_at) / 1000L
    if elapsed >= self.window_seconds {
      entry.count = 1
      entry.first_failure_at = now_ms
    } else {
      entry.count = entry.count + 1
    }
  } else {
    self.failures[ip] = { count: 1, first_failure_at: now_ms }
  }
}

///|
/// Clear failure record for an IP after successful auth.
pub fn IpRateLimiter::record_success(self : IpRateLimiter, ip : String) -> Unit {
  self.failures.remove(ip)
}

///|
/// Get the remaining seconds before rate limit expires.
pub fn IpRateLimiter::retry_after(
  self : IpRateLimiter,
  ip : String,
  now_ms : Int64,
) -> Int {
  guard self.failures.contains(ip) else { return 0 }
  let entry = self.failures[ip]
  let elapsed = (now_ms - entry.first_failure_at) / 1000L
  let remaining = self.window_seconds - elapsed
  if remaining <= 0L {
    0
  } else {
    remaining.to_int()
  }
}

///|
/// Extract client IP from request, checking X-Forwarded-For, X-Real-IP, then remote address.
fn extract_client_ip(req : @core.HttpRequest) -> String {
  match req.get_header("X-Forwarded-For") {
    Some(ip) => {
      let parts = ip.split(",").collect()
      if parts.length() > 0 {
        parts[0].trim_start().trim_end().to_owned()
      } else {
        ip
      }
    }
    None =>
      match req.get_header("X-Real-IP") {
        Some(ip) => ip
        None => "unknown"
      }
  }
}

///|
/// Extract API key from multiple sources in priority order:
/// 1. Authorization: Bearer <key> header
/// 2. X-API-Key header
/// 3. ?access_key=<key> query parameter
/// 4. clacky_access_key cookie
fn extract_api_key(req : @core.HttpRequest) -> String? {
  // 1. Authorization: Bearer <key>
  let bearer_result = match req.get_header("Authorization") {
    Some(auth) => {
      let trimmed = auth.trim_start()
      if trimmed.length() > 7 {
        let prefix = trimmed[:7].to_owned().to_lower()
        if prefix == "bearer " {
          let key = trimmed[7:].trim_start().trim_end().to_owned()
          if key.length() > 0 {
            Some(key)
          } else {
            None
          }
        } else {
          None
        }
      } else {
        None
      }
    }
    None => None
  }
  match bearer_result {
    Some(_) => bearer_result
    None =>
      // 2. X-API-Key header
      match req.get_header("X-API-Key") {
        Some(_) => req.get_header("X-API-Key")
        None =>
          // 3. Query parameter ?access_key=
          match req.get_query("access_key") {
            Some(_) => req.get_query("access_key")
            None =>
              // 4. Cookie: clacky_access_key
              match req.get_cookie("clacky_access_key") {
                Some(item) => Some(item.value)
                None => None
              }
          }
      }
  }
}

///|
/// Public endpoints that never require authentication.
/// - /health: monitoring probes need credential-less access
/// - GET /api/version: version query (note: POST /api/version/upgrade is NOT public)
pub fn is_public_path(http_method : String, path : String) -> Bool {
  if path == "/health" {
    return true
  }
  http_method == "GET" && path == "/api/version"
}

///|
/// Creates enhanced authentication middleware with:
/// - Constant-time key comparison
/// - Multi-method auth (Bearer, X-API-Key header, query param, cookie)
/// - IP rate limiting (10 failures / 300s window)
/// - Public-path allowlist (/health, GET /api/version)
/// - Optional loopback bypass (dev only, default OFF)
///
/// SECURITY: `client_ip` is derived from X-Forwarded-For / X-Real-IP request
/// headers, which are client-controlled. It is therefore used ONLY for rate
/// limiting and logging — never as an authentication decision input, unless
/// `allow_loopback_bypass` is explicitly enabled (development convenience,
/// NOT a security boundary: a remote client can forge the header).
pub fn auth_middleware(
  api_key : String,
  allow_loopback_bypass? : Bool = false,
) -> @crescent.Middleware {
  let limiter = IpRateLimiter::new()
  let mw : @crescent.Middleware = (event, next) => {
    let req = event.req
    let path = req.path()
    let http_method = req.method_string()

    // Public endpoint allowlist: no auth required
    if is_public_path(http_method, path) {
      return next()
    }
    let client_ip = extract_client_ip(req)
    let now = @async.now()

    // Optional loopback bypass (dev only; disabled by default because the
    // client IP comes from forgeable headers)
    if allow_loopback_bypass && is_loopback_ip(client_ip) {
      return next()
    }

    // Rate limit check
    if limiter.is_limited(client_ip, now) {
      let retry = limiter.retry_after(client_ip, now)
      return @core.HttpResponse::HttpResponse(
          status_code=@core.StatusCode::TooManyRequests,
        )
        .json_value(
          Json::object({
            "error": Json::object({
              "status": (429).to_json(),
              "message": "Too many failed authentication attempts".to_json(),
              "retry_after": retry.to_json(),
            }),
          }),
        )
        .header("Retry-After", retry.to_string())
        .to_responder()
    }

    // Extract key from any supported source
    match extract_api_key(req) {
      Some(provided_key) =>
        if secure_string_compare(provided_key, api_key) {
          limiter.record_success(client_ip)
          next()
        } else {
          limiter.record_failure(client_ip, now)
          @core.HttpResponse::unauthorized()
          .json_value(
            Json::object({
              "error": Json::object({
                "status": (401).to_json(),
                "message": "Invalid API key".to_json(),
                "hint": "Provide key via Authorization: Bearer, X-API-Key header, ?access_key= query, or clacky_access_key cookie".to_json(),
              }),
            }),
          )
          .to_responder()
        }
      None => {
        limiter.record_failure(client_ip, now)
        @core.HttpResponse::unauthorized()
        .json_value(
          Json::object({
            "error": Json::object({
              "status": (401).to_json(),
              "message": "Missing API key".to_json(),
              "hint": "Provide key via Authorization: Bearer, X-API-Key header, ?access_key= query, or clacky_access_key cookie".to_json(),
            }),
          }),
        )
        .to_responder()
      }
    }
  }
  mw
}

///|
/// Cache control middleware.
/// Sets Cache-Control headers on the response before the handler runs.
/// API responses get "no-store"; static assets get "public, max-age=3600".
pub fn cache_control_middleware() -> @crescent.Middleware {
  let mw : @crescent.Middleware = (event, next) => {
    let url = event.req.url
    // Set cache headers on the response before calling next
    if url.has_prefix("/api/") {
      event.res.headers["Cache-Control"] = "no-store"
    } else if !url.has_suffix(".html") && !url.has_suffix("/") {
      event.res.headers["Cache-Control"] = "public, max-age=3600"
    }
    next()
  }
  mw
}
