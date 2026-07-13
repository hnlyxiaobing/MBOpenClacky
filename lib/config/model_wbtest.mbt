///| White-box tests for model.mbt (P2-4 coverage expansion).
///
/// Pure ModelConfig construction and copying.

///|
test "model_config: new sets identity fields" {
  let m = ModelConfig::new("m1", "key", "http://x", "model-a")
  assert_eq(m.id, "m1")
  assert_eq(m.api_key, "key")
  assert_eq(m.base_url, "http://x")
  assert_eq(m.model, "model-a")
}

///|
test "model_config: new defaults are sensible" {
  let m = ModelConfig::new("m1", "key", "http://x", "model-a")
  assert_false(m.anthropic_format)
  assert_eq(m.runtime_id, "m1")
  assert_true(m.media_type is None)
}

///|
test "model_config: deep_copy is equal to original" {
  let m = ModelConfig::new("m1", "key", "http://x", "model-a")
  assert_true(m.deep_copy() == m)
}

///|
test "model_config: equality is reflexive" {
  let m = ModelConfig::new("m1", "key", "http://x", "model-a")
  assert_true(m == m)
}
