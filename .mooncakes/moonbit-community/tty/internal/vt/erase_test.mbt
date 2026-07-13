///|
test "erase line sequences" {
  @debug.assert_eq(@vt.erase_line_right, b"\u{1b}[K")
  @debug.assert_eq(@vt.erase_line_left, b"\u{1b}[1K")
  @debug.assert_eq(@vt.erase_line_all, b"\u{1b}[2K")
}

///|
test "erase display sequences" {
  @debug.assert_eq(@vt.erase_display, b"\u{1b}[2J")
  @debug.assert_eq(@vt.erase_scrollback, b"\u{1b}[3J")
}
