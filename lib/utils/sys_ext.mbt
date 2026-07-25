///|
/// System extension FFI: chdir / osrelease
/// Bridging MoonBit to platform-native directory and kernel info operations.

///|
/// Change the current working directory.
/// Returns 0 on success, -1 on error.
#cfg(target="native")
#borrow(path)
extern "C" fn chdir_ffi(path : String) -> Int = "mbopenclacky_chdir"

///|
/// Get the kernel release string (same content as
/// /proc/sys/kernel/osrelease). Returns empty string on Windows/error.
#cfg(target="native")
extern "C" fn osrelease_ffi() -> String = "mbopenclacky_osrelease"

///|
/// Public API: change working directory
pub fn change_dir(path : String) -> Unit {
  let ret = chdir_ffi(path)
  if ret != 0 {
    // Could raise error, but for now silent — caller checks
  }
}

///|
/// Public API: get current working directory
pub fn current_dir() -> String {
  match @env.current_dir() {
    Some(d) => d
    None => ""
  }
}
