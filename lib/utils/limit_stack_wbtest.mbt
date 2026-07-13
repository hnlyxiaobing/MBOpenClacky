///| White-box tests for limit_stack.mbt (P2-4 coverage expansion).
///
/// Pure recursion-depth limiter. All behavior is deterministic and local.

///|
test "limit_stack: default max depth is 50" {
  let s = LimitStack::new()
  assert_eq(s.depth(), 0)
  assert_eq(s.remaining(), 50)
  assert_false(s.is_exceeded())
}

///|
test "limit_stack: custom max depth" {
  let s = LimitStack::new(max_depth=3)
  assert_eq(s.remaining(), 3)
}

///|
test "limit_stack: push succeeds below limit" {
  let s = LimitStack::new(max_depth=2)
  assert_true(s.push())
  assert_eq(s.depth(), 1)
  assert_true(s.push())
  assert_eq(s.depth(), 2)
}

///|
test "limit_stack: push fails at limit" {
  let s = LimitStack::new(max_depth=2)
  assert_true(s.push())
  assert_true(s.push())
  assert_false(s.push())
  assert_true(s.is_exceeded())
}

///|
test "limit_stack: push records label" {
  let s = LimitStack::new(max_depth=2)
  ignore(s.push(label="outer"))
  ignore(s.push(label="inner"))
  assert_eq(s.stack_trace().length(), 2)
  assert_eq(s.stack_trace()[0], "outer")
}

///|
test "limit_stack: pop decreases depth" {
  let s = LimitStack::new(max_depth=5)
  ignore(s.push())
  ignore(s.push())
  assert_eq(s.depth(), 2)
  s.pop()
  assert_eq(s.depth(), 1)
}

///|
test "limit_stack: pop never goes negative" {
  let s = LimitStack::new(max_depth=5)
  s.pop()
  assert_eq(s.depth(), 0)
}

///|
test "limit_stack: reset clears state" {
  let s = LimitStack::new(max_depth=5)
  ignore(s.push())
  ignore(s.push())
  s.reset()
  assert_eq(s.depth(), 0)
  assert_eq(s.remaining(), 5)
  assert_eq(s.stack_trace().length(), 0)
}

///|
test "limit_stack: remaining shrinks with depth" {
  let s = LimitStack::new(max_depth=4)
  ignore(s.push())
  ignore(s.push())
  assert_eq(s.remaining(), 2)
}

///|
test "limit_stack: exceeded after filling exactly" {
  let s = LimitStack::new(max_depth=1)
  assert_true(s.push())
  assert_true(s.is_exceeded())
  assert_false(s.push())
}
