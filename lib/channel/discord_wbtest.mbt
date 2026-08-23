///|
/// Table-driven tests for parse_iso8601_to_ms (Discord snowflake-adjacent
/// timestamp parsing) and Int64 timestamp handling (C8 fix).

///|
test "discord_parse_iso8601_table" {
  // (input, expected_ms)
  // Reference: 2026-01-02T03:04:05Z = 1767323045s
  let base : Int64 = 1767323045000L
  let cases : Array[(String, Int64)] = [
    // UTC with Z suffix
    ("2026-01-02T03:04:05Z", base),
    // UTC with +00:00 offset
    ("2026-01-02T03:04:05+00:00", base),
    // Positive offset: local time is ahead, UTC is earlier
    ("2026-01-02T05:04:05+02:00", base),
    // Negative offset: local time is behind, UTC is later
    ("2026-01-02T01:04:05-02:00", base),
    // Fractional seconds: .5s = 500ms
    ("2026-01-02T03:04:05.5Z", base + 500L),
    // Fractional seconds with 3 digits: .123s = 123ms
    ("2026-01-02T03:04:05.123Z", base + 123L),
    // Fractional seconds truncated to milliseconds: .123456 -> 123ms
    ("2026-01-02T03:04:05.123456Z", base + 123L),
    // Different date entirely: 1970-01-01T00:00:00Z = epoch 0
    ("1970-01-01T00:00:00Z", 0L),
    // One day after epoch
    ("1970-01-02T00:00:00Z", 86400000L),
  ]
  for idx = 0; idx < cases.length(); idx = idx + 1 {
    let input = cases[idx].0
    let expected = cases[idx].1
    let got = parse_iso8601_to_ms(input)
    if got != expected {
      fail(
        "parse_iso8601_to_ms(\{input}) = \{got.to_string()}, expected \{expected.to_string()}",
      )
    }
  }
}

///|
test "discord_parse_iso8601_invalid" {
  // Too short / malformed input returns 0 (honest failure sentinel)
  @debug.assert_eq(parse_iso8601_to_ms(""), 0L)
  @debug.assert_eq(parse_iso8601_to_ms("2026-01-02"), 0L)
  @debug.assert_eq(parse_iso8601_to_ms("garbage-input-!!"), 0L)
}

///|
test "discord_parse_iso8601_no_32bit_overflow" {
  // 2026 epoch ms ~ 1.78e12: far beyond 32-bit range. The result must
  // round-trip through Int64 without truncation (C8).
  let ms = parse_iso8601_to_ms("2026-06-17T00:00:00Z")
  assert_true(ms > 1700000000000L)
  assert_true(ms < 2000000000000L)
}

///|
test "feishu_parse_int_safe_13_digit_ms" {
  // Feishu create_time is a 13-digit millisecond-epoch string that
  // overflows Int; parse_int_safe must hold it in Int64.
  @debug.assert_eq(parse_int_safe("1784678400000"), 1784678400000L)
  @debug.assert_eq(parse_int_safe("0"), 0L)
  // Trailing garbage stops the parse (prefix semantics)
  @debug.assert_eq(parse_int_safe("123abc"), 123L)
}
