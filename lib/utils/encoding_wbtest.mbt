///| White-box tests for encoding.mbt (P2-4 coverage expansion).
///
/// Pure UTF-8 / string encoding helpers. Expected values are hand-computed
/// from the implementation; surrogate-pair edge cases are intentionally
/// limited to valid (ASCII / BMP) inputs to keep expectations unambiguous.

///|
test "is_valid_utf8_content: empty is valid" {
  assert_true(is_valid_utf8_content(""))
}

///|
test "is_valid_utf8_content: ascii is valid" {
  assert_true(is_valid_utf8_content("hello world"))
}

///|
test "is_valid_utf8_content: cjk is valid" {
  assert_true(is_valid_utf8_content("你好，世界"))
}

///|
test "estimate_utf8_byte_length: empty is zero" {
  assert_eq(estimate_utf8_byte_length(""), 0)
}

///|
test "estimate_utf8_byte_length: ascii is one byte each" {
  assert_eq(estimate_utf8_byte_length("abc"), 3)
}

///|
test "estimate_utf8_byte_length: latin1 char is two bytes" {
  assert_eq(estimate_utf8_byte_length("é"), 2)
}

///|
test "estimate_utf8_byte_length: bmp char is three bytes" {
  assert_eq(estimate_utf8_byte_length("中"), 3)
}

///|
test "estimate_utf8_byte_length: mixed widths sum correctly" {
  assert_eq(estimate_utf8_byte_length("a中b"), 5)
}

///|
test "sanitize_string: ascii passes through unchanged" {
  assert_eq(sanitize_string("abc"), "abc")
}

///|
test "sanitize_string: empty stays empty" {
  assert_eq(sanitize_string(""), "")
}

///|
test "sanitize_string: cjk preserved" {
  assert_eq(sanitize_string("中文"), "中文")
}

///|
test "safe_truncate: no-op when shorter than limit" {
  assert_eq(safe_truncate("hello", 5), "hello")
}

///|
test "safe_truncate: cuts at char boundary" {
  assert_eq(safe_truncate("hello", 3), "hel")
}

///|
test "safe_truncate: zero limit yields empty" {
  assert_eq(safe_truncate("ab", 0), "")
}

///|
test "safe_truncate: limit beyond length is no-op" {
  assert_eq(safe_truncate("ab", 10), "ab")
}

///|
test "strip_bom: no bom passes through" {
  assert_eq(strip_bom("abc"), "abc")
}

///|
test "strip_bom: leading bom removed" {
  assert_eq(strip_bom("\uFEFFabc"), "abc")
}

///|
test "strip_bom: empty stays empty" {
  assert_eq(strip_bom(""), "")
}

///|
test "is_binary_content: empty is not binary" {
  assert_false(is_binary_content(""))
}

///|
test "is_binary_content: normal text is not binary" {
  assert_false(is_binary_content("normal text here"))
}

///|
test "is_binary_content: newlines are tolerated" {
  assert_false(is_binary_content("line1\nline2\nline3"))
}

///|
test "is_binary_content: mostly control chars is binary" {
  assert_true(is_binary_content("\u007F\u007F\u007F"))
}
