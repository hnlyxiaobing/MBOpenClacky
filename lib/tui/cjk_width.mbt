///|
/// CJK-aware text utilities for cursor positioning and line wrapping.
///
/// Width calculation is delegated to mizchi/tui/core which provides
/// Unicode-aware display width (including CJK double-width, emoji, etc.).
/// This module provides application-specific helpers built on top of it.

///|
/// Wrap a line at a maximum display width, respecting CJK double-width chars.
pub fn wrap_line_at_width(line : String, max_width : Int) -> Array[String] {
  if max_width <= 0 {
    return [line]
  }
  let segments : Array[String] = []
  let chars = line.to_array()
  for range in wrap_line_segments(line, max_width) {
    let (start, end) = range
    let sb = StringBuilder::new()
    for i = start; i < end; i = i + 1 {
      sb.write_char(chars[i])
    }
    segments.push(sb.to_string())
  }
  if segments.length() == 0 {
    segments.push("")
  }
  segments
}

///|
/// Wrap a line like `wrap_line_at_width`, but return the char-index ranges
/// `[start, end)` of each segment instead of the segment strings.
///
/// Callers that need to map a cursor char index onto a wrapped segment
/// (e.g. for terminal cursor placement) use this to stay exactly consistent
/// with the rendered wrapping.
pub fn wrap_line_segments(line : String, max_width : Int) -> Array[(Int, Int)] {
  if max_width <= 0 {
    return [(0, line.length())]
  }
  let segments : Array[(Int, Int)] = []
  let mut seg_start = 0
  let mut current_width = 0
  let mut idx = 0
  for c in line.iter() {
    let cw = @tui_core.char_display_width(c)
    if current_width + cw > max_width {
      segments.push((seg_start, idx))
      seg_start = idx
      current_width = 0
    }
    current_width = current_width + cw
    idx = idx + 1
  }
  if current_width > 0 {
    segments.push((seg_start, idx))
  }
  if segments.length() == 0 {
    segments.push((0, 0))
  }
  segments
}

///|
/// Calculate the display column for a cursor at character position `col`.
pub fn cursor_display_col(line : String, col : Int) -> Int {
  let mut dcol = 0
  let mut char_idx = 0
  for c in line.iter() {
    if char_idx >= col {
      break
    }
    dcol = dcol + @tui_core.char_display_width(c)
    char_idx = char_idx + 1
  }
  dcol
}

///|
/// Convert a display column back to a character index.
pub fn display_col_to_char_index(line : String, display_col : Int) -> Int {
  let mut dcol = 0
  let mut char_idx = 0
  for c in line.iter() {
    let cw = @tui_core.char_display_width(c)
    if dcol + cw > display_col {
      break
    }
    dcol = dcol + cw
    char_idx = char_idx + 1
  }
  char_idx
}
