///| EPIPE-safe IO wrapper.
/// Wraps output operations to handle broken pipe (EPIPE) gracefully
/// instead of crashing.

///|
/// IO write result type.
pub enum WriteResult {
  Success(Int) // Successfully written byte count
  PipeBroken // Pipe is broken (EPIPE)
  Error(String) // Other error
} derive(Debug, Eq)

///|
/// Safe write to stdout. In wasm-gc target this is a stub that always succeeds.
pub fn safe_stdout_write(content : String) -> WriteResult {
  if content.is_empty() {
    return Success(0)
  }
  // In actual native target, this would wrap write() with EPIPE handling.
  // For wasm-gc, we just print and report success.
  println(content)
  Success(content.length())
}

///|
/// Safe write to stderr. Stub implementation.
pub fn safe_stderr_write(content : String) -> WriteResult {
  if content.is_empty() {
    return Success(0)
  }
  // Stub: in native this would write to fd 2 with error handling
  Success(content.length())
}

///|
/// Check if an error message indicates an EPIPE error.
pub fn is_epipe_error(error_msg : String) -> Bool {
  let lower = error_msg.to_lower()
  lower.contains("epipe") ||
  lower.contains("broken pipe") ||
  lower.contains("error 32") ||
  lower.contains("errno 32")
}

///|
/// Safe println that silently ignores EPIPE errors.
pub fn safe_println(content : String) -> Unit {
  let result = safe_stdout_write(content)
  match result {
    PipeBroken | Error(_) => () // Silently ignore
    Success(_) => ()
  }
}

///|
/// Write multiple lines safely, stopping on EPIPE.
pub fn safe_write_lines(lines : Array[String]) -> WriteResult {
  let mut total = 0
  for line in lines {
    match safe_stdout_write(line) {
      Success(n) => total = total + n
      PipeBroken => return PipeBroken
      Error(e) => {
        if is_epipe_error(e) {
          return PipeBroken
        }
        return Error(e)
      }
    }
  }
  Success(total)
}
