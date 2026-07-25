///|
/// Get the current wall-clock time in milliseconds since epoch.
pub fn current_time_ms() -> Int64 {
  @env.now().reinterpret_as_int64()
}

///|
/// Current local UTC offset in minutes (e.g. +480 for UTC+8).
/// Detected via OS APIs (GetTimeZoneInformation / localtime_r).
#cfg(target="native")
extern "C" fn local_offset_minutes_ffi() -> Int = "mbopenclacky_local_offset_minutes"

///|
#cfg(target="native")
fn local_offset_minutes() -> Int {
  local_offset_minutes_ffi()
}

///|
#cfg(not(target="native"))
fn local_offset_minutes() -> Int {
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
