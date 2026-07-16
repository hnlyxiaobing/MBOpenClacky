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

///|
test "get_model_capabilities: anthropic returns full capabilities" {
  let cap = get_model_capabilities("anthropic", "claude-sonnet-4-6")
  assert_true(cap.vision)
  assert_true(cap.reasoning)
  assert_true(cap.function_calling)
}

///|
test "get_model_capabilities: openrouter exact match in model_capabilities" {
  let cap = get_model_capabilities("openrouter", "anthropic/claude-sonnet-4-6")
  assert_true(cap.vision)
  assert_true(cap.reasoning)
  assert_true(cap.json_mode)
}

///|
test "get_model_capabilities: openrouter falls back to default capabilities" {
  let cap = get_model_capabilities("openrouter", "openai/gpt-5.5")
  assert_true(cap.vision)
  assert_false(cap.reasoning)
  assert_true(cap.json_mode)
}

///|
test "get_model_capabilities: unknown provider returns text_only" {
  let cap = get_model_capabilities("nonexistent-provider", "some-model")
  assert_false(cap.vision)
  assert_false(cap.reasoning)
  assert_true(cap.function_calling)
}

///|
test "get_model_capabilities: openrouter prefix match" {
  let cap = get_model_capabilities(
    "openrouter", "anthropic/claude-sonnet-4-6-20250620",
  )
  assert_true(cap.vision)
  assert_true(cap.reasoning)
}

///|
test "get_api_type_for_model: openrouter exact override" {
  let api_type = get_api_type_for_model(
    "openrouter", "anthropic/claude-sonnet-4-6",
  )
  assert_eq(api_type, "anthropic-messages")
}

///|
test "get_api_type_for_model: openrouter falls back to default api_type" {
  let api_type = get_api_type_for_model("openrouter", "openai/gpt-5.5")
  assert_eq(api_type, "openai-responses")
}

///|
test "get_api_type_for_model: anthropic default api_type" {
  let api_type = get_api_type_for_model("anthropic", "claude-sonnet-4-6")
  assert_eq(api_type, "anthropic-messages")
}

///|
test "get_api_type_for_model: unknown provider defaults to openai-completions" {
  let api_type = get_api_type_for_model("nonexistent", "some-model")
  assert_eq(api_type, "openai-completions")
}

///|
test "get_api_type_for_model: openrouter prefix override" {
  let api_type = get_api_type_for_model(
    "openrouter", "anthropic/claude-sonnet-4-6-20250620",
  )
  assert_eq(api_type, "anthropic-messages")
}

///|
test "ModelCapabilities: to_json from_json roundtrip" {
  let cap = ModelCapabilities::full()
  let json = cap.to_json()
  let parsed : ModelCapabilities = @json.from_json(json)
  assert_eq(parsed, cap)
}
