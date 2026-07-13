///| Tests for ANSI output cleaner and terminal output processing.

///|
test "clean_ansi_output removes color codes" {
  let esc = (0x1b).unsafe_to_char().to_string()
  let input = esc + "[31mERROR" + esc + "[0m: something failed"
  let result = clean_ansi_output(input)
  @debug.assert_eq(result, "ERROR: something failed")
}

///|
test "clean_ansi_output removes cursor movement" {
  let esc = (0x1b).unsafe_to_char().to_string()
  let input = esc + "[2J" + esc + "[H Hello"
  let result = clean_ansi_output(input)
  @debug.assert_eq(result, " Hello")
}

///|
test "clean_ansi_output removes complex sequences" {
  let esc = (0x1b).unsafe_to_char().to_string()
  let input = esc +
    "[1;32mbold green" +
    esc +
    "[0m normal " +
    esc +
    "[4munderline" +
    esc +
    "[24m"
  let result = clean_ansi_output(input)
  @debug.assert_eq(result, "bold green normal underline")
}

///|
test "clean_ansi_output handles OSC sequences" {
  // OSC title set: ESC ] 0 ; title BEL
  let esc = (0x1b).unsafe_to_char().to_string()
  let bel = (0x07).unsafe_to_char().to_string()
  let input = esc + "]0;my title" + bel + "Hello world"
  let result = clean_ansi_output(input)
  @debug.assert_eq(result, "Hello world")
}

///|
test "clean_ansi_output passthrough plain text" {
  let input = "no escape sequences here"
  let result = clean_ansi_output(input)
  @debug.assert_eq(result, "no escape sequences here")
}

///|
test "strip_control_chars preserves newlines and tabs" {
  let input = "line1\nline2\ttab\rreturn"
  let result = strip_control_chars(input)
  @debug.assert_eq(result, "line1\nline2\ttab\rreturn")
}

///|
test "strip_control_chars removes null and other controls" {
  let nul = (0).unsafe_to_char().to_string()
  let soh = (1).unsafe_to_char().to_string()
  let stx = (2).unsafe_to_char().to_string()
  let input = "hello" + nul + soh + stx + "world"
  let result = strip_control_chars(input)
  @debug.assert_eq(result, "helloworld")
}

///|
test "truncate_output no truncation needed" {
  let text = "short output"
  let (result, truncated) = truncate_output(text, max_chars=100)
  assert_false(truncated)
  @debug.assert_eq(result, "short output")
}

///|
test "truncate_output marks truncation" {
  let long_text = "a".repeat(200)
  let (result, truncated) = truncate_output(long_text, max_chars=100)
  assert_true(truncated)
  assert_true(result.has_prefix("a".repeat(100)))
  assert_true(result.find("[output truncated") is Some(_))
}

///|
test "process_terminal_output full pipeline" {
  let esc = (0x1b).unsafe_to_char().to_string()
  let input = esc + "[1;32m$ ls" + esc + "[0m\nfile1.txt\nfile2.txt"
  let (result, truncated) = process_terminal_output(input)
  assert_false(truncated)
  @debug.assert_eq(result, "$ ls\nfile1.txt\nfile2.txt")
}

///|
test "process_terminal_output with control chars and ANSI" {
  let esc = (0x1b).unsafe_to_char().to_string()
  let nul = (0).unsafe_to_char().to_string()
  let soh = (1).unsafe_to_char().to_string()
  let input = esc + "[36mhello" + esc + "[0m" + nul + soh + "world\nend"
  let (result, _) = process_terminal_output(input)
  @debug.assert_eq(result, "helloworld\nend")
}
