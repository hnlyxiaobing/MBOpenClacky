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

///|
/// BUG-0060 回归：`-f/--file`、`-i/--image` 的 raw-argv 预扫描。
/// 语义对齐 Ruby/optimist 的 `type: :array`：一次出现贪婪收集多个值，
/// 列表在下个形如选项的 token 处结束，同一 flag 再次出现则覆盖前一次。
test "extract_attachment_flags: greedy multi-value then option boundary" {
  let files : Array[String] = []
  let images : Array[String] = []
  let argv : Array[String] = ["-m", "hi", "-f", "a.txt", "b.txt", "-i", "c.png"]
  let rest = extract_attachment_flags(argv[:], files, images)
  assert_eq(files.length(), 2)
  assert_eq(files[0], "a.txt")
  assert_eq(files[1], "b.txt")
  assert_eq(images.length(), 1)
  assert_eq(images[0], "c.png")
  assert_eq(rest.length(), 2)
  assert_eq(rest[0], "-m")
  assert_eq(rest[1], "hi")
}

///|
test "extract_attachment_flags: repeated flag replaces the earlier list" {
  let files : Array[String] = []
  let images : Array[String] = []
  let argv : Array[String] = ["-f", "a.txt", "-f", "b.txt"]
  let _ = extract_attachment_flags(argv[:], files, images)
  assert_eq(files.length(), 1)
  assert_eq(files[0], "b.txt")
}

///|
test "extract_attachment_flags: long forms and no flags" {
  let files : Array[String] = []
  let images : Array[String] = []
  let _ = extract_attachment_flags(
    ["--file", "a.txt", "--image", "b.png"][:],
    files,
    images,
  )
  assert_eq(files[0], "a.txt")
  assert_eq(images[0], "b.png")
  let f2 : Array[String] = []
  let i2 : Array[String] = []
  let rest = extract_attachment_flags(["-m", "hi"][:], f2, i2)
  assert_eq(f2.length(), 0)
  assert_eq(i2.length(), 0)
  assert_eq(rest.length(), 2)
}

///|
test "looks_like_cli_option: flags yes, lone dash and values no" {
  assert_true(looks_like_cli_option("-f"))
  assert_true(looks_like_cli_option("--file"))
  assert_false(looks_like_cli_option("-"))
  assert_false(looks_like_cli_option("a.txt"))
  assert_false(looks_like_cli_option(""))
}
