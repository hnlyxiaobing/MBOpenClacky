///|
/// 5x5 ASCII art block font renderer for the TUI.
///
/// Each glyph is 5 rows tall and 5 columns wide. Characters are joined
/// horizontally with a single space column, and newlines in the input
/// are honored as line breaks. Characters that are not in the table
/// (including CJK and other non-ASCII) fall back to the original
/// character centered in a 5-column block, so the layout stays aligned
/// and the source character is preserved verbatim.
///
/// This is a companion to the 5x5 bitmap renderer in `lib/utils`; that
/// one is designed for compact Full / Half / Outline bitmap output,
/// while this one is the banner-style Standard / Banner / Shadow set
/// suited for startup headers.

///|
/// Available block font styles.
pub enum BlockFontStyle {
  /// 5x5 bitmap drawn with the full block character.
  Standard
  /// Same bitmap wrapped in a single-line box.
  Banner
  /// Same bitmap with a one-cell drop shadow drawn in light shade.
  Shadow
} derive(Eq, Show)

///|
/// Height in rows of a single Standard-style glyph.
pub let block_font_height : Int = 5

///|
/// Width in columns of a single Standard-style glyph.
pub let block_font_width : Int = 5

///|
/// Render `text` as ASCII art block font using the Standard style.
///
/// Returns an empty string for an empty input. The output has
/// `block_font_height` rows per input line; multi-line input is
/// rendered block-by-block and joined with newlines.
pub fn render(text : String) -> String {
  render_with_style(text, Standard)
}

///|
/// Render `text` as ASCII art block font with the given style.
///
/// The `Banner` style adds one extra row above and below (the box
/// border) and one column on each side, so the output is two rows
/// taller and two columns wider than the Standard style. The
/// `Shadow` style adds one shadow column on the right and one
/// shadow row below, so the output is one row taller and one
/// column wider.
pub fn render_with_style(text : String, style : BlockFontStyle) -> String {
  let lines = render_lines_with_style(text, style)
  lines.join("\n")
}

///|
/// Render `text` as an array of output lines using the Standard style.
/// Returns an empty array for an empty input.
pub fn render_lines(text : String) -> Array[String] {
  render_lines_with_style(text, Standard)
}

///|
/// Render `text` as an array of output lines with the given style.
pub fn render_lines_with_style(
  text : String,
  style : BlockFontStyle,
) -> Array[String] {
  if text.length() == 0 {
    return []
  }
  let input_lines = split_lines(text)
  let result : Array[String] = []
  for i, line in input_lines {
    let rendered = render_block(line, style)
    for l in rendered {
      result.push(l)
    }
    if i < input_lines.length() - 1 {
      // Insert a blank row between rendered blocks so consecutive
      // lines in the input do not visually merge.
      result.push("")
    }
  }
  result
}

///|
/// Maximum rendered width of `text` (Standard style) in columns.
pub fn render_width(text : String) -> Int {
  render_width_with_style(text, Standard)
}

///|
/// Maximum rendered width of `text` in the given style, in columns.
pub fn render_width_with_style(text : String, style : BlockFontStyle) -> Int {
  let lines = render_lines_with_style(text, style)
  let mut max_w = 0
  for line in lines {
    if line.length() > max_w {
      max_w = line.length()
    }
  }
  max_w
}

// ---------------------------------------------------------------------------
// internal helpers
// ---------------------------------------------------------------------------

///|
/// Split `text` on '\n' (preserving empty fields) so multi-line input
/// can be rendered as multiple block-font paragraphs.
fn split_lines(text : String) -> Array[String] {
  let parts : Array[String] = []
  let buf = StringBuilder::new()
  for c in text.iter() {
    if c == '\n' {
      parts.push(buf.to_string())
      buf.reset()
    } else {
      buf.write_char(c)
    }
  }
  parts.push(buf.to_string())
  parts
}

///|
/// Render a single line (no newlines) as a block-font array of rows,
/// then optionally apply the Banner frame or Shadow overlay.
fn render_block(text : String, style : BlockFontStyle) -> Array[String] {
  let n_rows = block_font_height
  let rows : Array[String] = Array::make(n_rows, "")
  let mut first = true
  for c in text.iter() {
    if not(first) {
      for i in 0..<n_rows {
        rows[i] = rows[i] + " "
      }
    }
    first = false
    let g = letter_shape(c).unwrap_or(fallback_glyph(c))
    for i in 0..<n_rows {
      rows[i] = rows[i] + g[i]
    }
  }
  match style {
    Standard => rows
    Banner => apply_banner_frame(rows)
    Shadow => apply_shadow(rows)
  }
}

///|
/// Wrap a rendered block in a single-line box frame.
fn apply_banner_frame(rows : Array[String]) -> Array[String] {
  let width = rows[0].length()
  let top = "╔" + "═".repeat(width) + "╗"
  let bottom = "╚" + "═".repeat(width) + "╝"
  let result : Array[String] = [top]
  for line in rows {
    result.push("║" + line + "║")
  }
  result.push(bottom)
  result
}

///|
/// Add a one-cell drop shadow (light shade) to the right and bottom
/// of the rendered block.
fn apply_shadow(rows : Array[String]) -> Array[String] {
  let width = rows[0].length()
  let result : Array[String] = []
  for line in rows {
    result.push(line + "░")
  }
  // Bottom shadow row, offset one column to the right so it reads as
  // a down-right drop shadow rather than a flush bottom border.
  result.push(" " + "░".repeat(width))
  result
}

///|
/// Fallback glyph for characters without a defined 5x5 shape (CJK
/// and any other unsupported character). Preserves the original
/// character centered in a 5-column block so the surrounding layout
/// is not disturbed and the character remains visible.
fn fallback_glyph(c : Char) -> Array[String] {
  let s = c.to_string()
  // Use byte length for the padding math. The visual width of a
  // CJK character (2 columns) is wider than its byte length would
  // suggest, so the result is approximate, but the character is
  // preserved verbatim and the block stays 5 columns wide in source.
  let s_len = s.length()
  let pad_left = if s_len >= block_font_width {
    0
  } else {
    (block_font_width - s_len) / 2
  }
  let pad_right = if s_len >= block_font_width {
    0
  } else {
    block_font_width - s_len - pad_left
  }
  let line = " ".repeat(pad_left) + s + " ".repeat(pad_right)
  [line, line, line, line, line]
}

///|
/// 5x5 glyph shape for the supported ASCII characters. Returns
/// `None` for characters that are not defined; the caller is expected
/// to substitute the fallback glyph in that case.
fn letter_shape(c : Char) -> Array[String]? {
  let rows = match c {
    'A' =>
      [
        "█████", "█   █", "█████", "█   █", "█   █",
      ]
    'B' =>
      [
        "████ ", "█   █", "████ ", "█   █", "████ ",
      ]
    'C' => [" ████", "█    ", "█    ", "█    ", " ████"]
    'D' =>
      ["████ ", "█   █", "█   █", "█   █", "████ "]
    'E' =>
      [
        "█████", "█    ", "████ ", "█    ", "█████",
      ]
    'F' => ["█████", "█    ", "████ ", "█    ", "█    "]
    'G' =>
      [" ████", "█    ", "█  ██", "█   █", " ████"]
    'H' =>
      ["█   █", "█   █", "█████", "█   █", "█   █"]
    'I' =>
      ["█████", "  █  ", "  █  ", "  █  ", "█████"]
    'J' => ["█████", "    █", "    █", "█   █", " ███ "]
    'K' => ["█   █", "█  █ ", "███  ", "█  █ ", "█   █"]
    'L' => ["█    ", "█    ", "█    ", "█    ", "█████"]
    'M' =>
      ["█   █", "██ ██", "█ █ █", "█   █", "█   █"]
    'N' =>
      ["█   █", "██  █", "█ █ █", "█  ██", "█   █"]
    'O' => [" ███ ", "█   █", "█   █", "█   █", " ███ "]
    'P' => ["████ ", "█   █", "████ ", "█    ", "█    "]
    'Q' =>
      [" ███ ", "█   █", "█ █ █", "█  █ ", " ████"]
    'R' =>
      ["████ ", "█   █", "████ ", "█  █ ", "█   █"]
    'S' =>
      [" ████", "█    ", " ███ ", "    █", "████ "]
    'T' => ["█████", "  █  ", "  █  ", "  █  ", "  █  "]
    'U' => ["█   █", "█   █", "█   █", "█   █", " ███ "]
    'V' => ["█   █", "█   █", "█   █", " █ █ ", "  █  "]
    'W' =>
      ["█   █", "█   █", "█ █ █", "██ ██", "█   █"]
    'X' => ["█   █", " █ █ ", "  █  ", " █ █ ", "█   █"]
    'Y' => ["█   █", " █ █ ", "  █  ", "  █  ", "  █  "]
    'Z' =>
      ["█████", "   █ ", "  █  ", " █   ", "█████"]
    '0' =>
      [" ███ ", "█   █", "█  ██", "█   █", " ███ "]
    '1' => ["  █  ", " ██  ", "  █  ", "  █  ", "█████"]
    '2' => [" ███ ", "█   █", "   █ ", "  █  ", "█████"]
    '3' => ["████ ", "    █", "  ██ ", "    █", "████ "]
    '4' => ["█   █", "█   █", "█████", "    █", "    █"]
    '5' =>
      [
        "█████", "█    ", "████ ", "    █", "████ ",
      ]
    '6' =>
      [" ███ ", "█    ", "████ ", "█   █", " ███ "]
    '7' => ["█████", "    █", "   █ ", "  █  ", "  █  "]
    '8' =>
      [" ███ ", "█   █", " ███ ", "█   █", " ███ "]
    '9' =>
      [" ███ ", "█   █", " ████", "    █", " ███ "]
    ' ' => ["     ", "     ", "     ", "     ", "     "]
    '.' => ["     ", "     ", "     ", "     ", "  █  "]
    ',' => ["     ", "     ", "     ", "  █  ", " █   "]
    '!' => ["  █  ", "  █  ", "  █  ", "     ", "  █  "]
    '?' => [" ███ ", "█   █", "   █ ", "  █  ", "  █  "]
    ':' => ["     ", "  █  ", "     ", "  █  ", "     "]
    '-' => ["     ", "     ", "█████", "     ", "     "]
    '_' => ["     ", "     ", "     ", "     ", "█████"]
    '/' => ["    █", "   █ ", "  █  ", " █   ", "█    "]
    '\\' => ["█    ", " █   ", "  █  ", "   █ ", "    █"]
    '(' => ["   █ ", "  █  ", "  █  ", "  █  ", "   █ "]
    ')' => [" █   ", "  █  ", "  █  ", "  █  ", " █   "]
    '[' => ["  ██ ", "  █  ", "  █  ", "  █  ", "  ██ "]
    ']' => [" ██  ", "  █  ", "  █  ", "  █  ", " ██  "]
    '<' => ["    █", "   █ ", "  █  ", "   █ ", "    █"]
    '>' => ["█    ", " █   ", "  █  ", " █   ", "█    "]
    '=' => ["     ", "█████", "     ", "█████", "     "]
    '+' => ["     ", "  █  ", "█████", "  █  ", "     "]
    '*' => ["     ", "█ █ █", " ███ ", "█ █ █", "     "]
    '@' =>
      [" ███ ", "█   █", "█ ███", "█ █  ", " ███ "]
    '#' =>
      [
        " █ █ ", "█████", " █ █ ", "█████", " █ █ ",
      ]
    '|' => ["  █  ", "  █  ", "  █  ", "  █  ", "  █  "]
    _ => return None
  }
  Some(rows)
}
