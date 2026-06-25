///|
/// Realtime inline renderer for streaming content.
///
/// Manages a text buffer and provides incremental rendering using ANSI
/// cursor control sequences. Designed for displaying LLM streaming output.

///|
/// Realtime renderer state (immutable, functional updates).
pub(all) struct RealtimeRenderer {
  buffer : String
  line_count : Int
  max_width : Int
} derive(Eq, Debug)

///|
/// Create a new RealtimeRenderer with the given maximum width.
pub fn RealtimeRenderer::new(max_width~ : Int) -> RealtimeRenderer {
  { buffer: "", line_count: 0, max_width }
}

///|
/// Append a chunk of streaming content, returning a new renderer state.
pub fn RealtimeRenderer::append(
  self : RealtimeRenderer,
  chunk : String,
) -> RealtimeRenderer {
  let new_buffer = self.buffer + chunk
  let new_line_count = count_newlines_impl(new_buffer)
  { buffer: new_buffer, line_count: new_line_count, max_width: self.max_width }
}

///|
/// Compute the incremental ANSI output needed to update from a previous state.
///
/// Uses cursor-up sequences to overwrite changed lines, then prints the delta.
pub fn RealtimeRenderer::render_delta(
  self : RealtimeRenderer,
  prev : RealtimeRenderer,
) -> String {
  if prev.buffer.length() == 0 {
    // First render — just output the full buffer
    return self.buffer
  }
  if self.buffer == prev.buffer {
    // No change
    return ""
  }
  // Calculate how many lines to move cursor up
  let lines_up = prev.line_count
  let out = StringBuilder::new()
  // Move cursor up to beginning of previous output
  if lines_up > 0 {
    // ANSI: move cursor up N lines
    out.write_string("\u001b[\{lines_up}A")
  }
  // Carriage return to start of line
  out.write_string("\r")
  // Clear from cursor to end of screen
  out.write_string("\u001b[J")
  // Write new content
  out.write_string(self.buffer)
  out.to_string()
}

///|
/// Clear the renderer buffer, returning the ANSI clear sequence and new state.
pub fn RealtimeRenderer::clear(
  self : RealtimeRenderer,
) -> (String, RealtimeRenderer) {
  let out = StringBuilder::new()
  if self.line_count > 0 {
    // Move up to clear all lines
    out.write_string("\u001b[\{self.line_count}A")
    out.write_string("\r")
    out.write_string("\u001b[J")
  } else if self.buffer.length() > 0 {
    // Single line — just clear the line
    out.write_string("\r")
    out.write_string("\u001b[K")
  }
  let new_state : RealtimeRenderer = {
    buffer: "",
    line_count: 0,
    max_width: self.max_width,
  }
  (out.to_string(), new_state)
}

///|
/// Count the number of newline characters in a string.
fn count_newlines_impl(s : String) -> Int {
  let chars = s.to_array()
  let mut count = 0
  for i = 0; i < chars.length(); i = i + 1 {
    if chars[i] == '\n' {
      count = count + 1
    }
  }
  count
}
