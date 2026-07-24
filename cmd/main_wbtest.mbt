///| White-box tests for the public-binding security gate helper.

///|
test "is_loopback_host: 127.0.0.1 is loopback" {
  assert_true(is_loopback_host("127.0.0.1"))
}

///|
test "is_loopback_host: 127.x.x.x prefix is loopback" {
  assert_true(is_loopback_host("127.0.0.2"))
  assert_true(is_loopback_host("127.1.2.3"))
}

///|
test "is_loopback_host: IPv6 loopback variants" {
  assert_true(is_loopback_host("::1"))
  assert_true(is_loopback_host("[::1]"))
  assert_true(is_loopback_host("localhost"))
}

///|
test "is_loopback_host: 0.0.0.0 is NOT loopback (public binding)" {
  assert_false(is_loopback_host("0.0.0.0"))
}

///|
test "is_loopback_host: public addresses are not loopback" {
  assert_false(is_loopback_host("0.0.0.0"))
  assert_false(is_loopback_host("192.168.1.1"))
  assert_false(is_loopback_host("10.0.0.1"))
  assert_false(is_loopback_host("203.0.113.5"))
}

///|
test "is_loopback_host: empty string is not loopback" {
  assert_false(is_loopback_host(""))
}
