///|
/// Tests for BlockFont rendering.

///|
test "BlockFont::new defaults" {
  let font = BlockFont::new()
  @debug.assert_eq(font.style, Full)
  @debug.assert_eq(font.letter_spacing, 1)
}

///|
test "BlockFont::with_style creates correct style" {
  let font = BlockFont::with_style(Half)
  @debug.assert_eq(font.style, Half)
  @debug.assert_eq(font.letter_spacing, 1)
}

///|
test "BlockFont::char_width returns 5" {
  let font = BlockFont::new()
  @debug.assert_eq(font.char_width(), 5)
}

///|
test "BlockFont::height returns 5" {
  @debug.assert_eq(BlockFont::height(), 5)
}

///|
test "BlockFont::render_char produces 5 lines for A" {
  let font = BlockFont::new()
  let lines = font.render_char('A')
  @debug.assert_eq(lines.length(), 5)
  // Check that each line has 5 characters
  for line in lines {
    @debug.assert_eq(line.length(), 5)
  }
}

///|
test "BlockFont::render_char Full style A" {
  let font = BlockFont::new()
  let lines = font.render_char('A')
  // A should look like:
  //  ███
  // █   █
  // █████
  // █   █
  // █   █
  @debug.assert_eq(lines[0], " ███ ")
  @debug.assert_eq(lines[1], "█   █")
  @debug.assert_eq(lines[2], "█████")
  @debug.assert_eq(lines[3], "█   █")
  @debug.assert_eq(lines[4], "█   █")
}

///|
test "BlockFont::render_char Outline style A" {
  let font = BlockFont::with_style(Outline)
  let lines = font.render_char('A')
  @debug.assert_eq(lines[0], "░▓▓▓░")
  @debug.assert_eq(lines[2], "▓▓▓▓▓")
}

///|
test "BlockFont::render_char Half style A" {
  let font = BlockFont::with_style(Half)
  let lines = font.render_char('A')
  @debug.assert_eq(lines[0], " ▀▀▀ ")
  @debug.assert_eq(lines[2], "▀▀▀▀▀")
}

///|
test "BlockFont::render_char lowercase converts to uppercase" {
  let font = BlockFont::new()
  let lower = font.render_char('a')
  let upper = font.render_char('A')
  @debug.assert_eq(lower[0], upper[0])
  @debug.assert_eq(lower[2], upper[2])
}

///|
test "BlockFont::render_char space is all empty" {
  let font = BlockFont::new()
  let lines = font.render_char(' ')
  for line in lines {
    @debug.assert_eq(line, "     ")
  }
}

///|
test "BlockFont::render_text produces 5 lines" {
  let font = BlockFont::new()
  let lines = font.render_text("AB")
  @debug.assert_eq(lines.length(), 5)
  // Each line should be 5 + 1 (spacing) + 5 = 11 chars
  for line in lines {
    @debug.assert_eq(line.length(), 11)
  }
}

///|
test "BlockFont::render_text empty string" {
  let font = BlockFont::new()
  let lines = font.render_text("")
  @debug.assert_eq(lines.length(), 5)
  for line in lines {
    @debug.assert_eq(line, "")
  }
}

///|
test "BlockFont::render_text single char" {
  let font = BlockFont::new()
  let lines = font.render_text("A")
  @debug.assert_eq(lines.length(), 5)
  @debug.assert_eq(lines[0], " ███ ")
}
