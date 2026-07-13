///| White-box tests for string_matcher.mbt (P2-4 coverage expansion).
///
/// All functions here are pure and deterministic, so expected values are
/// verified by hand and independent of any FFI or runtime environment.

///|
test "glob_match: single star matches anything" {
  assert_true(glob_match("*", "anything"))
  assert_true(glob_match("*", ""))
}

///|
test "glob_match: star suffix pattern" {
  assert_true(glob_match("*.txt", "file.txt"))
  assert_false(glob_match("*.txt", "file.md"))
}

///|
test "glob_match: star prefix and zero-width" {
  assert_true(glob_match("a*", "a"))
  assert_true(glob_match("a*", "abcdef"))
}

///|
test "glob_match: star in the middle" {
  assert_true(glob_match("a*b", "aXXb"))
  assert_false(glob_match("a*b", "aXXc"))
}

///|
test "glob_match: question mark matches exactly one" {
  assert_true(glob_match("a?c", "abc"))
  assert_false(glob_match("a?c", "ac"))
  assert_false(glob_match("?", ""))
}

///|
test "glob_match: literal equality" {
  assert_true(glob_match("abc", "abc"))
  assert_false(glob_match("abc", "abd"))
}

///|
test "glob_match: empty pattern only matches empty text" {
  assert_true(glob_match("", ""))
  assert_false(glob_match("", "x"))
}

///|
test "glob_match: consecutive stars collapse" {
  assert_true(glob_match("**", "abc"))
  assert_true(glob_match("a**b", "aXYZb"))
}

///|
test "levenshtein_distance: identical and empty" {
  @debug.assert_eq(levenshtein_distance("", ""), 0)
  @debug.assert_eq(levenshtein_distance("abc", "abc"), 0)
}

///|
test "levenshtein_distance: insertions and deletions" {
  @debug.assert_eq(levenshtein_distance("abc", ""), 3)
  @debug.assert_eq(levenshtein_distance("", "abc"), 3)
}

///|
test "levenshtein_distance: classic examples" {
  @debug.assert_eq(levenshtein_distance("kitten", "sitting"), 3)
  @debug.assert_eq(levenshtein_distance("flaw", "lawn"), 2)
  @debug.assert_eq(levenshtein_distance("abc", "abd"), 1)
}

///|
test "fuzzy_match: within default threshold" {
  assert_true(fuzzy_match("kitten", "sitting"))
  assert_true(fuzzy_match("abc", "abc"))
  assert_true(fuzzy_match("abc", "xyz"))
}

///|
test "fuzzy_match: custom threshold" {
  assert_false(fuzzy_match("kitten", "sitting", max_distance=2))
  assert_false(fuzzy_match("abcd", "wxyz"))
}

///|
test "similarity_score: identical and empty are 1.0" {
  @debug.assert_eq(similarity_score("abc", "abc"), 1.0)
  @debug.assert_eq(similarity_score("", ""), 1.0)
}

///|
test "similarity_score: partial and disjoint" {
  @debug.assert_eq(similarity_score("abcd", "abce"), 0.75)
  @debug.assert_eq(similarity_score("abc", ""), 0.0)
}

///|
test "best_match: picks closest candidate" {
  match best_match("hllo", ["hello", "world", "foo"]) {
    Some(m) => @debug.assert_eq(m, "hello")
    None => fail("expected a match")
  }
}

///|
test "best_match: empty candidates returns None" {
  assert_true(best_match("x", []) is None)
}

///|
test "best_match: ties keep the first candidate" {
  match best_match("x", ["a", "b"]) {
    Some(m) => @debug.assert_eq(m, "a")
    None => fail("expected a match")
  }
}

///|
test "fuzzy_search: sorted by ascending distance" {
  let out = fuzzy_search("abc", ["abc", "abd", "xyz", "abcd"])
  @debug.assert_eq(out.length(), 4)
  @debug.assert_eq(out[0], "abc")
  @debug.assert_eq(out[1], "abd")
  @debug.assert_eq(out[2], "abcd")
  @debug.assert_eq(out[3], "xyz")
}

///|
test "fuzzy_search: threshold filters everything out" {
  let out = fuzzy_search("zzz", ["abc", "def"], max_distance=1)
  @debug.assert_eq(out.length(), 0)
}
