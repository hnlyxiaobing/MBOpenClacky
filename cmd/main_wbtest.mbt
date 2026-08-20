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

///|
test "is_bare_message_flag: bare -m at end is bare" {
  assert_true(is_bare_message_flag(["-m"][:]))
  assert_true(is_bare_message_flag(["--message"][:]))
}

///|
test "is_bare_message_flag: -m followed by another flag is bare" {
  assert_true(is_bare_message_flag(["-m", "--verbose"][:]))
  assert_true(is_bare_message_flag(["--message", "-c"][:]))
}

///|
test "is_bare_message_flag: -m with a value is not bare" {
  assert_false(is_bare_message_flag(["-m", "hello"][:]))
  assert_false(is_bare_message_flag(["--message", "hi"][:]))
}

///|
test "is_bare_message_flag: no message flag is not bare" {
  assert_false(is_bare_message_flag(["--verbose", "-l"][:]))
  assert_false(is_bare_message_flag([]))
}

///|
test "parse_port: valid ports are parsed" {
  assert_eq(parse_port("8080", 7071), 8080)
  assert_eq(parse_port(" 3000 ", 7071), 3000)
  assert_eq(parse_port("1", 7071), 1)
  assert_eq(parse_port("65535", 7071), 65535)
}

///|
test "parse_port: invalid ports fall back" {
  assert_eq(parse_port("", 7071), 7071)
  assert_eq(parse_port("abc", 7071), 7071)
  assert_eq(parse_port("0", 7071), 7071)
  assert_eq(parse_port("65536", 7071), 7071)
  assert_eq(parse_port("-1", 7071), 7071)
}

///|
test "verify_channel: supported platforms pass" {
  assert_true(verify_channel("feishu") is Ok(_))
  assert_true(verify_channel("wecom") is Ok(_))
  assert_true(verify_channel("telegram") is Ok(_))
  assert_true(verify_channel("discord") is Ok(_))
  assert_true(verify_channel("dingtalk") is Ok(_))
  assert_true(verify_channel("weixin") is Ok(_))
}

///|
test "verify_channel: case-insensitive" {
  assert_true(verify_channel("Feishu") is Ok(_))
  assert_true(verify_channel("TELEGRAM") is Ok(_))
}

///|
test "verify_channel: unknown platform fails" {
  assert_true(verify_channel("slack") is Err(_))
  assert_true(verify_channel("") is Err(_))
}
