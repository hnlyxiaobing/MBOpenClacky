///|
/// CJK-aware text utilities for cursor positioning and line wrapping.
///
/// Width calculation is delegated to moonbit-community/unicodewidth, which
/// provides full UAX #11 display width (CJK double-width, emoji, zero-width
/// combining marks, etc.). This module provides application-specific helpers
/// built on top of it.

///|
/// Get display width of a character (1 for normal, 2 for wide/CJK, 0 for
/// zero-width combining marks). Control characters report width 1 to match
/// terminal cell accounting for characters such as newline.
pub fn char_display_width(c : Char) -> Int32 {
  match @unicodewidth.char_width(c) {
    Some(w) => w
    None => 1
  }
}

///|
/// Calculate the total display width of a string.
pub fn string_display_width(s : String) -> Int32 {
  let mut width = 0
  for c in s {
    width = width + char_display_width(c)
  }
  width
}

///|
/// Wrap a line at a maximum display width, respecting CJK double-width chars.
pub fn wrap_line_at_width(line : String, max_width : Int32) -> Array[String] {
  if max_width <= 0 {
    return [line]
  }
  let segments : Array[String] = []
  let chars = line.to_array()
  for range in wrap_line_segments(line, max_width) {
    let (start, end) = range
    let sb = StringBuilder()
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
pub fn wrap_line_segments(
  line : String,
  max_width : Int32,
) -> Array[(Int32, Int32)] {
  if max_width <= 0 {
    return [(0, line.length())]
  }
  let segments : Array[(Int32, Int32)] = []
  let mut seg_start = 0
  let mut current_width = 0
  let mut idx = 0
  for c in line.iter() {
    let cw = char_display_width(c)
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
pub fn cursor_display_col(line : String, col : Int32) -> Int32 {
  let mut dcol = 0
  let mut char_idx = 0
  for c in line.iter() {
    if char_idx >= col {
      break
    }
    dcol = dcol + char_display_width(c)
    char_idx = char_idx + 1
  }
  dcol
}

///|
/// Convert a display column back to a character index.
pub fn display_col_to_char_index(line : String, display_col : Int32) -> Int32 {
  let mut dcol = 0
  let mut char_idx = 0
  for c in line.iter() {
    let cw = char_display_width(c)
    if dcol + cw > display_col {
      break
    }
    dcol = dcol + cw
    char_idx = char_idx + 1
  }
  char_idx
}

///|
/// Wrap a line at maximum display width, ANSI-escape-aware.
///
/// ANSI CSI sequences (ESC [ ... m) are invisible and do not contribute
/// to display width. When a line break is inserted, the active SGR state
/// is carried to the next line (prepended as `\e[<params>m`), and the
/// current line is terminated with `\e[0m` to prevent bleeding.
///
/// Lines that fit within `max_width` are returned as-is (no trailing reset).
pub fn wrap_ansi_line(line : String, max_width : Int32) -> Array[String] {
  if max_width <= 0 {
    return [line]
  }
  let chars = line.to_array()
  let len = chars.length()
  // Collect break positions and the SGR state at each break.
  let break_positions : Array[Int32] = []
  let break_sgrs : Array[String] = []
  let mut display_w = 0
  let mut i = 0
  let mut active_sgr : String = ""

  while i < len {
    // Check for ESC [ ... m  (CSI SGR sequence)
    if chars[i] == '\u{1b}' && i + 1 < len && chars[i + 1] == '[' {
      let mut j = i + 2
      let mut params = ""
      while j < len && chars[j] != 'm' {
        params = params + chars[j].to_string()
        j = j + 1
      }
      if j < len && chars[j] == 'm' {
        if params == "0" || params == "" {
          active_sgr = ""
        } else {
          active_sgr = params
        }
        i = j + 1
        continue
      }
    }
    let cw = char_display_width(chars[i])
    if display_w + cw > max_width {
      break_positions.push(i)
      break_sgrs.push(active_sgr)
      display_w = 0
      // Don't consume this char — it starts the next segment
      continue
    }
    display_w = display_w + cw
    i = i + 1
  }

  if break_positions.length() == 0 {
    return [line]
  }

  // Build segments from break positions
  let segments : Array[String] = []
  let mut seg_start = 0
  for bi = 0; bi < break_positions.length(); bi = bi + 1 {
    let bp = break_positions[bi]
    let sb = StringBuilder()
    for k = seg_start; k < bp; k = k + 1 {
      sb.write_char(chars[k])
    }
    // Terminate with reset if there's active SGR
    if break_sgrs[bi].length() > 0 {
      sb.write_string("\u{1b}[0m")
    }
    segments.push(sb.to_string())
    seg_start = bp
  }
  // Final segment (remainder)
  let sb = StringBuilder()
  for k = seg_start; k < len; k = k + 1 {
    sb.write_char(chars[k])
  }
  segments.push(sb.to_string())

  // Prepend carried SGR state to segments 1..n
  let result : Array[String] = []
  for si = 0; si < segments.length(); si = si + 1 {
    if si == 0 {
      result.push(segments[si])
    } else {
      let sgr = break_sgrs[si - 1]
      if sgr.length() > 0 {
        result.push("\u{1b}[\{sgr}m" + segments[si])
      } else {
        result.push(segments[si])
      }
    }
  }
  result
}
