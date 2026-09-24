///| Diagnostic output routing.
///
/// stdout is the machine-readable contract (`--message --json`,
/// `eval --live`); diagnostics that user-facing modes want to see must go to
/// stderr instead, or every JSON consumer has to special-case a trailing
/// non-JSON line.

///|
/// Write one diagnostic line to stderr (a newline is appended by the stub).
pub fn write_diagnostic(msg : String) -> Unit {
  write_stderr_ffi(@utf8.encode(msg))
}

///|
#borrow(bytes)
extern "C" fn write_stderr_ffi(bytes : Bytes) -> Unit = "mbopenclacky_write_stderr"