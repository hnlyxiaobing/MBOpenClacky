///| White-box tests for capabilities.mbt (P2-4 coverage expansion).
///
/// Pure model-capability presets. Field-level expectations follow the
/// documented intent of each constructor.

///|
test "model_capabilities: full has vision and reasoning" {
  let c = ModelCapabilities::full()
  assert_true(c.vision)
  assert_true(c.reasoning)
  assert_true(c.json_mode)
  assert_true(c.function_calling)
  assert_true(c.streaming)
  assert_false(c.audio)
}

///|
test "model_capabilities: text_only has no vision or reasoning" {
  let c = ModelCapabilities::text_only()
  assert_false(c.vision)
  assert_false(c.reasoning)
  assert_true(c.json_mode)
  assert_true(c.function_calling)
}

///|
test "model_capabilities: with_vision has vision but no reasoning" {
  let c = ModelCapabilities::with_vision()
  assert_true(c.vision)
  assert_false(c.reasoning)
  assert_true(c.json_mode)
}

///|
test "model_capabilities: reasoning_model lacks json mode" {
  let c = ModelCapabilities::reasoning_model()
  assert_true(c.reasoning)
  assert_true(c.vision)
  assert_false(c.json_mode)
}

///|
test "model_capabilities: equality of identical presets" {
  assert_true(ModelCapabilities::full() == ModelCapabilities::full())
  assert_true(ModelCapabilities::text_only() == ModelCapabilities::text_only())
}

///|
test "model_capabilities: different presets are not equal" {
  assert_true(ModelCapabilities::full() != ModelCapabilities::text_only())
  assert_true(
    ModelCapabilities::with_vision() != ModelCapabilities::reasoning_model(),
  )
}
