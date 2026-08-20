///| Local-timezone aware time helpers for billing storage.

///| Reference: openclacky/lib/clacky/billing/billing_store.rb

///| (period_start calendar boundaries, month file naming, iso8601

///| timestamps — all computed in the local timezone, spec 21 decision 7).

// ── Local offset ────────────────────────────────────────────────

///|
/// Current local UTC offset in minutes (e.g. +480 for UTC+8).
#cfg(target="native")
extern "C" fn billing_local_offset_minutes_ffi() -> Int = "mbopenclacky_billing_local_offset_minutes"

///|
#cfg(target="native")
fn local_offset_minutes() -> Int {
  billing_local_offset_minutes_ffi()
}

///|
#cfg(not(target="native"))
fn local_offset_minutes() -> Int {
  0
}

///|
/// Local UTC offset in milliseconds.
fn local_offset_ms() -> Int64 {
  local_offset_minutes().to_int64() * 60_000L
}

// ── Civil calendar helpers (Howard Hinnant algorithms) ──────────

///|
/// Days since Unix epoch from a civil date (Hinnant days_from_civil).
fn days_from_civil(year : Int, month : Int, day : Int) -> Int {
  let y = if month <= 2 { year - 1 } else { year }
  let era = (if y >= 0 { y } else { y - 399 }) / 400
  let yoe = y - era * 400
  let mp = if month > 2 { month - 3 } else { month + 9 }
  let doy = (153 * mp + 2) / 5 + day - 1
  let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
  era * 146097 + doe - 719468
}

///|
/// Civil date (year, month, day) from days since Unix epoch
/// (Hinnant civil_from_days).
fn civil_from_days(days : Int) -> (Int, Int, Int) {
  let z = days + 719468
  let era = (if z >= 0 { z } else { z - 146096 }) / 146097
  let doe = z - era * 146097
  let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
  let y = yoe + era * 400
  let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
  let mp = (5 * doy + 2) / 153
  let d = doy - (153 * mp + 2) / 5 + 1
  let m = if mp < 10 { mp + 3 } else { mp - 9 }
  (if m <= 2 { y + 1 } else { y }, m, d)
}

///|
/// Local civil date parts (year, month, day) for an epoch-ms instant.
pub fn ms_to_local_date_parts(ms : Int64) -> (Int, Int, Int) {
  let local_ms = ms + local_offset_ms()
  let days = (local_ms / 86_400_000L).to_int()
  civil_from_days(days)
}

///|
/// Local midnight (epoch ms) of the given civil date.
fn local_midnight_ms(year : Int, month : Int, day : Int) -> Int64 {
  days_from_civil(year, month, day).to_int64() * 86_400_000L - local_offset_ms()
}

///|
/// Local date string "YYYY-MM-DD" for an epoch-ms instant.
pub fn ms_to_local_date_string(ms : Int64) -> String {
  let (y, m, d) = ms_to_local_date_parts(ms)
  "\{y}-\{pad2(m)}-\{pad2(d)}"
}

///|
/// Zero-pad an integer to at least 2 digits.
fn pad2(n : Int) -> String {
  if n < 10 {
    "0\{n}"
  } else {
    n.to_string()
  }
}

// ── Period boundaries (Ruby period_start semantics) ─────────────

///|
/// Calendar-aligned period start in epoch ms (local timezone).
/// Mirrors Ruby BillingStore#period_start:
/// Day = today 00:00, Week = this Monday 00:00 (wday==0 ? 6 : wday-1),
/// Month = 1st 00:00, Year = Jan 1 00:00, All = 0.
pub fn get_period_start_ms(period : TimePeriod) -> Int64 {
  let now_ms = @env.now().reinterpret_as_int64()
  let local_ms = now_ms + local_offset_ms()
  let days = (local_ms / 86_400_000L).to_int()
  let (y, m, d) = civil_from_days(days)
  match period {
    Day => local_midnight_ms(y, m, d)
    Week => {
      // Ruby wday: Sunday=0. Unix day 0 (1970-01-01) is Thursday (wday 4).
      let wday = (days + 4) % 7
      let days_since_monday = if wday == 0 { 6 } else { wday - 1 }
      let (wy, wm, wd) = civil_from_days(days - days_since_monday)
      local_midnight_ms(wy, wm, wd)
    }
    Month => local_midnight_ms(y, m, 1)
    Year => local_midnight_ms(y, 1, 1)
    All => 0L
  }
}

// ── Month file naming ───────────────────────────────────────────

///|
/// Month file name ("YYYY-MM.jsonl", local timezone) for a timestamp.
pub fn month_file_name(ms : Int64) -> String {
  let (y, m, _) = ms_to_local_date_parts(ms)
  "\{y}-\{pad2(m)}.jsonl"
}

///|
/// Parse a "YYYY-MM" month prefix into the epoch ms of its local start,
/// or None if the name does not match the month-file pattern.
pub fn month_file_start_ms(file_name : String) -> Int64? {
  if file_name.length() < 7 {
    return None
  }
  let year = match parse_digits_opt(file_name, 0, 4) {
    Some(v) => v
    None => return None
  }
  let month = match parse_digits_opt(file_name, 5, 7) {
    Some(v) => v
    None => return None
  }
  guard file_name[4] == '-' && month >= 1 && month <= 12 else { return None }
  Some(local_midnight_ms(year, month, 1))
}

///|
/// Parse decimal digits from string slice [start, end), or None if any
/// character is not a digit.
fn parse_digits_opt(s : String, start : Int, end : Int) -> Int? {
  let mut result = 0
  for i = start; i < end; i = i + 1 {
    let c = s[i]
    guard c >= '0' && c <= '9' else { return None }
    result = result * 10 + (c.to_int() - '0'.to_int())
  }
  Some(result)
}

///|
/// Parse a non-negative decimal string into Int64, or None on any
/// non-digit character.
fn parse_int64_opt(s : String) -> Int64? {
  if s.is_empty() {
    return None
  }
  let mut result = 0L
  for c in s {
    guard c >= '0' && c <= '9' else { return None }
    result = result * 10L + (c.to_int() - '0'.to_int()).to_int64()
  }
  Some(result)
}

// ── ISO 8601 serialization ──────────────────────────────────────

///|
/// Format epoch ms as an ISO 8601 local-time string with millisecond
/// precision, e.g. "2026-08-20T12:22:34.567+08:00". Millisecond
/// precision keeps JSON roundtrips lossless (Ruby serializes Time via
/// iso8601; spec 21 decision 7).
pub fn ms_to_iso8601_local(ms : Int64) -> String {
  let offset_min = local_offset_minutes()
  let local_ms = ms + offset_min.to_int64() * 60_000L
  let days = (local_ms / 86_400_000L).to_int()
  let day_ms = local_ms - days.to_int64() * 86_400_000L
  let (y, m, d) = civil_from_days(days)
  let sec_total = (day_ms / 1000L).to_int()
  let millis = (day_ms % 1000L).to_int()
  let hh = sec_total / 3600
  let mi = sec_total % 3600 / 60
  let ss = sec_total % 60
  let sign = if offset_min < 0 { "-" } else { "+" }
  let abs_min = offset_min.abs()
  "\{y}-\{pad2(m)}-\{pad2(d)}T\{pad2(hh)}:\{pad2(mi)}:\{pad2(ss)}.\{pad3(millis)}\{sign}\{pad2(abs_min / 60)}:\{pad2(abs_min % 60)}"
}

///|
/// Zero-pad to exactly 3 digits.
fn pad3(n : Int) -> String {
  if n < 10 {
    "00\{n}"
  } else if n < 100 {
    "0\{n}"
  } else {
    n.to_string()
  }
}

///|
/// Parse a persisted timestamp back into epoch ms. Accepts:
/// - ISO 8601 local strings with optional fractional seconds and a
///   `±HH:MM`/`Z` offset (the current serialization format);
/// - plain millisecond strings/Int64 values (legacy `current.jsonl`
///   records written before spec 21 decision 7).
pub fn parse_timestamp_to_ms(value : Json) -> Int64? {
  match value {
    Number(d, ..) => Some(d.to_int().to_int64())
    String(s) => parse_timestamp_string(s)
    _ => None
  }
}

///|
fn parse_timestamp_string(s : String) -> Int64? {
  if s.is_empty() {
    return None
  }
  // Legacy numeric timestamp (epoch milliseconds).
  if !s.contains("T") && !s.contains("-") {
    return parse_int64_opt(s)
  }
  guard s.length() >= 19 else { return None }
  let year = match parse_digits_opt(s, 0, 4) {
    Some(v) => v
    None => return None
  }
  let month = match parse_digits_opt(s, 5, 7) {
    Some(v) => v
    None => return None
  }
  let day = match parse_digits_opt(s, 8, 10) {
    Some(v) => v
    None => return None
  }
  let hour = match parse_digits_opt(s, 11, 13) {
    Some(v) => v
    None => return None
  }
  let minute = match parse_digits_opt(s, 14, 16) {
    Some(v) => v
    None => return None
  }
  let second = match parse_digits_opt(s, 17, 19) {
    Some(v) => v
    None => return None
  }
  let mut millis = 0
  let mut i = 19
  if i < s.length() && s[i] == '.' {
    i = i + 1
    let mut digits = 0
    while i < s.length() && s[i] >= '0' && s[i] <= '9' && digits < 3 {
      millis = millis * 10 + (s[i].to_int() - '0'.to_int())
      i = i + 1
      digits = digits + 1
    }
    // Skip sub-millisecond remainder (truncate).
    while i < s.length() && s[i] >= '0' && s[i] <= '9' {
      i = i + 1
    }
    if digits == 1 {
      millis = millis * 100
    } else if digits == 2 {
      millis = millis * 10
    }
  }
  // Offset suffix: "Z" or "±HH:MM".
  let mut offset_min = 0
  if i < s.length() {
    if s[i] == 'Z' {
      offset_min = 0
    } else if s[i] == '+' || s[i] == '-' {
      let sign = if s[i] == '-' { -1 } else { 1 }
      guard i + 6 <= s.length() else { return None }
      let oh = match parse_digits_opt(s, i + 1, i + 3) {
        Some(v) => v
        None => return None
      }
      let om = match parse_digits_opt(s, i + 4, i + 6) {
        Some(v) => v
        None => return None
      }
      offset_min = sign * (oh * 60 + om)
    } else {
      return None
    }
  } else {
    // No offset: treat as local time (be lenient for hand-written records).
    offset_min = local_offset_minutes()
  }
  let days = days_from_civil(year, month, day)
  let utc_ms = days.to_int64() * 86_400_000L +
    (hour * 3600 + minute * 60 + second).to_int64() * 1000L +
    millis.to_int64() -
    offset_min.to_int64() * 60_000L
  Some(utc_ms)
}
