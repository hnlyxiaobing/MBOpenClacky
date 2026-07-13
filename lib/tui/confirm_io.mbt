///|
/// Synchronous I/O for confirmation prompts.
///
/// These functions bypass the async I/O system using C FFI to
/// read/write directly from file descriptors. This is necessary
/// because the confirmation callback is called synchronously
/// from within `agent.run()`, which blocks the async event loop.

///|
/// Read a single byte from the given file descriptor.
///
/// Returns the byte value (0-255) or -1 on timeout/error.
/// `timeout_ms` = -1 for infinite wait.
extern "c" fn sync_read_byte_fd(fd : Int, timeout_ms : Int) -> Int = "sync_read_byte_fd"

///|
/// Write a string to the given file descriptor.
#borrow(data)
extern "c" fn sync_write_fd(fd : Int, data : String, len : Int) -> Unit = "sync_write_fd"

///|
/// Write a string to stdout (fd 1).
fn sync_write_stdout(text : String) -> Unit {
  sync_write_fd(1, text, text.length())
}

///|
/// Read a confirmation key from stdin (fd 0).
///
/// Reads bytes until a confirmation key is received:
/// - 'y' (0x79) or 'Y' (0x59) → true (approved)
/// - 'n' (0x6e) or 'N' (0x4e) → false (denied)
/// - Enter (0x0d or 0x0a) → uses `default_yes`
/// - Escape (0x1b) → false (cancelled)
/// - Ctrl-C (0x03) → false (cancelled)
/// - Other keys → ignored, re-read
///
/// Escape key handling: after reading 0x1b, waits 50ms for more bytes.
/// If more bytes arrive (escape sequence), they're consumed and the
/// key is treated as "other" (ignored). If no more bytes, it's Escape.
pub fn read_confirmation_key(default_yes : Bool) -> Bool {
  for ;; {
    let byte = sync_read_byte_fd(0, -1) // Infinite wait
    if byte < 0 {
      // Error or EOF — deny
      return false
    }
    match byte {
      0x79 | 0x59 => return true // 'y' or 'Y'
      0x6e | 0x4e => return false // 'n' or 'N'
      0x0d | 0x0a => return default_yes // Enter
      0x03 => return false // Ctrl-C
      0x1b => {
        // Possible Escape key or escape sequence
        // Wait 50ms for more bytes
        let next = sync_read_byte_fd(0, 50)
        if next < 0 {
          // No more bytes — it's a standalone Escape key
          return false
        }
        // More bytes arrived — it's an escape sequence (arrow keys, etc.)
        // Consume remaining bytes of the sequence
        let _ = sync_read_byte_fd(0, 10)
        // Ignore and re-read for confirmation key
      }
      _ => () // Ignore other keys
    }
  }
}

///|
/// Display a confirmation prompt and read the user's response.
///
/// This is the main entry point for the TUI confirmation callback.
/// It writes the prompt to stdout, reads a key from stdin, clears
/// the prompt, and returns the result.
///
/// `tool_name` and `tool_args` are used to build the prompt text.
/// `default_yes` controls the default action for Enter key.
pub fn prompt_confirmation(
  tool_name : String,
  tool_args : String,
  default_yes : Bool,
) -> Bool {
  // Build the prompt
  let prompt_text = build_tool_prompt(tool_name, tool_args)
  let yn = if default_yes { "[Y/n]" } else { "[y/N]" }
  let prompt_line = "\r\u{1b}[K⚠ [\{tool_name}] \{prompt_text}  \{yn} "
  // Write the prompt
  sync_write_stdout(prompt_line)
  // Read the key
  let result = read_confirmation_key(default_yes)
  // Clear the prompt
  sync_write_stdout("\r\u{1b}[K")
  result
}
