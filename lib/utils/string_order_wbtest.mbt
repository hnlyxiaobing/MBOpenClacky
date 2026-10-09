///| White-box tests for `compare_lexicographic`.
///
/// Regression guard for BUG-0075: core `String::compare` is shortlex (length
/// first), which silently broke every `sort_by { name }` ported from orig.

///|
/// `compare_lexicographic` must agree with Ruby's `String#<=>` even when the
/// operands have different lengths.
test "compare_lexicographic differs from core shortlex" {
  // Core String::compare says -1 here (shorter first); Ruby says +1 ('n' > 'd').
  assert_true("new".compare("deploy") < 0)
  assert_true(compare_lexicographic("new", "deploy") > 0)
  // Core says +1 (longer first); Ruby says -1 ('a' < 'b').
  assert_true("aa".compare("b") > 0)
  assert_true(compare_lexicographic("aa", "b") < 0)
}

///|
test "compare_lexicographic basic ordering" {
  assert_eq(compare_lexicographic("abc", "abc"), 0)
  assert_true(compare_lexicographic("a", "aa") < 0)
  assert_true(compare_lexicographic("aa", "a") > 0)
  assert_true(compare_lexicographic("ab", "aa") > 0)
  assert_true(compare_lexicographic("a", "b") < 0)
  // Hyphen (0x2D) sorts before letters, like Ruby.
  assert_true(compare_lexicographic("media-gen", "median") < 0)
}

///|
test "compare_lexicographic sorts differently-lengthed names" {
  let names : Array[String] = ["new", "deploy", "media-gen"]
  names.sort_by(fn(a, b) { compare_lexicographic(a, b) })
  assert_eq(names, ["deploy", "media-gen", "new"])
}
