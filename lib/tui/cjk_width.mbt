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
  let current = StringBuilder::new()
  let mut current_width = 0
  for c in line.iter() {
    let cw = @tui_core.char_display_width(c)
    if current_width + cw > max_width {
      segments.push(current.to_string())
      current.reset()
      current_width = 0
    }
    current.write_char(c)
    current_width = current_width + cw
  }
  if current_width > 0 {
    segments.push(current.to_string())
  }
  if segments.length() == 0 {
    segments.push("")
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
