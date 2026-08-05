///|
/// Unit tests for the borderless input area: 90% content width, auto-wrap
/// rendering, and wrapped cursor positioning (Ruby ui2 input_area parity).

///|
test "effective_content_width is 90% of the terminal width" {
  assert_eq(effective_content_width(100), 90)
  assert_eq(effective_content_width(80), 72)
  assert_eq(effective_content_width(41), 36)
  // Never zero on tiny terminals.
  assert_eq(effective_content_width(1), 1)
}

///|
test "render_wrapped_lines: empty input shows prompt + placeholder" {
  let input = InputArea::multiline_new()
  let lines = input.render_wrapped_lines(72)
  assert_eq(lines.length(), 1)
  assert_true(lines[0].has_prefix("[>>] "))
  assert_true(lines[0].contains("Type a message"))
}

///|
test "render_wrapped_lines: first line gets prompt, later lines get indent" {
  let input = InputArea::multiline_new()
  input.insert_text("abc\ndef")
  let lines = input.render_wrapped_lines(72)
  assert_eq(lines.length(), 2)
  assert_eq(lines[0], "[>>] abc")
  assert_eq(lines[1], "     def") // indented by prompt width (5)
}

///|
test "render_wrapped_lines: long lines wrap at content width minus prompt" {
  let input = InputArea::multiline_new()
  input.insert_text("x".repeat(100))
  // content width 72, prompt 5 → segments of at most 67 columns.
  let lines = input.render_wrapped_lines(72)
  assert_eq(lines.length(), 2)
  assert_eq(lines[0].length(), 5 + 67)
  assert_eq(lines[1].length(), 5 + 33)
  // Continuation segment is indented by the prompt width.
  assert_true(lines[1].has_prefix("     "))
}

///|
test "cursor_display_pos_wrapped: cursor maps onto the wrapped grid" {
  let input = InputArea::multiline_new()
  input.insert_text("x".repeat(100))
  // Cursor is at the end (char 100): segment 2, column 5 + 33.
  let (row, col) = input.cursor_display_pos_wrapped(72)
  assert_eq(row, 1)
  assert_eq(col, 5 + 33)
}

///|
test "cursor_display_pos_wrapped: multi-line input counts prior wrapped rows" {
  let input = InputArea::multiline_new()
  input.insert_text("x".repeat(100) + "\ny")
  // Line 0 wraps into 2 rows; cursor is on logical line 1, char 1.
  let (row, col) = input.cursor_display_pos_wrapped(72)
  assert_eq(row, 2)
  assert_eq(col, 5 + 1)
}
