///|
test "sgr sequences" {
  @debug.assert_eq(@vt.bold, b"\u{1b}[1m")
  @debug.assert_eq(@vt.reset_bold, b"\u{1b}[22m")
  @debug.assert_eq(@vt.italic, b"\u{1b}[3m")
  @debug.assert_eq(@vt.reset_italic, b"\u{1b}[23m")
  @debug.assert_eq(@vt.underline, b"\u{1b}[4m")
  @debug.assert_eq(@vt.reset_underline, b"\u{1b}[24m")
  @debug.assert_eq(@vt.reverse, b"\u{1b}[7m")
  @debug.assert_eq(@vt.reset_reverse, b"\u{1b}[27m")
  @debug.assert_eq(@vt.sgr1(0), b"\u{1b}[0m")
  @debug.assert_eq(@vt.sgr3(38, 5, 42), b"\u{1b}[38;5;42m")
  @debug.assert_eq(@vt.sgr5(38, 2, 1, 127, 255), b"\u{1b}[38;2;1;127;255m")
}
