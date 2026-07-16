///| Extended utils tests: UTF-8 encoding, sanitization, truncation, binary detection.

// ── is_valid_utf8_content Tests ─────────────────────────────────────────────

///|
test "ext_is_valid_utf8_ascii" {
  assert_true(is_valid_utf8_content("hello world"))
  assert_true(is_valid_utf8_content(""))
}

///|
test "ext_is_valid_utf8_cjk" {
  assert_true(is_valid_utf8_content("中文"))
  assert_true(is_valid_utf8_content("こんにちは"))
  assert_true(is_valid_utf8_content("한국어"))
}

///|
test "ext_is_valid_utf8_emoji" {
  assert_true(is_valid_utf8_content("hello 😀 world"))
}

///|
test "ext_is_valid_utf8_mixed" {
  assert_true(is_valid_utf8_content("hello中文世界😀test"))
}

// ── sanitize_string Tests ───────────────────────────────────────────────────

///|
test "ext_sanitize_normal_string" {
  assert_eq(sanitize_string("hello"), "hello")
  assert_eq(sanitize_string(""), "")
}

///|
test "ext_sanitize_cjk_string" {
  assert_eq(sanitize_string("中文"), "中文")
  assert_eq(sanitize_string("hello中文"), "hello中文")
}

///|
test "ext_sanitize_preserves_emoji" {
  let input = "hello 😀 world"
  assert_eq(sanitize_string(input), input)
}

// ── safe_truncate Tests ──────────────────────────────────────────────────────

///|
test "ext_safe_truncate_short_string" {
  assert_eq(safe_truncate("hello", 10), "hello")
}

///|
test "ext_safe_truncate_exact_length" {
  assert_eq(safe_truncate("hello", 5), "hello")
}

///|
test "ext_safe_truncate_partial" {
  assert_eq(safe_truncate("hello world", 5), "hello")
}

///|
test "ext_safe_truncate_empty" {
  assert_eq(safe_truncate("", 5), "")
}

///|
test "ext_safe_truncate_zero" {
  assert_eq(safe_truncate("hello", 0), "")
}

///|
test "ext_safe_truncate_cjk" {
  let result = safe_truncate("中文测试", 2)
  assert_eq(result.length(), 2)
}

// ── strip_bom Tests ─────────────────────────────────────────────────────────

///|
test "ext_strip_bom_no_bom" {
  assert_eq(strip_bom("hello"), "hello")
  assert_eq(strip_bom(""), "")
}

///|
test "ext_strip_bom_with_bom" {
  let input = "\u{FEFF}hello"
  assert_eq(strip_bom(input), "hello")
}

///|
test "ext_strip_bom_only_bom" {
  let input = "\u{FEFF}"
  assert_eq(strip_bom(input), "")
}

///|
test "ext_strip_bom_cjk_with_bom" {
  let input = "\u{FEFF}中文"
  assert_eq(strip_bom(input), "中文")
}

// ── estimate_utf8_byte_length Tests ──────────────────────────────────────────

///|
test "ext_utf8_bytes_ascii" {
  assert_eq(estimate_utf8_byte_length("hello"), 5)
  assert_eq(estimate_utf8_byte_length(""), 0)
}

///|
test "ext_utf8_bytes_cjk" {
  assert_eq(estimate_utf8_byte_length("中"), 3)
  assert_eq(estimate_utf8_byte_length("中文"), 6)
}

///|
test "ext_utf8_bytes_mixed" {
  assert_eq(estimate_utf8_byte_length("a中b"), 5)
}

///|
test "ext_utf8_bytes_special" {
  assert_eq(estimate_utf8_byte_length("café"), 5)
}

// ── is_binary_content Tests ──────────────────────────────────────────────────

///|
test "ext_is_binary_empty" {
  assert_false(is_binary_content(""))
}

///|
test "ext_is_binary_plain_text" {
  assert_false(is_binary_content("hello world this is plain text"))
}

///|
test "ext_is_binary_cjk_text" {
  assert_false(is_binary_content("这是一段中文文本"))
}

///|
test "ext_is_binary_high_control_chars" {
  let chars : Array[Char] = []
  for i = 0; i < 20; i = i + 1 {
    chars.push('\u{01}')
  }
  for i = 0; i < 5; i = i + 1 {
    chars.push('a')
  }
  let text = String::from_array(chars)
  assert_true(is_binary_content(text))
}

///|
test "ext_is_binary_custom_threshold" {
  let chars : Array[Char] = []
  for i = 0; i < 10; i = i + 1 {
    chars.push('\u{01}')
  }
  for i = 0; i < 20; i = i + 1 {
    chars.push('a')
  }
  let text = String::from_array(chars)
  assert_false(is_binary_content(text, threshold=0.6))
}

///|
test "ext_is_binary_all_printable" {
  let text = "abcdefghijklmnopqrstuvwxyz0123456789!@#$%^&*()"
  assert_false(is_binary_content(text))
}

// ── Additional is_valid_utf8_content Tests ───────────────────────────────────

///|
test "ext_is_valid_utf8_numbers" {
  assert_true(is_valid_utf8_content("1234567890"))
}

///|
test "ext_is_valid_utf8_special_chars" {
  assert_true(is_valid_utf8_content("!@#$%^&*()"))
}

///|
test "ext_is_valid_utf8_newlines" {
  assert_true(is_valid_utf8_content("line1\nline2\nline3"))
}

///|
test "ext_is_valid_utf8_mixed_content" {
  assert_true(
    is_valid_utf8_content("Title: 中文标题\nContent: Hello 世界"),
  )
}

// ── Additional sanitize_string Tests ─────────────────────────────────────────

///|
test "ext_sanitize_with_newlines" {
  assert_eq(sanitize_string("hello\nworld"), "hello\nworld")
}

///|
test "ext_sanitize_with_tabs" {
  assert_eq(sanitize_string("hello\tworld"), "hello\tworld")
}

///|
test "ext_sanitize_numbers" {
  assert_eq(sanitize_string("12345"), "12345")
}

// ── Additional safe_truncate Tests ───────────────────────────────────────────

///|
test "ext_safe_truncate_one_char" {
  assert_eq(safe_truncate("hello", 1), "h")
}

///|
test "ext_safe_truncate_all_lengths" {
  let text = "abcdef"
  for i = 0; i <= text.length(); i = i + 1 {
    let result = safe_truncate(text, i)
    assert_eq(result.length(), i)
  }
}

///|
test "ext_safe_truncate_cjk_long" {
  let text = "这是一个很长的中文文本用于测试截断功能"
  let result = safe_truncate(text, 5)
  let chars = result.to_array()
  assert_true(chars.length() <= 5)
}

// ── Additional strip_bom Tests ───────────────────────────────────────────────

///|
test "ext_strip_bom_preserves_content" {
  let input = "\u{FEFF}Hello, World!"
  assert_eq(strip_bom(input), "Hello, World!")
}

///|
test "ext_strip_bom_preserves_newlines" {
  let input = "\u{FEFF}line1\nline2"
  assert_eq(strip_bom(input), "line1\nline2")
}

// ── Additional estimate_utf8_byte_length Tests ───────────────────────────────

///|
test "ext_utf8_bytes_long_ascii" {
  let text = "a".repeat(100)
  assert_eq(estimate_utf8_byte_length(text), 100)
}

///|
test "ext_utf8_bytes_emoji" {
  assert_eq(estimate_utf8_byte_length("😀"), 3)
}

///|
test "ext_utf8_bytes_mixed_long" {
  let text = "Hello世界This is a test"
  let bytes = estimate_utf8_byte_length(text)
  assert_true(bytes > text.length())
}

// ── Additional is_binary_content Tests ───────────────────────────────────────

///|
test "ext_is_binary_code_text" {
  assert_false(is_binary_content("function hello() { return 42; }"))
}

///|
test "ext_is_binary_json" {
  assert_false(is_binary_content("{\"key\": \"value\", \"num\": 42}"))
}

///|
test "ext_is_binary_all_control" {
  let chars : Array[Char] = []
  for i = 0; i < 10; i = i + 1 {
    chars.push('\u{01}')
  }
  let text = String::from_array(chars)
  assert_true(is_binary_content(text))
}
