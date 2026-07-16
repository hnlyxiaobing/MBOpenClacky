///|
test "format_bytes_zero" {
  assert_eq(format_bytes(0), "0 B")
}

///|
test "format_bytes_small" {
  assert_eq(format_bytes(1), "1 B")
  assert_eq(format_bytes(100), "100 B")
  assert_eq(format_bytes(512), "512 B")
  assert_eq(format_bytes(1023), "1023 B")
}

///|
test "format_bytes_exactly_1kb" {
  let result = format_bytes(1024)
  assert_eq(result, "0.01 KB")
}

///|
test "format_bytes_2kb" {
  let result = format_bytes(2048)
  assert_eq(result, "0.02 KB")
}

///|
test "format_bytes_large_values" {
  let mb = format_bytes(1048576)
  assert_eq(mb, "0.01 MB")
}
