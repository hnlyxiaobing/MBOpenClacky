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
