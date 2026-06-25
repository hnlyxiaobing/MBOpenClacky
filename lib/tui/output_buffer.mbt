///|
/// Output buffer for managing rendered text lines with scrolling.
///
/// Provides a logical buffer of output lines with style and timestamp
/// metadata, plus viewport-based scrolling for terminal display.

///|
/// A single output line with styling metadata.
pub(all) struct OutputLine {
  /// The text content of the line.
  content : String
  /// Style name: "normal", "bold", "dim", "error", "success", "warning".
  style : String
  /// Optional timestamp string.
  timestamp : String?
} derive(Eq, Debug, Show)

///|
/// Create a normal-style output line.
pub fn OutputLine::new(content : String) -> OutputLine {
  { content, style: "normal", timestamp: None }
}

///|
/// Create an output line with a specific style.
pub fn OutputLine::styled(content : String, style : String) -> OutputLine {
  { content, style, timestamp: None }
}

///|
/// Create an output line with style and timestamp.
pub fn OutputLine::with_timestamp(
  content : String,
  style : String,
  timestamp : String,
) -> OutputLine {
  { content, style, timestamp: Some(timestamp) }
}

///|
/// Scrollable output buffer with viewport-based rendering.
pub(all) struct OutputBuffer {
  /// All stored output lines.
  mut lines : Array[OutputLine]
  /// Maximum number of lines to retain.
  max_lines : Int
  /// Current scroll offset from the bottom (0 = at bottom).
  mut scroll_offset : Int
  /// Number of visible lines in the viewport.
  mut viewport_height : Int
} derive(Debug)

///|
/// Create a new OutputBuffer with the given capacity and viewport height.
pub fn OutputBuffer::new(
  max_lines : Int,
  viewport_height : Int,
) -> OutputBuffer {
  { lines: [], max_lines, scroll_offset: 0, viewport_height }
}

///|
/// Append an OutputLine to the buffer.
///
/// If the buffer exceeds max_lines, the oldest lines are dropped.
pub fn OutputBuffer::append(self : OutputBuffer, line : OutputLine) -> Unit {
  self.lines.push(line)
  // Trim oldest lines if over capacity
  while self.lines.length() > self.max_lines {
    self.lines = self.lines[1:].to_owned()
  }
  // Keep scroll pinned to bottom if already at bottom
  if self.scroll_offset > 0 {
    self.scroll_offset = self.scroll_offset + 1
  }
}

///|
/// Append a text string with an optional style.
pub fn OutputBuffer::append_text(
  self : OutputBuffer,
  content : String,
  style? : String = "normal",
) -> Unit {
  self.append({ content, style, timestamp: None })
}

///|
/// Scroll up by the given number of lines.
pub fn OutputBuffer::scroll_up(self : OutputBuffer, lines? : Int = 1) -> Unit {
  let max_offset = self.max_scroll_offset()
  let new_offset = self.scroll_offset + lines
  self.scroll_offset = if new_offset > max_offset {
    max_offset
  } else {
    new_offset
  }
}

///|
/// Scroll down by the given number of lines.
pub fn OutputBuffer::scroll_down(self : OutputBuffer, lines? : Int = 1) -> Unit {
  let new_offset = self.scroll_offset - lines
  self.scroll_offset = if new_offset < 0 { 0 } else { new_offset }
}

///|
/// Scroll up by one page (viewport_height lines).
pub fn OutputBuffer::page_up(self : OutputBuffer) -> Unit {
  self.scroll_up(lines=self.viewport_height)
}

///|
/// Scroll down by one page (viewport_height lines).
pub fn OutputBuffer::page_down(self : OutputBuffer) -> Unit {
  self.scroll_down(lines=self.viewport_height)
}

///|
/// Scroll to the top of the buffer.
pub fn OutputBuffer::scroll_top(self : OutputBuffer) -> Unit {
  self.scroll_offset = self.max_scroll_offset()
}

///|
/// Scroll to the bottom of the buffer.
pub fn OutputBuffer::scroll_bottom(self : OutputBuffer) -> Unit {
  self.scroll_offset = 0
}

///|
/// Get the lines currently visible in the viewport.
pub fn OutputBuffer::get_visible_lines(
  self : OutputBuffer,
) -> Array[OutputLine] {
  let total = self.lines.length()
  if total == 0 {
    return []
  }
  let end_idx = total - self.scroll_offset
  let start_idx = end_idx - self.viewport_height
  let actual_start = if start_idx < 0 { 0 } else { start_idx }
  let actual_end = if end_idx < 0 { 0 } else { end_idx }
  if actual_start >= total || actual_end <= actual_start {
    return []
  }
  self.lines[actual_start:actual_end].to_array()
}

///|
/// Search the buffer for lines containing the query string.
///
/// Returns an array of matching line indices (0-based).
pub fn OutputBuffer::search(self : OutputBuffer, query : String) -> Array[Int] {
  let results : Array[Int] = []
  for i = 0; i < self.lines.length(); i = i + 1 {
    if self.lines[i].content.contains(query) {
      results.push(i)
    }
  }
  results
}

///|
/// Clear all lines and reset scroll.
pub fn OutputBuffer::clear(self : OutputBuffer) -> Unit {
  self.lines.clear()
  self.scroll_offset = 0
}

///|
/// Get the total number of lines in the buffer.
pub fn OutputBuffer::line_count(self : OutputBuffer) -> Int {
  self.lines.length()
}

///|
/// Update the viewport height (e.g., on resize).
pub fn OutputBuffer::set_viewport_height(
  self : OutputBuffer,
  height : Int,
) -> Unit {
  self.viewport_height = height
}

// ── Internal helpers ────────────────────────────────────────────────

///|
/// Compute the maximum allowed scroll offset.
fn OutputBuffer::max_scroll_offset(self : OutputBuffer) -> Int {
  let total = self.lines.length()
  let max = total - self.viewport_height
  if max < 0 {
    0
  } else {
    max
  }
}
