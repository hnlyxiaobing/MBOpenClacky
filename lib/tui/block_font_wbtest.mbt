///|
/// White-box tests for the block font renderer.
///
/// Each test targets a single behavior: single-character render,
/// multi-character render, empty input, CJK fallback, multi-style
/// dispatch, and the render_lines / render_width helpers.

///|
test "render empty string returns empty string" {
  let out = render("")
  assert_eq(out, "")
}

///|
test "render_lines empty string returns empty array" {
  let lines = render_lines("")
  assert_eq(lines.length(), 0)
}

///|
test "block_font_height and width are 5" {
  assert_eq(block_font_height, 5)
  assert_eq(block_font_width, 5)
}

///|
test "render single uppercase letter returns 5 lines" {
  let lines = render_lines("A")
  assert_eq(lines.length(), block_font_height)
  for line in lines {
    // Standard glyphs are 5 columns wide; no inter-letter gap.
    assert_eq(line.length(), 5)
  }
}

///|
test "render single uppercase A matches expected 5x5 shape" {
  let lines = render_lines("A")
  assert_eq(lines[0], "█████")
  assert_eq(lines[1], "█   █")
  assert_eq(lines[2], "█████")
  assert_eq(lines[3], "█   █")
  assert_eq(lines[4], "█   █")
}

///|
test "render single digit matches expected shape" {
  let lines = render_lines("0")
  assert_eq(lines.length(), 5)
  // 0's top and bottom rows are symmetric (3 wide block).
  assert_eq(lines[0], " ███ ")
  assert_eq(lines[4], " ███ ")
}

///|
test "render multi-letter string has inter-letter spacing" {
  let lines = render_lines("Hi")
  // H (5 cols) + 1 space + i (5 cols) = 11 cols.
  assert_eq(lines.length(), 5)
  for line in lines {
    assert_eq(line.length(), 11)
  }
  // The middle column should be a single space (the gap).
  let row0 : String = lines[0]
  assert_eq(row0[5], ' ')
}

///|
test "render with spaces preserves the gap" {
  let lines = render_lines("A B")
  // A(5) + 1 + space(5) + 1 + B(5) = 17 cols.
  for line in lines {
    assert_eq(line.length(), 17)
  }
  // Row 0: A row + space + '     ' (5 spaces) + space + B row.
  assert_eq(lines[0], "█████      █████")
}

///|
test "render supports common punctuation" {
  // Each of these glyphs is defined; we just check no crash and
 // that the output is exactly 5 lines.
  for ch in [".", ",", "!", "?", ":", "-", "_", "/", "\\", "(", ")", "@", "#", "+", "*", "="] {
    let lines = render_lines(ch)
    assert_eq(lines.length(), 5)
  }
}

///|
test "render multi-line input is stacked with a blank separator" {
  let lines = render_lines("A\nB")
  // 5 lines for A + 1 blank separator + 5 lines for B = 11.
  assert_eq(lines.length(), 11)
  assert_eq(lines[5], "")
}

///|
test "render_with_style(Standard) matches render" {
  assert_eq(
    render_with_style("Hi", Standard),
    render("Hi"),
  )
}

///|
test "render_with_style(Banner) adds a box frame" {
  let std = render_lines("Hi")
  let banner = render_lines_with_style("Hi", Banner)
  // Banner output has 2 extra rows (top and bottom borders) and
 // 2 extra columns (left and right borders) compared to Standard.
  assert_eq(banner.length(), std.length() + 2)
  // First line is the top border and must use double-line chars.
  let first : String = banner[0]
  assert_eq(first[0], '╔')
  assert_eq(first[first.length() - 1], '╗')
  // Last line is the bottom border.
  let last : String = banner[banner.length() - 1]
  assert_eq(last[0], '╚')
  assert_eq(last[last.length() - 1], '╝')
}

///|
test "render_with_style(Shadow) adds a drop shadow row" {
  let std = render_lines("Hi")
  let shadow = render_lines_with_style("Hi", Shadow)
  // Shadow adds exactly one row at the bottom and one column on the
 // right compared to Standard.
  assert_eq(shadow.length(), std.length() + 1)
  // The bottom row should consist of a leading space followed by
 // light-shade characters (a "drop shadow" pattern).
  let bottom : String = shadow[shadow.length() - 1]
  assert_eq(bottom[0], ' ')
  for i in 1..<bottom.length() {
    assert_eq(bottom[i], '░')
  }
}

///|
test "CJK characters fall back to the original character" {
  let lines = render_lines("中")
  assert_eq(lines.length(), 5)
  // Every row must preserve the original character verbatim, so a
 // grep for "中" should match in every rendered row.
  for line in lines {
    assert_eq(line.contains("中"), true)
  }
}

///|
test "CJK fallback keeps the 5-column block aligned" {
  let lines = render_lines("你")
  for line in lines {
    // Block width is 5 source characters. For multi-byte UTF-8
    // characters like "你" (3 bytes), String::length returns 3, so
    // the fallback pads the line to a 5-byte width with spaces.
    assert_eq(line.length(), 5)
  }
}

///|
test "CJK characters can mix with ASCII block art" {
  let lines = render_lines("A中")
  // 5 (A) + 1 space + 5 (中 fallback block) = 11 source cols.
  assert_eq(lines.length(), 5)
  for line in lines {
    assert_eq(line.length(), 11)
  }
}

///|
test "render_width measures Standard style" {
  // 5 chars * 5 cols + 4 inter-letter gaps = 29 cols.
  assert_eq(render_width("Hello"), 29)
  // Empty input renders to zero width.
  assert_eq(render_width(""), 0)
}

///|
test "render_width_with_style accounts for the Banner border" {
  // 29 base cols + 2 border cols = 31.
  assert_eq(render_width_with_style("Hello", Banner), 31)
}

///|
test "render_width_with_style accounts for the Shadow column" {
  // 29 base cols + 1 shadow col = 30.
  assert_eq(render_width_with_style("Hello", Shadow), 30)
}

///|
test "render returns render_lines joined with newlines" {
  let joined = render("Hello")
  let lines = render_lines("Hello")
  assert_eq(joined, lines.join("\n"))
}

///|
test "unknown but printable ASCII falls back gracefully" {
  // The grave accent is not in the table; it should not crash and
  // must still produce a 5-line output preserving the character.
  let lines = render_lines("`")
  assert_eq(lines.length(), 5)
  for line in lines {
    assert_eq(line.contains("`"), true)
  }
}
