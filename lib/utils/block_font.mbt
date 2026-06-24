///|
/// Block font renderer for rendering text as Unicode block character art.
/// Supports Full, Half, and Outline block styles.

///|
/// Block font style
pub enum BlockStyle {
  Full // Full block characters (█)
  Half // Half block characters (▀▄)
  Outline // Outline characters (░▒▓)
} derive(Debug, Eq, Show)

///|
/// Character bitmap: 5 rows of 5 columns.
/// Each row is a 5-character string of '1' (filled) and '0' (empty).
priv struct CharBitmap {
  rows : Array[String]
}

///|
/// Block font renderer
pub(all) struct BlockFont {
  style : BlockStyle
  letter_spacing : Int
} derive(Eq, Debug)

///|
/// Create a new BlockFont with default style (Full, spacing 1).
pub fn BlockFont::new() -> BlockFont {
  { style: Full, letter_spacing: 1 }
}

///|
/// Create with custom style and default spacing.
pub fn BlockFont::with_style(style : BlockStyle) -> BlockFont {
  { style, letter_spacing: 1 }
}

///|
/// Get the width of a rendered character (always 5).
pub fn BlockFont::char_width(_self : BlockFont) -> Int {
  5
}

///|
/// Get the height of rendered text (always 5).
pub fn BlockFont::height() -> Int {
  5
}

///|
/// Look up the 5x5 bitmap for a character.
/// Returns None for undefined characters.
fn char_bitmap(c : Char) -> CharBitmap? {
  let rows = match c {
    'A' => ["01110", "10001", "11111", "10001", "10001"]
    'B' => ["11110", "10001", "11110", "10001", "11110"]
    'C' => ["01110", "10001", "10000", "10001", "01110"]
    'D' => ["11110", "10001", "10001", "10001", "11110"]
    'E' => ["11111", "10000", "11110", "10000", "11111"]
    'F' => ["11111", "10000", "11110", "10000", "10000"]
    'G' => ["01110", "10000", "10011", "10001", "01110"]
    'H' => ["10001", "10001", "11111", "10001", "10001"]
    'I' => ["01110", "00100", "00100", "00100", "01110"]
    'J' => ["00111", "00010", "00010", "10010", "01100"]
    'K' => ["10001", "10010", "11100", "10010", "10001"]
    'L' => ["10000", "10000", "10000", "10000", "11111"]
    'M' => ["10001", "11011", "10101", "10001", "10001"]
    'N' => ["10001", "11001", "10101", "10011", "10001"]
    'O' => ["01110", "10001", "10001", "10001", "01110"]
    'P' => ["11110", "10001", "11110", "10000", "10000"]
    'Q' => ["01110", "10001", "10101", "10010", "01101"]
    'R' => ["11110", "10001", "11110", "10010", "10001"]
    'S' => ["01110", "10000", "01110", "00001", "11110"]
    'T' => ["11111", "00100", "00100", "00100", "00100"]
    'U' => ["10001", "10001", "10001", "10001", "01110"]
    'V' => ["10001", "10001", "10001", "01010", "00100"]
    'W' => ["10001", "10001", "10101", "11011", "10001"]
    'X' => ["10001", "01010", "00100", "01010", "10001"]
    'Y' => ["10001", "01010", "00100", "00100", "00100"]
    'Z' => ["11111", "00010", "00100", "01000", "11111"]
    '0' => ["01110", "10011", "10101", "11001", "01110"]
    '1' => ["00100", "01100", "00100", "00100", "01110"]
    '2' => ["01110", "10001", "00110", "01000", "11111"]
    '3' => ["11110", "00001", "01110", "00001", "11110"]
    '4' => ["10001", "10001", "11111", "00001", "00001"]
    '5' => ["11111", "10000", "11110", "00001", "11110"]
    '6' => ["01110", "10000", "11110", "10001", "01110"]
    '7' => ["11111", "00001", "00010", "00100", "00100"]
    '8' => ["01110", "10001", "01110", "10001", "01110"]
    '9' => ["01110", "10001", "01111", "00001", "01110"]
    ' ' => ["00000", "00000", "00000", "00000", "00000"]
    '-' => ["00000", "00000", "11111", "00000", "00000"]
    '.' => ["00000", "00000", "00000", "00000", "00100"]
    ':' => ["00000", "00100", "00000", "00100", "00000"]
    _ => return None
  }
  Some({ rows, })
}

///|
/// Render a single character as block art (5 lines high).
/// Returns an array of 5 strings, each representing one line.
pub fn BlockFont::render_char(self : BlockFont, c : Char) -> Array[String] {
  let upper = if c >= 'a' && c <= 'z' {
    // Convert lowercase to uppercase using ASCII offset
    let s = c.to_string().to_upper()
    s.to_array()[0]
  } else {
    c
  }
  let bitmap = match char_bitmap(upper) {
    Some(bm) => bm
    None =>
      // Unknown character: render as a simple filled block
      { rows: ["11111", "11111", "11111", "11111", "11111"] }
  }
  let result = []
  for row in bitmap.rows {
    let line = self.render_row(row)
    result.push(line)
  }
  result
}

///|
/// Render a full text string as block art.
/// Returns 5 lines of concatenated character art.
pub fn BlockFont::render_text(self : BlockFont, text : String) -> Array[String] {
  let lines : Array[Array[String]] = []
  for ch in text.iter() {
    lines.push(self.render_char(ch))
  }
  if lines.is_empty() {
    return ["", "", "", "", ""]
  }
  let spacing = " ".repeat(self.letter_spacing)
  let result = []
  for row_idx = 0; row_idx < 5; row_idx = row_idx + 1 {
    let parts = []
    for char_lines in lines {
      parts.push(char_lines[row_idx])
    }
    result.push(parts.join(spacing))
  }
  result
}

///|
/// Render a single bitmap row according to the font style.
fn BlockFont::render_row(self : BlockFont, row : String) -> String {
  match self.style {
    Full => self.render_row_full(row)
    Half => self.render_row_half(row)
    Outline => self.render_row_outline(row)
  }
}

///|
/// Full style: '█' for filled, ' ' for empty.
fn BlockFont::render_row_full(self : BlockFont, row : String) -> String {
  let _ = self
  let parts : Array[String] = []
  for ch in row.iter() {
    if ch == '1' {
      parts.push("█")
    } else {
      parts.push(" ")
    }
  }
  parts.join("")
}

///|
/// Half style: '▀' for filled, ' ' for empty.
fn BlockFont::render_row_half(self : BlockFont, row : String) -> String {
  let _ = self
  let parts : Array[String] = []
  for ch in row.iter() {
    if ch == '1' {
      parts.push("▀")
    } else {
      parts.push(" ")
    }
  }
  parts.join("")
}

///|
/// Outline style: '▓' for filled, '░' for empty.
fn BlockFont::render_row_outline(self : BlockFont, row : String) -> String {
  let _ = self
  let parts : Array[String] = []
  for ch in row.iter() {
    if ch == '1' {
      parts.push("▓")
    } else {
      parts.push("░")
    }
  }
  parts.join("")
}
