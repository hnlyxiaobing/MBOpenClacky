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
priv struct ExchangeRateCacheEntry {
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
  _from : String,
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
        Some(Number(rate, ..)) => Ok(rate)
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
  _from : String,
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
        Some(Number(rate, ..)) => Ok(rate)
        Some(_) => Err("Rate for " + to + " is not a number")
        None => Err("Rate for " + to + " not found")
      }
    _ => Err("Missing rates object in fallback response")
  }
}

///|
/// Fetch the exchange rate from a URL and parse it with the given parser.
async fn fetch_rate(
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
    Err(e) => Err(@debug.to_string(e))
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
/// Check if a year is a leap year (Gregorian calendar).
fn is_leap_year(year : Int) -> Bool {
  (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
}

///|
/// Number of days in a given month (1-12) for a specific year.
fn days_in_month(year : Int, month : Int) -> Int {
  match month {
    1 | 3 | 5 | 7 | 8 | 10 | 12 => 31
    4 | 6 | 9 | 11 => 30
    2 => if is_leap_year(year) { 29 } else { 28 }
    _ => 30
  }
}

///|
/// Convert epoch days (since 1970-01-01) to (year, month, day) in UTC.
fn epoch_days_to_ymd(days_in : Int) -> (Int, Int, Int) {
  let mut days = days_in
  let mut year = 1970
  while true {
    let diy = if is_leap_year(year) { 366 } else { 365 }
    if days < diy {
      break
    }
    days = days - diy
    year = year + 1
  }
  let mut month = 1
  while month <= 12 {
    let dim = days_in_month(year, month)
    if days < dim {
      break
    }
    days = days - dim
    month = month + 1
  }
  (year, month, days + 1)
}

///|
/// Left-pad a number to 4 digits with leading zeros.
fn pad4(n : Int) -> String {
  let s = n.to_string()
  let mut result = s
  while result.length() < 4 {
    result = "0" + result
  }
  result
}

///|
/// Format a millisecond timestamp as an RFC2822 UTC string.
/// Example: "Sun, 26 Jul 2026 00:02:32 +0000"
fn format_iso8601_ms(ts : Int64) -> String {
  let secs = ts / 1000L
  let days = (secs / 86_400L).to_int()
  let remainder = (secs % 86_400L).to_int()
  let hour = remainder / 3600
  let min = remainder % 3600 / 60
  let sec = remainder % 60
  let (year, month, day) = epoch_days_to_ymd(days)
  // 1970-01-01 was a Thursday; 0=Sun in the weekday name table.
  let weekday = ((days + 4) % 7 + 7) % 7
  let weekday_names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
  let month_names = [
    "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov",
    "Dec",
  ]
  weekday_names[weekday] +
  ", " +
  pad2(day) +
  " " +
  month_names[month - 1] +
  " " +
  pad4(year) +
  " " +
  pad2(hour) +
  ":" +
  pad2(min) +
  ":" +
  pad2(sec) +
  " +0000"
}

///|
/// Format a millisecond timestamp as a YYYY-MM-DD UTC date string.
fn format_iso8601_date(ts : Int64) -> String {
  let secs = ts / 1000L
  let days = (secs / 86_400L).to_int()
  let (year, month, day) = epoch_days_to_ymd(days)
  pad4(year) + "-" + pad2(month) + "-" + pad2(day)
}

///|
/// Resolve the exchange rate, trying the primary source first and falling back.
async fn resolve_exchange_rate(
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
async fn handle_exchange_rate(
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
