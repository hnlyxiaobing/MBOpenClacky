///| White-box tests for the auth middleware (loopback bypass security).

///|
fn make_req(
  meth : @core.HttpMethod,
  url : String,
  headers : Map[String, String],
) -> @core.HttpRequest {
  @core.HttpRequest::HttpRequest(meth, url, headers, raw_body=b"")
}

// ── is_public_path ────────────────────────────────────────────────

///|
test "health is public" {
  assert_true(is_public_path("GET", "/health"))
  assert_true(is_public_path("POST", "/health"))
}

///|
test "get api version is public" {
  assert_true(is_public_path("GET", "/api/version"))
}

///|
test "version upgrade is not public" {
  assert_false(is_public_path("POST", "/api/version/upgrade"))
  assert_false(is_public_path("GET", "/api/version/upgrade"))
}

///|
test "post api version is not public" {
  assert_false(is_public_path("POST", "/api/version"))
}

///|
test "other api paths are not public" {
  assert_false(is_public_path("GET", "/api/sessions"))
  assert_false(is_public_path("GET", "/api/info"))
}

// ── is_loopback_ip ────────────────────────────────────────────────

///|
test "loopback ip variants" {
  assert_true(is_loopback_ip("127.0.0.1"))
  assert_true(is_loopback_ip("::1"))
  assert_true(is_loopback_ip("localhost"))
  assert_true(is_loopback_ip("[::1]"))
  assert_false(is_loopback_ip("192.168.1.1"))
  assert_false(is_loopback_ip("unknown"))
  assert_false(is_loopback_ip(""))
}

// ── extract_client_ip ─────────────────────────────────────────────

///|
test "extract ip from x-forwarded-for first entry" {
  let req = make_req(Get, "/api/info", {
    "X-Forwarded-For": "203.0.113.7, 10.0.0.1",
  })
  @debug.assert_eq(extract_client_ip(req), "203.0.113.7")
}

///|
test "extract ip falls back to x-real-ip" {
  let req = make_req(Get, "/api/info", { "X-Real-IP": "198.51.100.9" })
  @debug.assert_eq(extract_client_ip(req), "198.51.100.9")
}

///|
test "extract ip unknown when no headers" {
  let req = make_req(Get, "/api/info", Map([]))
  @debug.assert_eq(extract_client_ip(req), "127.0.0.1")
}

///|
test "forged xff loopback is still parsed as loopback string" {
  // Documents the forgery vector: a remote client can send this header.
  // Loopback bypass is OFF by default; enable with
  // MBOPENCLACKY_DEV_ALLOW_LOOPBACK=1 for local dev only.
  // When bypass is disabled, a forged X-Forwarded-For header has no effect
  // because the auth middleware requires a valid API key regardless of IP.
  let req = make_req(Get, "/api/info", { "X-Forwarded-For": "127.0.0.1" })
  assert_true(is_loopback_ip(extract_client_ip(req)))
}

// ── secure_string_compare ─────────────────────────────────────────

///|
test "secure compare equal and unequal" {
  assert_true(secure_string_compare("abc123", "abc123"))
  assert_false(secure_string_compare("abc123", "abc124"))
  assert_false(secure_string_compare("abc", "abc123"))
  assert_true(secure_string_compare("", ""))
}

// ── IpRateLimiter ─────────────────────────────────────────────────

///|
test "rate limiter blocks after max failures" {
  let limiter = IpRateLimiter::new(max_failures=3, window_seconds=300L)
  let ip = "203.0.113.5"
  assert_false(limiter.is_limited(ip, 0L))
  limiter.record_failure(ip, 0L)
  limiter.record_failure(ip, 1000L)
  assert_false(limiter.is_limited(ip, 2000L))
  limiter.record_failure(ip, 2000L)
  assert_true(limiter.is_limited(ip, 3000L))
}

///|
test "rate limiter window expiry resets" {
  let limiter = IpRateLimiter::new(max_failures=1, window_seconds=10L)
  let ip = "203.0.113.6"
  limiter.record_failure(ip, 0L)
  assert_true(limiter.is_limited(ip, 5000L))
  // After window elapses, no longer limited
  assert_false(limiter.is_limited(ip, 11_000L))
}

///|
test "rate limiter success clears failures" {
  let limiter = IpRateLimiter::new(max_failures=1, window_seconds=300L)
  let ip = "203.0.113.8"
  limiter.record_failure(ip, 0L)
  assert_true(limiter.is_limited(ip, 1000L))
  limiter.record_success(ip)
  assert_false(limiter.is_limited(ip, 2000L))
}

// ── auth_middleware behavior ─────────────────────────────────────
// These tests verify the security-critical default: loopback bypass is OFF,
// so a forged X-Forwarded-For: 127.0.0.1 header cannot bypass authentication.

///|
fn make_event(req : @core.HttpRequest) -> @crescent.Event {
  {
    req,
    res: @core.HttpResponse(status_code=@core.StatusCode::OK),
    params: Map([]),
  }
}

///|
fn make_next_ok() -> @crescent.MiddlewareNext {
  () => @core.HttpResponse::ok().to_responder()
}

///|
async test "auth middleware rejects forged loopback when bypass is off (default)" {
  let mw = auth_middleware("secret-key")
  let req = make_req(Get, "/api/info", { "X-Forwarded-For": "127.0.0.1" })
  let event = make_event(req)
  let responder = mw(event, make_next_ok())
  responder.options(event.res)
  @debug.assert_eq(event.res.status_code, @core.StatusCode::Unauthorized)
}

///|
async test "auth middleware allows loopback when bypass is explicitly on" {
  let mw = auth_middleware("secret-key", allow_loopback_bypass=true)
  let req = make_req(Get, "/api/info", { "X-Forwarded-For": "127.0.0.1" })
  let event = make_event(req)
  let responder = mw(event, make_next_ok())
  responder.options(event.res)
  @debug.assert_eq(event.res.status_code, @core.StatusCode::OK)
}

///|
async test "auth middleware accepts valid Bearer token" {
  let mw = auth_middleware("secret-key")
  let req = make_req(Get, "/api/info", { "Authorization": "Bearer secret-key" })
  let event = make_event(req)
  let responder = mw(event, make_next_ok())
  responder.options(event.res)
  @debug.assert_eq(event.res.status_code, @core.StatusCode::OK)
}

///|
async test "auth middleware rejects invalid Bearer token" {
  let mw = auth_middleware("secret-key")
  let req = make_req(Get, "/api/info", { "Authorization": "Bearer wrong-key" })
  let event = make_event(req)
  let responder = mw(event, make_next_ok())
  responder.options(event.res)
  @debug.assert_eq(event.res.status_code, @core.StatusCode::Unauthorized)
}

///|
async test "auth middleware rejects request with no key and no bypass" {
  let mw = auth_middleware("secret-key")
  let req = make_req(Get, "/api/info", Map([]))
  let event = make_event(req)
  let responder = mw(event, make_next_ok())
  responder.options(event.res)
  @debug.assert_eq(event.res.status_code, @core.StatusCode::Unauthorized)
}

///|
async test "auth middleware allows public path without key" {
  let mw = auth_middleware("secret-key")
  let req = make_req(Get, "/health", Map([]))
  let event = make_event(req)
  let responder = mw(event, make_next_ok())
  responder.options(event.res)
  @debug.assert_eq(event.res.status_code, @core.StatusCode::OK)
}
