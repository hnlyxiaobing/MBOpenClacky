///|
/// White-box tests for the thinking verb animator.
///
/// Coverage:
/// - the default verb list (`all_verbs`, length, format)
/// - sequential rotation, wrap-around, and `reset`
/// - random mode returns verbs that belong to the underlying list
/// - `with_verbs` custom list and the empty-list fallback

///|
test "all_verbs returns a non-empty list of 20+ verbs" {
  let verbs = all_verbs()
  @debug.assert_eq(verbs.length() >= 20, true)
}

///|
test "default verbs are the documented 20 in the expected order" {
  let verbs = all_verbs()
  @debug.assert_eq(verbs.length(), 20)
  @debug.assert_eq(verbs[0], "Cogitating")
  @debug.assert_eq(verbs[1], "Pondering")
  @debug.assert_eq(verbs[10], "Stewing")
  @debug.assert_eq(verbs[19], "Reasoning")
}

///|
test "all_verbs returns a copy so callers cannot mutate the module list" {
  let verbs = all_verbs()
  let original_first = verbs[0]
  verbs[0] = "Mutated"
  let fresh = all_verbs()
  @debug.assert_eq(fresh[0], original_first)
}

///|
test "sequential animator starts at the first verb" {
  let a = ThinkingVerbAnimator::new()
  @debug.assert_eq(a.next(), "Cogitating...")
}

///|
test "sequential next returns different verbs on consecutive calls" {
  let a = ThinkingVerbAnimator::new()
  let v1 = a.next()
  let v2 = a.next()
  // assert_ne is not in the stdlib; compare manually.
  @debug.assert_eq(v1 == v2, false)
}

///|
test "sequential animator walks the list in order" {
  let a = ThinkingVerbAnimator::new()
  let expected = ["Cogitating", "Pondering", "Ruminating", "Deliberating"]
  for v in expected {
    @debug.assert_eq(a.next(), v + "...")
  }
}

///|
test "sequential animator wraps back to the first verb after one full pass" {
  let a = ThinkingVerbAnimator::new()
  let total = all_verbs().length()
  let first = a.next()
  for _ in 0..<total {
    let _ = a.next()
  }
  @debug.assert_eq(a.next(), first)
}

///|
test "reset returns a sequential animator to the first verb" {
  let a = ThinkingVerbAnimator::new()
  let first = a.next()
  for _ in 0..<5 {
    let _ = a.next()
  }
  a.reset()
  @debug.assert_eq(a.next(), first)
}

///|
test "every sequential verb is formatted as Verb..." {
  let a = ThinkingVerbAnimator::new()
  let total = all_verbs().length()
  for _ in 0..<total {
    let v = a.next()
    @debug.assert_eq(v.has_suffix("..."), true)
  }
}

///|
test "ThinkingVerbMode variants compare as expected" {
  @debug.assert_eq(Sequential == Sequential, true)
  @debug.assert_eq(Random == Random, true)
  @debug.assert_eq(Sequential == Random, false)
}

///|
test "new_random creates a random-mode animator" {
  let a = ThinkingVerbAnimator::new_random()
  @debug.assert_eq(a.mode, Random)
}

///|
test "new creates a sequential-mode animator" {
  let a = ThinkingVerbAnimator::new()
  @debug.assert_eq(a.mode, Sequential)
}

///|
test "random mode returns verbs drawn from the list" {
  let a = ThinkingVerbAnimator::new_random()
  let pool = all_verbs()
  for _ in 0..<20 {
    let v = a.next()
    @debug.assert_eq(v.has_suffix("..."), true)
    // Strip the "..." suffix and check the base verb is in the pool.
    let base = v[:v.length() - 3].to_owned()
    @debug.assert_eq(pool.contains(base), true)
  }
}

///|
test "random mode is non-deterministic across many calls" {
  // Statistically the 20 calls below should hit at least 3 distinct
  // verbs. With 20 verbs and uniform sampling the probability of
  // hitting fewer than 3 is vanishingly small, so this is a safe
  // behavioral test rather than a strict requirement.
  let a = ThinkingVerbAnimator::new_random()
  let seen : Array[String] = []
  for _ in 0..<20 {
    let v = a.next()
    if !seen.contains(v) {
      seen.push(v)
    }
  }
  @debug.assert_eq(seen.length() >= 3, true)
}

///|
test "with_verbs accepts a custom list and uses it for rotation" {
  let a = ThinkingVerbAnimator::with_verbs(["Alpha", "Beta", "Gamma"])
  @debug.assert_eq(a.next(), "Alpha...")
  @debug.assert_eq(a.next(), "Beta...")
  @debug.assert_eq(a.next(), "Gamma...")
  @debug.assert_eq(a.next(), "Alpha...")
}

///|
test "with_verbs with a Random mode uses the custom list as the pool" {
  let a = ThinkingVerbAnimator::with_verbs(["Foo", "Bar"], mode=Random)
  let pool = ["Foo...", "Bar..."]
  for _ in 0..<10 {
    @debug.assert_eq(pool.contains(a.next()), true)
  }
}

///|
test "empty verb list returns the Thinking... fallback" {
  let a = ThinkingVerbAnimator::with_verbs([])
  @debug.assert_eq(a.next(), "Thinking...")
  // And it keeps returning the fallback for repeated calls.
  @debug.assert_eq(a.next(), "Thinking...")
}
