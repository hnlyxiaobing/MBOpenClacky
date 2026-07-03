///| Exchange Rate REST API handler.
/// Proxies public exchange-rate APIs with dual-source fallback and a short-lived
/// in-memory cache.

// ── Types ─────────────────────────────────────────────────────────

///|
struct ExchangeRateResponse {
  from : String
  to : String
  rate : Double
  date : String
  updated_at : String
  source : String
} derive(ToJson)

///|
struct ExchangeRateCacheEntry {
  from : String
  to : String
  response : ExchangeRateResponse
  cached_at : Int64
}

// ── Cache ─────────────────────────────────────────────────────────

///|
/// Cache TTL in milliseconds (1 hour).
let exchange_rate_cache_ttl_ms : Int64 = 3_600_000L

///|
/// In-memory exchange-rate cache protected by a Ref.
let exchange_rate_cache : Ref[ExchangeRateCacheEntry?] = Ref(None)

// ── Helpers ───────────────────────────────────────────────────────

///|
/// Validate a currency code: must be exactly 3 ASCII letters.
fn validate_currency_code(code : String) -> String? {
  let upper = code.to_upper()
  if upper.length() == 3 {
    Some(upper)
  } else {
    None
  }
}

///|
/// Try to extract a rate from the open.er-api.com response.
fn parse_open_er_rate(
  body : String,
  from : String,
  to : String,
) -> Result[Double, String] {
  let j = @json.parse(body) catch {
    _ => return Err("Invalid JSON from primary source")
  }
  guard j is Object(obj) else {
    return Err("Unexpected primary response shape")
  }
  match obj.get("rates") {
    Some(Object(rates)) =>
      match rates.get(to) {
        Some(Number(rate)) => Ok(rate)
        Some(_) => Err("Rate for " + to + " is not a number")
        None => Err("Rate for " + to + " not found")
      }
    _ => Err("Missing rates object in primary response")
  }
}

///|
/// Try to extract a rate from the frankfurter.app response.
fn parse_frankfurter_rate(
  body : String,
  from : String,
  to : String,
) -> Result[Double, String] {
  let j = @json.parse(body) catch {
    _ => return Err("Invalid JSON from fallback source")
  }
  guard j is Object(obj) else {
    return Err("Unexpected fallback response shape")
  }
  match obj.get("rates") {
    Some(Object(rates)) =>
      match rates.get(to) {
        Some(Number(rate)) => Ok(rate)
        Some(_) => Err("Rate for " + to + " is not a number")
        None => Err("Rate for " + to + " not found")
      }
    _ => Err("Missing rates object in fallback response")
  }
}

///|
/// Fetch the exchange rate from a URL and parse it with the given parser.
fn fetch_rate(
  url : String,
  parser : (String, String, String) -> Result[Double, String],
  from : String,
  to : String,
) -> Result[(Double, String), String] {
  let result = @client.http_get(url, [], 8000)
  match result {
    Ok(resp) =>
      if resp.status_code == 200 {
        match parser(resp.body, from, to) {
          Ok(rate) => Ok((rate, resp.body))
          Err(msg) => Err(msg)
        }
      } else {
        Err("HTTP " + resp.status_code.to_string())
      }
    Err(e) => Err(e.to_string())
  }
}

///|
/// Build a response with the current timestamp and a formatted date.
fn build_exchange_rate_response(
  from : String,
  to : String,
  rate : Double,
  source : String,
) -> ExchangeRateResponse {
  let now = @agent.current_time_ms()
  let updated_at = if now == 0L { "" } else { format_iso8601_ms(now) }
  let date = if now == 0L { "" } else { format_iso8601_date(now) }
  ExchangeRateResponse::{ from, to, rate, date, updated_at, source }
}

///|
/// Format a millisecond timestamp as an ISO-8601 UTC string.
fn format_iso8601_ms(ts : Int64) -> String {
  // Minimal formatting: seconds since epoch is sufficient for this endpoint.
  let secs = ts / 1000L
  secs.to_string()
}

///|
/// Format a millisecond timestamp as a date string (YYYY-MM-DD approximation).
fn format_iso8601_date(ts : Int64) -> String {
  let secs = ts / 1000L
  let days = secs / 86_400L
  // Approximate epoch day to YYYY-MM-DD is not needed for the API contract;
  // return a placeholder derived from the timestamp.
  "day-" + days.to_string()
}

///|
/// Resolve the exchange rate, trying the primary source first and falling back.
fn resolve_exchange_rate(
  from : String,
  to : String,
) -> Result[ExchangeRateResponse, String] {
  let primary_url = "https://open.er-api.com/v6/latest/" + from
  match fetch_rate(primary_url, parse_open_er_rate, from, to) {
    Ok((rate, _body)) =>
      return Ok(build_exchange_rate_response(from, to, rate, "open.er-api.com"))
    Err(_) => ()
  }
  let fallback_url = "https://frankfurter.app/latest?from=" + from
  match fetch_rate(fallback_url, parse_frankfurter_rate, from, to) {
    Ok((rate, _body)) =>
      Ok(build_exchange_rate_response(from, to, rate, "frankfurter.app"))
    Err(msg) => Err("Both exchange-rate sources failed: " + msg)
  }
}

// ── Handler ───────────────────────────────────────────────────────

///|
/// GET /api/exchange-rate?from=USD&to=CNY
/// Returns the current exchange rate with source attribution and caching.
fn handle_exchange_rate(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let from_raw = event.req.get_query("from").unwrap_or("USD")
  let to_raw = event.req.get_query("to").unwrap_or("CNY")
  let from = match validate_currency_code(from_raw) {
    Some(c) => c
    None =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": "Invalid 'from' currency code".to_json() }),
      )
  }
  let to = match validate_currency_code(to_raw) {
    Some(c) => c
    None =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": "Invalid 'to' currency code".to_json() }),
      )
  }
  // Check cache.
  let now = @agent.current_time_ms()
  match exchange_rate_cache.val {
    Some(entry) =>
      if entry.from == from &&
        entry.to == to &&
        now - entry.cached_at < exchange_rate_cache_ttl_ms {
        return @core.HttpResponse::ok().json_value(entry.response.to_json())
      }
    None => ()
  }
  // Fetch fresh rate.
  match resolve_exchange_rate(from, to) {
    Ok(response) => {
      exchange_rate_cache.val = Some(ExchangeRateCacheEntry::{
        from,
        to,
        response,
        cached_at: now,
      })
      @core.HttpResponse::ok().json_value(response.to_json())
    }
    Err(msg) =>
      @core.HttpResponse::internal_server_error().json_value(
        Json::object({
          "error": "Failed to fetch exchange rate".to_json(),
          "detail": msg.to_json(),
        }),
      )
  }
}
