///|
/// Get the current wall-clock time in milliseconds since epoch.
///
/// Uses native FFI for native targets, returns 0 on wasm-gc (stub).
#cfg(target="native")
extern "C" fn ms_since_epoch_ffi() -> Int64 = "mbopenclacky_ms_since_epoch"

///|
#cfg(target="native")
pub fn current_time_ms() -> Int64 {
  ms_since_epoch_ffi()
}

///|
#cfg(any(target="wasm", target="wasm-gc"))
pub fn current_time_ms() -> Int64 {
  0
}

///|
#cfg(target="js")
pub fn current_time_ms() -> Int64 {
  0
}

///|
/// ISO 8601 local-time helpers ("2026-07-24T12:22:34+08:00"), matching the
/// reference implementation's timestamp format.
#cfg(target="native")
extern "C" fn iso8601_now_ffi() -> String = "mbopenclacky_iso8601_now"

///|
#cfg(target="native")
extern "C" fn ms_to_iso8601_local_ffi(ms : Int64) -> String = "mbopenclacky_ms_to_iso8601_local"

///|
/// Current local time as an ISO 8601 string with UTC offset.
#cfg(target="native")
pub fn current_iso8601() -> String {
  iso8601_now_ffi()
}

///|
#cfg(any(target="wasm", target="wasm-gc", target="js"))
pub fn current_iso8601() -> String {
  "1970-01-01T00:00:00+00:00"
}

///|
/// Convert Unix epoch milliseconds to a local ISO 8601 string with offset.
#cfg(target="native")
pub fn ms_to_iso8601(ms : Int64) -> String {
  ms_to_iso8601_local_ffi(ms)
}

///|
#cfg(any(target="wasm", target="wasm-gc", target="js"))
pub fn ms_to_iso8601(_ms : Int64) -> String {
  "1970-01-01T00:00:00+00:00"
}
