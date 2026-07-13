///| White-box tests for Exchange Rate API handler.

///|
fn make_rate_event(url : String) -> @crescent.Event {
  {
    req: @crescent.HttpRequest::http_request(Get, url, {}, raw_body=b""),
    res: @crescent.HttpResponse::http_response(status_code=OK),
    params: {},
  }
}

///|
fn make_rate_server_ref() -> Ref[WebServer] {
  Ref(WebServer::new(@config.AgentConfig::default(), None))
}

///|
fn rate_response_json(resp : @core.HttpResponse) -> Json {
  @json.parse(@utf8.decode(resp.raw_body)) catch {
    _ => Json::object({})
  }
}

// ── Validation ────────────────────────────────────────────────────

///|
test "exchange rate rejects invalid from code" {
  let server_ref = make_rate_server_ref()
  let event = make_rate_event("/api/exchange-rate?from=US&to=CNY")
  let resp = handle_exchange_rate(server_ref, event)
  @debug.assert_eq(resp.status_code.to_int(), 400)
}

///|
test "exchange rate rejects invalid to code" {
  let server_ref = make_rate_server_ref()
  let event = make_rate_event("/api/exchange-rate?from=USD&to=CN")
  let resp = handle_exchange_rate(server_ref, event)
  @debug.assert_eq(resp.status_code.to_int(), 400)
}

///|
test "exchange rate normalizes currency codes to uppercase" {
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
test "exchange rate returns cached value when available" {
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
  guard j is Object(obj)
  @debug.assert_eq(obj.get("rate"), Some(7.77.to_json()))
  @debug.assert_eq(obj.get("source"), Some("test-cache".to_json()))
  // Reset cache so subsequent tests are not affected.
  exchange_rate_cache.val = None
}
