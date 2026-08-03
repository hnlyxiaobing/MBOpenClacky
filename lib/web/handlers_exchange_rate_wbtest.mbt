///| White-box tests for Exchange Rate API handler.

///|
fn make_rate_event(url : String) -> @crescent.Event {
  {
    req: @crescent.HttpRequest::HttpRequest(Get, url, Map([]), raw_body=b""),
    res: @crescent.HttpResponse::HttpResponse(status_code=OK),
    params: Map([]),
  }
}

///|
fn make_rate_server_ref() -> Ref[WebServer] {
  Ref(WebServer::new(@config.AgentConfig::default(), None))
}

///|
fn rate_response_json(resp : @core.HttpResponse) -> Json {
  @json.parse(@utf8.decode(resp.raw_body)) catch {
    _ => Json::object(Map([]))
  }
}

// ── Validation ────────────────────────────────────────────────────

///|
async test "exchange rate rejects invalid from code" {
  let server_ref = make_rate_server_ref()
  let event = make_rate_event("/api/exchange-rate?from=US&to=CNY")
  let resp = handle_exchange_rate(server_ref, event)
  @debug.assert_eq(resp.status_code.to_int(), 400)
}

///|
async test "exchange rate rejects invalid to code" {
  let server_ref = make_rate_server_ref()
  let event = make_rate_event("/api/exchange-rate?from=USD&to=CN")
  let resp = handle_exchange_rate(server_ref, event)
  @debug.assert_eq(resp.status_code.to_int(), 400)
}

///|
async test "exchange rate normalizes currency codes to uppercase" {
  // We can't assert the response body without network, but we can verify
  // invalid codes are rejected and valid mixed-case codes are accepted.
  let server_ref = make_rate_server_ref()
  let event = make_rate_event("/api/exchange-rate?from=usd&to=cny")
  let resp = handle_exchange_rate(server_ref, event)
  // Either 200 (cache/network success) or 500 (network failure), never 400.
  assert_true(resp.status_code.to_int() != 400)
}

// ── Parsing ───────────────────────────────────────────────────────

///|
test "parse open.er-api rate extracts rate" {
  let body = "{\"rates\":{\"CNY\":7.25,\"EUR\":0.92}}"
  let result = parse_open_er_rate(body, "USD", "CNY")
  @debug.assert_eq(result, Ok(7.25))
}

///|
test "parse frankfurter rate extracts rate" {
  let body = "{\"rates\":{\"CNY\":7.25,\"EUR\":0.92}}"
  let result = parse_frankfurter_rate(body, "USD", "CNY")
  @debug.assert_eq(result, Ok(7.25))
}

///|
test "parse open.er-api rate returns error for missing currency" {
  let body = "{\"rates\":{\"EUR\":0.92}}"
  let result = parse_open_er_rate(body, "USD", "CNY")
  assert_true(result is Err(_))
}

// ── Caching ───────────────────────────────────────────────────────

///|
async test "exchange rate returns cached value when available" {
  let cached = ExchangeRateResponse::{
    from: "USD",
    to: "CNY",
    rate: 7.77,
    date: "2026-07-03",
    updated_at: "1000",
    source: "test-cache",
  }
  exchange_rate_cache.val = Some(ExchangeRateCacheEntry::{
    from: "USD",
    to: "CNY",
    response: cached,
    cached_at: @agent.current_time_ms(),
  })
  let server_ref = make_rate_server_ref()
  let resp = handle_exchange_rate(
    server_ref,
    make_rate_event("/api/exchange-rate?from=USD&to=CNY"),
  )
  @debug.assert_eq(resp.status_code.to_int(), 200)
  let j = rate_response_json(resp)
  guard! j is Object(obj)
  @debug.assert_eq(obj.get("rate"), Some(7.77.to_json()))
  @debug.assert_eq(obj.get("source"), Some("test-cache".to_json()))
  // Reset cache so subsequent tests are not affected.
  exchange_rate_cache.val = None
}

// ── Date formatting (web-ui2-07) ───────────────────────────────────

///|
test "format_iso8601_date: fixed timestamp -> YYYY-MM-DD" {
  // 1785024152000 ms = 2026-07-26 00:02:32 UTC
  @debug.assert_eq(format_iso8601_date(1785024152000L), "2026-07-26")
}

///|
test "format_iso8601_ms: fixed timestamp -> RFC2822" {
  // 1785024152000 ms = 2026-07-26 00:02:32 UTC (Sunday)
  @debug.assert_eq(
    format_iso8601_ms(1785024152000L),
    "Sun, 26 Jul 2026 00:02:32 +0000",
  )
}

///|
test "format_iso8601_date: leap day Feb 29" {
  // 1709164800000 ms = 2024-02-29 00:00:00 UTC
  @debug.assert_eq(format_iso8601_date(1709164800000L), "2024-02-29")
}

///|
test "format_iso8601_date: year boundary Dec 31 -> Jan 1" {
  // 1767139200000 ms = 2025-12-31 00:00:00 UTC
  @debug.assert_eq(format_iso8601_date(1767139200000L), "2025-12-31")
  // 1767225600000 ms = 2026-01-01 00:00:00 UTC
  @debug.assert_eq(format_iso8601_date(1767225600000L), "2026-01-01")
}

///|
test "format_iso8601_ms: RFC2822 weekday for leap day" {
  // 1709164800000 ms = 2024-02-29 00:00:00 UTC (Thursday)
  @debug.assert_eq(
    format_iso8601_ms(1709164800000L),
    "Thu, 29 Feb 2024 00:00:00 +0000",
  )
}
