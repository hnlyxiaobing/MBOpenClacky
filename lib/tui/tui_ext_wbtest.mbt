///| Extended TUI tests: CJK display width, line wrapping, cursor positioning.

// ── char_display_width Tests ─────────────────────────────────────────────────

///|
test "ext_char_width_ascii" {
  assert_eq(@tui_core.char_display_width('a'), 1)
  assert_eq(@tui_core.char_display_width('A'), 1)
  assert_eq(@tui_core.char_display_width('1'), 1)
  assert_eq(@tui_core.char_display_width(' '), 1)
  assert_eq(@tui_core.char_display_width('!'), 1)
  assert_eq(@tui_core.char_display_width('\n'), 1)
}

///|
test "ext_char_width_cjk" {
  assert_eq(@tui_core.char_display_width('中'), 2)
  assert_eq(@tui_core.char_display_width('文'), 2)
  assert_eq(@tui_core.char_display_width('あ'), 2)
  assert_eq(@tui_core.char_display_width('한'), 2)
}

///|
test "ext_char_width_fullwidth" {
  assert_eq(@tui_core.char_display_width('Ａ'), 2)
  assert_eq(@tui_core.char_display_width('１'), 2)
}

// ── string_display_width Tests ───────────────────────────────────────────────

///|
test "ext_string_width_empty" {
  assert_eq(@tui_core.string_display_width(""), 0)
}

///|
test "ext_string_width_ascii" {
  assert_eq(@tui_core.string_display_width("hello"), 5)
  assert_eq(@tui_core.string_display_width("hello world"), 11)
}

///|
test "ext_string_width_cjk" {
  assert_eq(@tui_core.string_display_width("中文"), 4)
  assert_eq(@tui_core.string_display_width("你好"), 4)
}

///|
test "ext_string_width_mixed" {
  assert_eq(@tui_core.string_display_width("hello中文"), 9)
  assert_eq(@tui_core.string_display_width("a中b文c"), 7)
}

// ── wrap_line_at_width Tests ────────────────────────────────────────────────

///|
test "ext_wrap_short_line" {
  let result = wrap_line_at_width("hello", 10)
  assert_eq(result.length(), 1)
  assert_eq(result[0], "hello")
}

///|
test "ext_wrap_exact_width" {
  let result = wrap_line_at_width("hello", 5)
  assert_eq(result.length(), 1)
  assert_eq(result[0], "hello")
}

///|
test "ext_wrap_long_ascii" {
  let result = wrap_line_at_width("hello world", 5)
  assert_true(result.length() >= 2)
  assert_eq(result[0], "hello")
}

///|
test "ext_wrap_empty_line" {
  let result = wrap_line_at_width("", 5)
  assert_eq(result.length(), 1)
  assert_eq(result[0], "")
}

///|
test "ext_wrap_cjk_boundary" {
  let result = wrap_line_at_width("中文", 2)
  assert_eq(result.length(), 2)
  assert_eq(result[0], "中")
  assert_eq(result[1], "文")
}

///|
test "ext_wrap_mixed_cjk" {
  let result = wrap_line_at_width("a中b文c", 3)
  assert_true(result.length() >= 2)
}

///|
test "ext_wrap_zero_width" {
  let result = wrap_line_at_width("hello", 0)
  assert_eq(result.length(), 1)
  assert_eq(result[0], "hello")
}

// ── cursor_display_col Tests ─────────────────────────────────────────────────

///|
test "ext_cursor_col_ascii" {
  assert_eq(cursor_display_col("hello", 0), 0)
  assert_eq(cursor_display_col("hello", 2), 2)
  assert_eq(cursor_display_col("hello", 5), 5)
}

///|
test "ext_cursor_col_cjk" {
  assert_eq(cursor_display_col("中文", 0), 0)
  assert_eq(cursor_display_col("中文", 1), 2)
  assert_eq(cursor_display_col("中文", 2), 4)
}

///|
test "ext_cursor_col_mixed" {
  assert_eq(cursor_display_col("hello中文", 5), 5)
  assert_eq(cursor_display_col("hello中文", 6), 7)
}

// ── display_col_to_char_index Tests ──────────────────────────────────────────

///|
test "ext_display_col_to_index_ascii" {
  assert_eq(display_col_to_char_index("hello", 0), 0)
  assert_eq(display_col_to_char_index("hello", 2), 2)
  assert_eq(display_col_to_char_index("hello", 5), 5)
}

///|
test "ext_display_col_to_index_cjk" {
  assert_eq(display_col_to_char_index("中文", 0), 0)
  assert_eq(display_col_to_char_index("中文", 2), 1)
  assert_eq(display_col_to_char_index("中文", 4), 2)
}

///|
test "ext_display_col_to_index_mixed" {
  assert_eq(display_col_to_char_index("hello中文", 5), 5)
  assert_eq(display_col_to_char_index("hello中文", 7), 6)
}

///|
test "ext_display_col_round_trip" {
  let line = "hello中文world"
  for i = 0; i < 10; i = i + 1 {
    let col = cursor_display_col(line, i)
    let back = display_col_to_char_index(line, col)
    assert_true(back <= i)
  }
}

// ── Additional char_display_width Tests ──────────────────────────────────────

///|
test "ext_char_width_digits" {
  assert_eq(@tui_core.char_display_width('0'), 1)
  assert_eq(@tui_core.char_display_width('9'), 1)
}

///|
test "ext_char_width_special_chars" {
  assert_eq(@tui_core.char_display_width('!'), 1)
  assert_eq(@tui_core.char_display_width('@'), 1)
  assert_eq(@tui_core.char_display_width('#'), 1)
}

///|
test "ext_char_width_japanese" {
  assert_eq(@tui_core.char_display_width('あ'), 2)
  assert_eq(@tui_core.char_display_width('ア'), 2)
  assert_eq(@tui_core.char_display_width('日'), 2)
}

///|
test "ext_char_width_korean" {
  assert_eq(@tui_core.char_display_width('한'), 2)
  assert_eq(@tui_core.char_display_width('국'), 2)
}

// ── Additional string_display_width Tests ────────────────────────────────────

///|
test "ext_string_width_single_char" {
  assert_eq(@tui_core.string_display_width("a"), 1)
  assert_eq(@tui_core.string_display_width("中"), 2)
}

///|
test "ext_string_width_long_mixed" {
  let s = "Hello世界This is test"
  let width = @tui_core.string_display_width(s)
  assert_eq(
    width,
    @tui_core.string_display_width("Hello") +
    @tui_core.string_display_width("世界") +
    @tui_core.string_display_width("This is test"),
  )
}

// ── Additional wrap_line_at_width Tests ──────────────────────────────────────

///|
test "ext_wrap_single_char" {
  let result = wrap_line_at_width("a", 1)
  assert_eq(result.length(), 1)
  assert_eq(result[0], "a")
}

///|
test "ext_wrap_all_cjk_fits" {
  let result = wrap_line_at_width("中文", 4)
  assert_eq(result.length(), 1)
  assert_eq(result[0], "中文")
}

///|
test "ext_wrap_very_long_line" {
  let long = "a".repeat(50)
  let result = wrap_line_at_width(long, 10)
  assert_eq(result.length(), 5)
}

// ── Additional cursor_display_col Tests ──────────────────────────────────────

///|
test "ext_cursor_col_empty_string" {
  assert_eq(cursor_display_col("", 0), 0)
  assert_eq(cursor_display_col("", 5), 0)
}

///|
test "ext_cursor_col_beyond_end" {
  assert_eq(cursor_display_col("abc", 100), 3)
  assert_eq(cursor_display_col("中文", 100), 4)
}

// ── Additional display_col_to_char_index Tests ───────────────────────────────

///|
test "ext_display_col_to_index_empty" {
  assert_eq(display_col_to_char_index("", 0), 0)
  assert_eq(display_col_to_char_index("", 5), 0)
}

///|
test "ext_display_col_to_index_beyond_end" {
  assert_eq(display_col_to_char_index("abc", 100), 3)
  assert_eq(display_col_to_char_index("中文", 100), 2)
}

///|
test "ext_display_col_to_index_mid_cjk" {
  assert_eq(display_col_to_char_index("中", 1), 0)
  assert_eq(display_col_to_char_index("中", 2), 1)
}
