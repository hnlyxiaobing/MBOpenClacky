///| White-box tests for provider.mbt (P2-4 coverage expansion).
///
/// Provider presets are static, deterministic data + pure resolvers, so all
/// expectations are hand-computed from the preset table in the source.

///|
test "api_type: to_string_value mappings" {
  assert_eq(ApiType::to_string_value(OpenAICompletions), "openai-completions")
  assert_eq(ApiType::to_string_value(AnthropicMessages), "anthropic-messages")
  assert_eq(ApiType::to_string_value(Bedrock), "bedrock")
  assert_eq(ApiType::to_string_value(OpenAIResponses), "openai-responses")
}

///|
test "api_type: from_string round-trips" {
  assert_true(
    ApiType::from_string("openai-completions") == Some(OpenAICompletions),
  )
  assert_true(
    ApiType::from_string("anthropic-messages") == Some(AnthropicMessages),
  )
  assert_true(ApiType::from_string("bedrock") == Some(Bedrock))
  assert_true(ApiType::from_string("openai-responses") == Some(OpenAIResponses))
}

///|
test "api_type: from_string rejects unknown" {
  assert_true(ApiType::from_string("nope") is None)
  assert_true(ApiType::from_string("") is None)
}

///|
test "providers: all returns the full preset list" {
  assert_eq(Providers::all().length(), 12)
}

///|
test "providers: find resolves by id" {
  match Providers::find("openai") {
    Some(p) => {
      assert_eq(p.id, "openai")
      assert_eq(p.default_model, "gpt-5.5")
    }
    None => fail("expected to find openai")
  }
}

///|
test "providers: find returns none for unknown id" {
  assert_true(Providers::find("does-not-exist") is None)
}

///|
test "providers: resolve matches by base_url" {
  match Providers::resolve("https://api.anthropic.com") {
    Some(p) => assert_eq(p.id, "anthropic")
    None => fail("expected to resolve anthropic")
  }
}

///|
test "providers: resolve returns none for unknown url" {
  assert_true(Providers::resolve("https://unknown.example.com") is None)
}

///|
test "providers: lite_model returns pairing" {
  let lite = Providers::lite_model(
    "https://api.openclacky.com", "abs-claude-sonnet-4-6",
  )
  assert_true(lite == Some("abs-claude-haiku-4-5"))
}

///|
test "providers: lite_model none when unpaired" {
  let lite = Providers::lite_model(
    "https://api.openclacky.com", "no-such-model",
  )
  assert_true(lite is None)
}

///|
test "providers: fallback_model returns chain" {
  let fb = Providers::fallback_model(
    "https://api.openclacky.com", "abs-claude-sonnet-4-6",
  )
  assert_true(fb == Some("abs-claude-sonnet-4-5"))
}

///|
test "providers: api_type_for known url" {
  assert_true(
    Providers::api_type_for("https://api.anthropic.com") == AnthropicMessages,
  )
  assert_true(
    Providers::api_type_for("https://openrouter.ai/api/v1") == OpenAIResponses,
  )
}

///|
test "providers: api_type_for unknown url defaults to openai" {
  assert_true(
    Providers::api_type_for("https://unknown.example.com") == OpenAICompletions,
  )
}

///|
test "providers: openai preset exposes gpt models" {
  match Providers::find("openai") {
    Some(p) => assert_true(p.models.contains("gpt-5.5"))
    None => fail("expected openai preset")
  }
}

///|
test "providers: openrouter default model" {
  match Providers::find("openrouter") {
    Some(p) => assert_eq(p.default_model, "anthropic/claude-sonnet-4-6")
    None => fail("expected openrouter preset")
  }
}

///|
test "providers: anthropic base url" {
  match Providers::find("anthropic") {
    Some(p) => assert_eq(p.base_url, "https://api.anthropic.com")
    None => fail("expected anthropic preset")
  }
}

///|
test "providers: deepseek uses openai completions" {
  match Providers::find("deepseek") {
    Some(p) => assert_true(p.api_type == OpenAICompletions)
    None => fail("expected deepseek preset")
  }
}

///|
test "providers: glm exposes glm-5.1" {
  match Providers::find("glm") {
    Some(p) => assert_true(p.models.contains("glm-5.1"))
    None => fail("expected glm preset")
  }
}

///|
test "providers: openai lite model pairing" {
  let lite = Providers::lite_model("https://api.openai.com/v1", "gpt-5.5")
  assert_true(lite == Some("gpt-5.4-mini"))
}

///|
test "providers: openclacky fallback chain" {
  let fb = Providers::fallback_model(
    "https://api.openclacky.com", "abs-claude-fable-5",
  )
  assert_true(fb == Some("abs-claude-opus-4-8"))
}

///|
test "providers: openclacky api type is bedrock" {
  assert_true(Providers::api_type_for("https://api.openclacky.com") == Bedrock)
}

///|
test "providers: every preset has a non-empty id" {
  for p in Providers::all() {
    assert_false(p.id.is_empty())
  }
}

///|
test "providers: resolve openai base url" {
  match Providers::resolve("https://api.openai.com/v1") {
    Some(p) => assert_eq(p.id, "openai")
    None => fail("expected to resolve openai")
  }
}

///|
test "providers: qwen default model" {
  match Providers::find("qwen") {
    Some(p) => assert_eq(p.default_model, "qwen3.7-max")
    None => fail("expected qwen preset")
  }
}
