///|
/// Console code page FFI: switch the Windows console to UTF-8 while the TUI
/// runs, restoring the original code pages on exit.
/// On non-Windows targets both functions are no-ops (the C stub compiles to
/// empty implementations).

///|
/// Switch console output/input code pages to UTF-8 (CP 65001).
/// Returns a token encoding the original code pages, or 0 when there is
/// nothing to restore (non-Windows, no console attached, or already switched).
#cfg(target="native")
extern "C" fn set_console_utf8_ffi() -> Int = "mbopenclacky_set_console_utf8"

///|
/// Restore the console code pages saved by `set_console_utf8_ffi`.
/// Safe to call with 0 (no-op).
#cfg(target="native")
extern "C" fn restore_console_cp_ffi(token : Int) -> Unit = "mbopenclacky_restore_console_cp"

///|
/// Public API: switch the console to UTF-8, returning an opaque token that
/// must be passed to `restore_console_cp` on exit. Returns 0 on non-Windows
/// platforms or when no console is attached (safe to pass back to restore).
pub fn set_console_utf8() -> Int {
  set_console_utf8_ffi()
}

///|
/// Public API: restore the console code pages saved by `set_console_utf8`.
pub fn restore_console_cp(token : Int) -> Unit {
  restore_console_cp_ffi(token)
}
