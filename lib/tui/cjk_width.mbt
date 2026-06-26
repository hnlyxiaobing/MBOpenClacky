///|
/// CJK-aware character display width utilities.
///
/// Terminal emulators display East Asian Wide/Fullwidth characters
/// in two columns, and most other characters in one column. This
/// module provides functions to calculate the visual display width
/// of strings, which is essential for correct cursor positioning
/// and line wrapping in the TUI editor.

///|
/// Calculate the terminal display width of a single character.
///
/// Returns 2 for East Asian Wide/Fullwidth characters, 1 for all others.
/// Based on Unicode EastAsianWidth categories and common terminal behavior.
pub fn char_display_width(c : Char) -> Int {
  let cp = c.to_int()
  if is_wide_codepoint(cp) {
    2
  } else {
    1
  }
}

///|
/// Calculate the total terminal display width of a string.
///
/// Sums the display width of each character. Use this instead of
/// `.length()` when computing visual column positions.
pub fn string_display_width(s : String) -> Int {
  let mut width = 0
  for c in s.iter() {
    width = width + char_display_width(c)
  }
  width
}

///|
/// Wrap a line at a maximum display width, respecting CJK double-width chars.
///
/// Returns an array of line segments, each no wider than `max_width`
/// display columns. A 2-column CJK character that would overflow the
/// boundary is moved to the next segment.
pub fn wrap_line_at_width(line : String, max_width : Int) -> Array[String] {
  if max_width <= 0 {
    return [line]
  }
  let segments : Array[String] = []
  let current = StringBuilder::new()
  let mut current_width = 0
  for c in line.iter() {
    let cw = char_display_width(c)
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
/// Calculate the display column for a cursor at character position `col`
/// in the given line string.
///
/// This accounts for CJK double-width characters: the cursor column
/// may be larger than the character index if wide characters precede it.
pub fn cursor_display_col(line : String, col : Int) -> Int {
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
/// Convert a display column back to a character index in the given line.
///
/// Given a visual column position, returns the character index whose
/// display position contains that column. Useful for mouse click
/// position mapping.
pub fn display_col_to_char_index(line : String, display_col : Int) -> Int {
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

// ── Internal: Unicode wide codepoint check ───────────────────────────────

///|
/// Check if a Unicode codepoint is a wide (double-width) character.
///
/// Covers East Asian Wide/Fullwidth ranges commonly encountered in
/// CJK text, Hangul, emoji, and fullwidth Latin forms.
fn is_wide_codepoint(cp : Int) -> Bool {
  // Hangul Jamo
  if cp >= 0x1100 && cp <= 0x115F {
    return true
  }
  // Left/Right-Pointing Angle Brackets
  if cp == 0x2329 || cp == 0x232A {
    return true
  }
  // CJK Radicals Supplement .. CJK Symbols and Punctuation
  if cp >= 0x2E80 && cp <= 0x303E {
    return true
  }
  // Hiragana .. Yi Radicals (includes Katakana, Bopomofo, Hangul Compat, CJK Unified)
  if cp >= 0x3040 && cp <= 0xA4CF {
    return true
  }
  // Hangul Syllables
  if cp >= 0xAC00 && cp <= 0xD7A3 {
    return true
  }
  // CJK Compatibility Ideographs
  if cp >= 0xF900 && cp <= 0xFAFF {
    return true
  }
  // Vertical Forms
  if cp >= 0xFE10 && cp <= 0xFE19 {
    return true
  }
  // CJK Compatibility Forms .. Small Form Variants
  if cp >= 0xFE30 && cp <= 0xFE6F {
    return true
  }
  // Fullwidth Forms (Latin, Shapes)
  if cp >= 0xFF00 && cp <= 0xFF60 {
    return true
  }
  // Fullwidth Currency/Signs
  if cp >= 0xFFE0 && cp <= 0xFFE6 {
    return true
  }
  // Emoticons, Symbols, Pictographs, etc.
  if cp >= 0x1F300 && cp <= 0x1F9FF {
    return true
  }
  // CJK Unified Ideographs Extension B-F (Supplementary)
  if cp >= 0x20000 && cp <= 0x2FFFD {
    return true
  }
  // CJK Unified Ideographs Extension G (Supplementary)
  if cp >= 0x30000 && cp <= 0x3FFFD {
    return true
  }
  false
}
