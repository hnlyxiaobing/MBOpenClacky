///|
test "limit_stack push pop" {
  let stack = LimitStack::new(max_depth=5)
  assert_true(stack.push(label="a"))
  assert_true(stack.push(label="b"))
  assert_eq(stack.depth(), 2)
  stack.pop()
  assert_eq(stack.depth(), 1)
  stack.pop()
  assert_eq(stack.depth(), 0)
}

///|
test "limit_stack exceeded" {
  let stack = LimitStack::new(max_depth=3)
  assert_true(stack.push(label="1"))
  assert_true(stack.push(label="2"))
  assert_true(stack.push(label="3"))
  assert_false(stack.push(label="4"))
  assert_true(stack.is_exceeded())
  assert_eq(stack.remaining(), 0)
}

///|
test "limit_stack reset" {
  let stack = LimitStack::new(max_depth=5)
  assert_true(stack.push(label="x"))
  assert_true(stack.push(label="y"))
  stack.reset()
  assert_eq(stack.depth(), 0)
  assert_eq(stack.remaining(), 5)
  assert_eq(stack.stack_trace().length(), 0)
}

///|
test "glob_match basic patterns" {
  assert_true(glob_match("hello", "hello"))
  assert_false(glob_match("hello", "world"))
  assert_true(glob_match("", ""))
  assert_false(glob_match("a", ""))
}

///|
test "glob_match star wildcard" {
  assert_true(glob_match("*", "anything"))
  assert_true(glob_match("h*o", "hello"))
  assert_true(glob_match("*.txt", "file.txt"))
  assert_false(glob_match("*.txt", "file.md"))
  assert_true(glob_match("*.*", "file.txt"))
  assert_true(glob_match("**", "abc"))
}

///|
test "glob_match question mark" {
  assert_true(glob_match("h?llo", "hello"))
  assert_false(glob_match("h?llo", "hllo"))
  assert_true(glob_match("?", "a"))
  assert_false(glob_match("?", ""))
  assert_true(glob_match("a?c", "abc"))
}

///|
test "levenshtein_distance identical" {
  assert_eq(levenshtein_distance("hello", "hello"), 0)
  assert_eq(levenshtein_distance("", ""), 0)
}

///|
test "levenshtein_distance one_edit" {
  assert_eq(levenshtein_distance("cat", "hat"), 1)
  assert_eq(levenshtein_distance("cat", "cats"), 1)
  assert_eq(levenshtein_distance("cat", "at"), 1)
}

///|
test "fuzzy_match within threshold" {
  assert_true(fuzzy_match("hello", "helo", max_distance=2))
  assert_false(fuzzy_match("hello", "world", max_distance=2))
  assert_true(fuzzy_match("abc", "abc", max_distance=0))
}

///|
test "similarity_score perfect" {
  assert_eq(similarity_score("hello", "hello"), 1.0)
  assert_eq(similarity_score("", ""), 1.0)
  assert_true(similarity_score("cat", "hat") > 0.6)
}

///|
test "best_match finds closest" {
  let candidates = ["apple", "application", "apply", "banana"]
  match best_match("appl", candidates) {
    Some(result) => assert_true(result == "apply" || result == "apple")
    None => fail("expected Some")
  }
}

///|
test "sanitize_string removes invalid" {
  // Normal ASCII stays unchanged
  assert_eq(sanitize_string("hello"), "hello")
  // Normal unicode stays unchanged
  assert_eq(sanitize_string("你好世界"), "你好世界")
}

///|
test "safe_truncate respects boundaries" {
  assert_eq(safe_truncate("hello", 3), "hel")
  assert_eq(safe_truncate("hi", 10), "hi")
  assert_eq(safe_truncate("abc", 0), "")
}

///|
test "strip_bom removes BOM" {
  let with_bom = "\u{FEFF}hello"
  assert_eq(strip_bom(with_bom), "hello")
  assert_eq(strip_bom("no bom"), "no bom")
}

///|
test "estimate_utf8_byte_length ascii" {
  assert_eq(estimate_utf8_byte_length("hello"), 5)
  assert_eq(estimate_utf8_byte_length(""), 0)
  // Chinese chars are 3 bytes each in UTF-8
  assert_eq(estimate_utf8_byte_length("你好"), 6)
}

///|
test "is_binary_content detects binary" {
  assert_false(is_binary_content("hello world"))
  assert_false(is_binary_content("line1\nline2\ttab"))
  // Mostly control characters
  assert_true(is_binary_content("\u{01}\u{02}\u{03}\u{04}\u{05}"))
  assert_false(is_binary_content(""))
}
