///|
/// Get the current wall-clock time in milliseconds since epoch.
pub fn current_time_ms() -> Int64 {
  @env.now().reinterpret_as_int64()
}

///|
/// Return a copy of the message stamped with the current epoch-ms timestamp.
/// Applied to every message that enters conversation history so history
/// pagination/dedup can rely on `created_at`.
fn stamp_created_at(msg : @message.Message) -> @message.Message {
  { ..msg, created_at: Some(current_time_ms().to_string()), }
}

///|
/// Current local UTC offset in minutes (e.g. +480 for UTC+8).
/// Detected via OS APIs (GetTimeZoneInformation / localtime_r).
#cfg(target="native")
extern "C" fn local_offset_minutes_ffi() -> Int32 = "mbopenclacky_local_offset_minutes"

///|
#cfg(target="native")
fn local_offset_minutes() -> Int32 {
  local_offset_minutes_ffi()
}

///|
#cfg(not(target="native"))
fn local_offset_minutes() -> Int32 {
  0
}

///|
/// Format a Unix epoch millisecond value as an ISO 8601 local-time string,
/// e.g. "2026-07-24T12:22:34+08:00".
fn format_iso8601_local(ms : Int64) -> String {
  let offset_min = local_offset_minutes()
  let offset_sec = offset_min * 60
  let local_sec = ms / 1000 + offset_sec.to_int64()
  let datetime = @time.PlainDateTime::from_unix_second(
    local_sec, 0, @time.utc_offset,
  ) catch {
    _ => return "1970-01-01T00:00:00+00:00"
  }
  let sign = if offset_min < 0 { "-" } else { "+" }
  let abs_min = offset_min.abs()
  let hh = (abs_min / 60).to_string()
  let mm = (abs_min % 60).to_string()
  let hh_padded = if hh.length() < 2 { "0" + hh } else { hh }
  let mm_padded = if mm.length() < 2 { "0" + mm } else { mm }
  datetime.to_string() + sign + hh_padded + ":" + mm_padded
}

///|
/// Current local time as an ISO 8601 string with UTC offset.
pub fn current_iso8601() -> String {
  format_iso8601_local(current_time_ms())
}

///|
/// Convert Unix epoch milliseconds to a local ISO 8601 string with offset.
pub fn ms_to_iso8601(ms : Int64) -> String {
  format_iso8601_local(ms)
}

///|
/// True when the string starts with a full `YYYY-MM-DDTHH:MM:SS` timestamp.
fn has_iso_datetime_prefix(s : String) -> Bool {
  if s.length() < 19 {
    return false
  }
  s[4] == '-' && s[7] == '-' && s[10] == 'T' && s[13] == ':' && s[16] == ':'
}

///|
/// Render a timestamp the way Ruby renders session/chunk filenames:
/// `Time.parse(created_at).strftime("%Y-%m-%d-%H-%M-%S")` — e.g.
/// `2026-10-09-14-30-00`, with no `T` and no UTC offset.
///
/// Ruby uses `Time.parse` and `strftime` without a target zone, so the
/// rendered wall clock is the timestamp's own offset, which is exactly the
/// first 19 characters of the ISO 8601 string: only the separators need
/// rewriting. Values without a full `YYYY-MM-DDTHH:MM:SS` prefix (legacy
/// epoch-millisecond dumps, empty strings) fall back to the current local
/// time instead of raising, because the filename must remain usable.
pub fn filename_datetime(iso : String) -> String {
  let stamp = if has_iso_datetime_prefix(iso) {
    iso[:19].to_owned()
  } else {
    let now = current_iso8601()
    if has_iso_datetime_prefix(now) {
      now[:19].to_owned()
    } else {
      "1970-01-01T00-00-00"
    }
  }
  stamp.replace_all(old=":", new="-").replace_all(old="T", new="-")
}

///|
/// Current weekday name (e.g. "Monday", "Tuesday").
pub fn current_weekday() -> String {
  let iso = current_iso8601()
  if iso.length() < 10 {
    return "unknown"
  }
  let year = parse_date_digits(iso, 0, 4)
  let month = parse_date_digits(iso, 5, 7)
  let day = parse_date_digits(iso, 8, 10)
  weekday_name(year, month, day)
}

///|
/// Parse decimal digits from a string slice [start, end).
fn parse_date_digits(s : String, start : Int32, end : Int32) -> Int32 {
  let mut result = 0
  for i = start; i < end; i = i + 1 {
    result = result * 10 + (s[i].to_int() - '0'.to_int())
  }
  result
}

///|
/// Compute weekday name from a date using Tomohiko Sakamoto's algorithm.
fn weekday_name(year : Int32, month : Int32, day : Int32) -> String {
  let t = [0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4]
  let y = if month < 3 { year - 1 } else { year }
  let dow = (y + y / 4 - y / 100 + y / 400 + t[month - 1] + day) % 7
  match dow {
    0 => "Sunday"
    1 => "Monday"
    2 => "Tuesday"
    3 => "Wednesday"
    4 => "Thursday"
    5 => "Friday"
    6 => "Saturday"
    _ => "unknown"
  }
}
