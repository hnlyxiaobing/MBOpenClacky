///| Extended tool tests: ANSI cleaning, control char stripping, truncation.

// ── clean_ansi_output Tests ──────────────────────────────────────────────────

///|
test "ext_clean_ansi_plain_text" {
  assert_eq(clean_ansi_output("hello world"), "hello world")
}

///|
test "ext_clean_ansi_empty" {
  assert_eq(clean_ansi_output(""), "")
}

///|
test "ext_clean_ansi_color_codes" {
  let input = "\u{1b}[31mhello\u{1b}[0m"
  assert_eq(clean_ansi_output(input), "hello")
}

///|
test "ext_clean_ansi_multiple_codes" {
  let input = "\u{1b}[1;31mError\u{1b}[0m: \u{1b}[32mOK\u{1b}[0m"
  assert_eq(clean_ansi_output(input), "Error: OK")
}

///|
test "ext_clean_ansi_cursor_movement" {
  let input = "\u{1b}[2Jhello"
  assert_eq(clean_ansi_output(input), "hello")
}

///|
test "ext_clean_ansi_clear_line" {
  let input = "abc\u{1b}[2Kdef"
  assert_eq(clean_ansi_output(input), "abcdef")
}

///|
test "ext_clean_ansi_osc_sequence" {
  let input = "\u{1b}]0;title\u{0007}hello"
  assert_eq(clean_ansi_output(input), "hello")
}

///|
test "ext_clean_ansi_preserves_newlines" {
  let input = "line1\nline2\nline3"
  assert_eq(clean_ansi_output(input), "line1\nline2\nline3")
}

///|
test "ext_clean_ansi_mixed_content" {
  let input = "\u{1b}[32m✓\u{1b}[0m done\n\u{1b}[31m✗\u{1b}[0m failed"
  let result = clean_ansi_output(input)
  assert_true(result.contains("done"))
  assert_true(result.contains("failed"))
  assert_false(result.contains("\u{1b}"))
}

// ── strip_control_chars Tests ───────────────────────────────────────────────

///|
test "ext_strip_control_plain_text" {
  assert_eq(strip_control_chars("hello"), "hello")
}

///|
test "ext_strip_control_empty" {
  assert_eq(strip_control_chars(""), "")
}

///|
test "ext_strip_control_preserves_newlines" {
  assert_eq(strip_control_chars("hello\nworld"), "hello\nworld")
}

///|
test "ext_strip_control_preserves_tabs" {
  assert_eq(strip_control_chars("hello\tworld"), "hello\tworld")
}

///|
test "ext_strip_control_removes_null" {
  let input = "he\u{0000}llo"
  assert_eq(strip_control_chars(input), "hello")
}

///|
test "ext_strip_control_removes_bell" {
  let input = "alert\u{0007}!"
  assert_eq(strip_control_chars(input), "alert!")
}

///|
test "ext_strip_control_mixed" {
  let input = "a\u{0001}b\u{0002}c\n\u{0003}d"
  assert_eq(strip_control_chars(input), "abc\nd")
}

// ── truncate_output Tests ────────────────────────────────────────────────────

///|
test "ext_truncate_short" {
  let (result, truncated) = truncate_output("hello", max_chars=100)
  assert_eq(result, "hello")
  assert_false(truncated)
}

///|
test "ext_truncate_exact_length" {
  let (result, truncated) = truncate_output("hello", max_chars=5)
  assert_eq(result, "hello")
  assert_false(truncated)
}

///|
test "ext_truncate_long" {
  // smart truncation: head 60% + tail 40% with a notice in between
  let (result, truncated) = truncate_output("hello world", max_chars=5)
  assert_true(truncated)
  assert_true(result.contains("hel"))
  assert_true(result.contains("ld"))
  assert_true(result.contains("truncated"))
}

///|
test "ext_truncate_empty" {
  let (result, truncated) = truncate_output("", max_chars=100)
  assert_eq(result, "")
  assert_false(truncated)
}

///|
test "ext_truncate_default_max" {
  let short = "a".repeat(100)
  let (result, truncated) = truncate_output(short)
  assert_eq(result, short)
  assert_false(truncated)
}

// ── process_terminal_output Tests ───────────────────────────────────────────

///|
test "ext_process_output_plain" {
  let (result, truncated) = process_terminal_output("hello", max_chars=100)
  assert_eq(result, "hello")
  assert_false(truncated)
}

///|
test "ext_process_output_with_ansi" {
  let input = "\u{1b}[31mhello\u{1b}[0m"
  let (result, _) = process_terminal_output(input, max_chars=100)
  assert_eq(result, "hello")
}

///|
test "ext_process_output_with_control_chars" {
  let input = "he\u{0000}llo"
  let (result, _) = process_terminal_output(input, max_chars=100)
  assert_eq(result, "hello")
}

///|
test "ext_process_output_full_pipeline" {
  let input = "\u{1b}[32mtest\u{1b}[0m\u{0001}\nline2"
  let (result, _) = process_terminal_output(input, max_chars=100)
  assert_eq(result, "test\nline2")
}

// ── truncate_long_lines Tests ────────────────────────────────────────────────

///|
test "ext_truncate_lines_short" {
  assert_eq(truncate_long_lines("hello", max_chars=100), "hello")
}

///|
test "ext_truncate_lines_exact" {
  assert_eq(truncate_long_lines("hello", max_chars=5), "hello")
}

///|
test "ext_truncate_lines_long" {
  let line = "a".repeat(100)
  let result = truncate_long_lines(line, max_chars=10)
  assert_true(result.contains("[line truncated]"))
  assert_true(result.contains("a".repeat(10)))
}

///|
test "ext_truncate_lines_multiline" {
  let input = "short\n" + "a".repeat(100) + "\nalso short"
  let result = truncate_long_lines(input, max_chars=10)
  assert_true(result.contains("short"))
  assert_true(result.contains("[line truncated]"))
}

///|
test "ext_truncate_lines_empty" {
  assert_eq(truncate_long_lines("", max_chars=100), "")
}

///|
test "ext_max_line_chars_constant" {
  assert_eq(max_line_chars, 500)
}

// ── strip_command_echo Tests ─────────────────────────────────────────────────

///|
test "ext_strip_echo_empty_output" {
  assert_eq(strip_command_echo("", "echo hello"), "")
}

///|
test "ext_strip_echo_empty_command" {
  assert_eq(strip_command_echo("hello", ""), "hello")
}

///|
test "ext_strip_echo_exact_match" {
  let output = "echo hello\nhello"
  let result = strip_command_echo(output, "echo hello")
  assert_false(result.contains("echo hello"))
}

///|
test "ext_strip_echo_with_prompt" {
  let output = "$ echo hello\nhello"
  let result = strip_command_echo(output, "echo hello")
  assert_false(result.contains("$ echo hello"))
}

///|
test "ext_strip_echo_no_match" {
  let output = "hello world"
  let result = strip_command_echo(output, "echo hello")
  assert_eq(result, "hello world")
}

// ── Additional clean_ansi_output Tests ──────────────────────────────────────

///|
test "ext_clean_ansi_nested_sequences" {
  let input = "\u{1b}[1m\u{1b}[31mBold Red\u{1b}[0m\u{1b}[0m"
  assert_eq(clean_ansi_output(input), "Bold Red")
}

///|
test "ext_clean_ansi_with_newlines_and_color" {
  let input = "\u{1b}[32mok\u{1b}[0m\n\u{1b}[31mfail\u{1b}[0m"
  let result = clean_ansi_output(input)
  assert_true(result.contains("\n"))
  assert_false(result.contains("\u{1b}"))
}

///|
test "ext_clean_ansi_multiple_osc" {
  let input = "\u{1b}]0;Title1\u{0007}\u{1b}]0;Title2\u{0007}Content"
  assert_eq(clean_ansi_output(input), "Content")
}

///|
test "ext_clean_ansi_only_escape" {
  assert_eq(clean_ansi_output("\u{1b}"), "")
}

// ── Additional strip_control_chars Tests ────────────────────────────────────

///|
test "ext_strip_control_preserves_cr" {
  assert_eq(strip_control_chars("hello\r\nworld"), "hello\r\nworld")
}

///|
test "ext_strip_control_all_control_range" {
  let chars : Array[Char] = []
  for i = 0; i < 0x20; i = i + 1 {
    if i != 0x0a && i != 0x0d && i != 0x09 {
      chars.push(i.unsafe_to_char())
    }
  }
  chars.push('a')
  let text = String::from_array(chars)
  assert_eq(strip_control_chars(text), "a")
}

// ── Additional truncate_output Tests ────────────────────────────────────────

///|
test "ext_truncate_one_char" {
  let (result, truncated) = truncate_output("hello", max_chars=1)
  assert_true(truncated)
  assert_true(result.contains("h"))
}

///|
test "ext_truncate_exact_boundary" {
  let (result, truncated) = truncate_output("hello world", max_chars=11)
  assert_false(truncated)
  assert_eq(result, "hello world")
}

// ── Additional process_terminal_output Tests ────────────────────────────────

///|
test "ext_process_output_empty" {
  let (result, truncated) = process_terminal_output("", max_chars=100)
  assert_eq(result, "")
  assert_false(truncated)
}

///|
test "ext_process_output_truncation" {
  let input = "a".repeat(200)
  let (_, truncated) = process_terminal_output(input, max_chars=50)
  assert_true(truncated)
}

// ── Additional truncate_long_lines Tests ────────────────────────────────────

///|
test "ext_truncate_lines_default_max" {
  let short = "a".repeat(100)
  assert_eq(truncate_long_lines(short), short)
}

///|
test "ext_truncate_lines_many_short_lines" {
  let lines : Array[String] = []
  for i = 0; i < 10; i = i + 1 {
    lines.push("line" + i.to_string())
  }
  let input = lines.join("\n")
  assert_eq(truncate_long_lines(input, max_chars=100), input)
}

// ── Additional strip_command_echo Tests ─────────────────────────────────────

///|
test "ext_strip_echo_with_greater_than" {
  let output = "> echo hello\nhello"
  let result = strip_command_echo(output, "echo hello")
  assert_false(result.contains("> echo hello"))
}

///|
test "ext_strip_echo_multiline_command" {
  let output = "echo hello\necho hello\nresult"
  let result = strip_command_echo(output, "echo hello")
  assert_true(result.contains("result"))
}
