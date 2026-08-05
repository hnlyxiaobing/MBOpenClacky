///|
/// Tests for width-based line wrapping in OutputBuffer::append_text (P2-1).
///
/// Plain lines are wrapped at the buffer's configured width (CJK-aware);
/// lines carrying ANSI escape sequences are stored unchanged so the
/// escape sequences are never split.

///|
test "append_text wraps long lines at configured width" {
  let output = OutputBuffer::new()
  output.width = 10
  ignore(output.append_text("abcdefghijklmnop", OutputKind::Text))
  assert_eq(output.tail_lines(10), ["abcdefghij", "klmnop"])
}

///|
test "append_text wraps each newline-separated line independently" {
  let output = OutputBuffer::new()
  output.width = 5
  ignore(output.append_text("abc\ndefghijklmno", OutputKind::Text))
  assert_eq(output.tail_lines(10), ["abc", "defgh", "ijklm", "no"])
}

///|
test "append_text wraps CJK text by display width" {
  let output = OutputBuffer::new()
  // Each CJK character is 2 display columns wide
  output.width = 4
  ignore(output.append_text("你好啊", OutputKind::Text))
  assert_eq(output.tail_lines(10), ["你好", "啊"])
}

///|
test "append_text wraps lines with ANSI escape sequences" {
  let output = OutputBuffer::new()
  output.width = 5
  let styled = "\u{1b}[38;2;0;200;255mabcdefghij\u{1b}[0m"
  ignore(output.append_text(styled, OutputKind::Text))
  // ANSI-aware wrapping: SGR state carried across line breaks
  assert_eq(output.tail_lines(10), [
    "\u{1b}[38;2;0;200;255mabcde\u{1b}[0m", "\u{1b}[38;2;0;200;255mfghij\u{1b}[0m",
  ])
}

///|
test "append_text wraps at the default width of 80" {
  let output = OutputBuffer::new()
  let long_line = "x".repeat(100)
  ignore(output.append_text(long_line, OutputKind::Text))
  assert_eq(output.tail_lines(10), ["x".repeat(80), "x".repeat(20)])
}

///|
test "append_text keeps empty lines when wrapping" {
  let output = OutputBuffer::new()
  output.width = 10
  ignore(output.append_text("a\n\nb", OutputKind::Text))
  assert_eq(output.tail_lines(10), ["a", "", "b"])
}
