///| White-box tests for provider.mbt (P2-4 coverage expansion).
///
/// Provider presets are static, deterministic data + pure resolvers, so all
/// expectations are hand-computed from the preset table in the source.

///|
test "api_type: to_string_value mappings" {
  @debug.assert_eq(
    ApiType::to_string_value(OpenAICompletions),
    "openai-completions",
  )
  @debug.assert_eq(
    ApiType::to_string_value(AnthropicMessages),
    "anthropic-messages",
  )
  @debug.assert_eq(ApiType::to_string_value(Bedrock), "bedrock")
  @debug.assert_eq(
    ApiType::to_string_value(OpenAIResponses),
    "openai-responses",
  )
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
  @debug.assert_eq(Providers::all().length(), 13)
}

///|
test "providers: find resolves by id" {
  match Providers::find("openai") {
    Some(p) => {
      @debug.assert_eq(p.id, "openai")
      @debug.assert_eq(p.default_model, "gpt-5.5")
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
    Some(p) => @debug.assert_eq(p.id, "anthropic")
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
test "providers: api_type_for_model routes openclacky non-claude to openai" {
  let base = "https://api.openclacky.com"
  assert_true(
    Providers::api_type_for_model(base, "dsk-deepseek-v4-flash") ==
    OpenAICompletions,
  )
  assert_true(
    Providers::api_type_for_model(base, "dsk-deepseek-v4-pro") ==
    OpenAICompletions,
  )
  assert_true(
    Providers::api_type_for_model(base, "or-gemini-3-1-pro") ==
    OpenAICompletions,
  )
  assert_true(
    Providers::api_type_for_model(base, "or-gemini-3-5-flash") ==
    OpenAICompletions,
  )
}

///|
test "providers: api_type_for_model keeps openclacky claude on bedrock" {
  let base = "https://api.openclacky.com"
  assert_true(
    Providers::api_type_for_model(base, "abs-claude-sonnet-4-6") == Bedrock,
  )
  assert_true(
    Providers::api_type_for_model(base, "abs-claude-haiku-4-5") == Bedrock,
  )
}

///|
test "providers: api_type_for_model unknown url defaults to openai" {
  assert_true(
    Providers::api_type_for_model("https://unknown.example.com", "some-model") ==
    OpenAICompletions,
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
    Some(p) => @debug.assert_eq(p.default_model, "anthropic/claude-sonnet-4-6")
    None => fail("expected openrouter preset")
  }
}

///|
test "providers: anthropic base url" {
  match Providers::find("anthropic") {
    Some(p) => @debug.assert_eq(p.base_url, "https://api.anthropic.com")
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
    Some(p) => @debug.assert_eq(p.id, "openai")
    None => fail("expected to resolve openai")
  }
}

///|
test "providers: qwen default model" {
  match Providers::find("qwen") {
    Some(p) => @debug.assert_eq(p.default_model, "qwen3.7-max")
    None => fail("expected qwen preset")
  }
}

///|
test "providers: resolve matches endpoint variants" {
  match Providers::resolve("https://api.z.ai/api/paas/v4") {
    Some(p) => @debug.assert_eq(p.id, "glm")
    None => fail("expected api.z.ai to resolve to glm")
  }
  match Providers::resolve("https://api.minimax.io/v1") {
    Some(p) => @debug.assert_eq(p.id, "minimax")
    None => fail("expected api.minimax.io to resolve to minimax")
  }
  match Providers::resolve("https://api.moonshot.ai/v1") {
    Some(p) => @debug.assert_eq(p.id, "kimi")
    None => fail("expected api.moonshot.ai to resolve to kimi")
  }
  match Providers::resolve("https://open.bigmodel.cn/api/coding/paas/v4") {
    Some(p) => @debug.assert_eq(p.id, "glm")
    None => fail("expected bigmodel coding path to resolve to glm")
  }
}

///|
test "providers: resolve ignores trailing slash and accepts sub-paths" {
  match Providers::resolve("https://api.anthropic.com/") {
    Some(p) => @debug.assert_eq(p.id, "anthropic")
    None => fail("expected trailing-slash url to resolve")
  }
  match Providers::resolve("https://api.deepseek.com/v1") {
    Some(p) => @debug.assert_eq(p.id, "deepseekv4")
    None => fail("expected sub-path url to resolve")
  }
}

///|
test "providers: resolve rejects near-miss prefixes" {
  // "api.anthropic.com.evil.com" must NOT match the anthropic preset.
  assert_true(Providers::resolve("https://api.anthropic.com.evil.com") is None)
  assert_true(Providers::resolve("") is None)
}

///|
test "providers: glm declares four endpoint variants" {
  match Providers::find("glm") {
    Some(p) => {
      @debug.assert_eq(p.endpoint_variants.length(), 4)
      let urls = p.endpoint_variants.map(fn(v) { v.base_url })
      assert_true(urls.contains("https://api.z.ai/api/coding/paas/v4"))
      assert_true(urls.contains("https://open.bigmodel.cn/api/paas/v4"))
      for v in p.endpoint_variants {
        assert_true(v.label_key is Some(_))
      }
    }
    None => fail("expected glm preset")
  }
}

///|
test "providers: minimax and kimi declare regional variants" {
  match Providers::find("minimax") {
    Some(p) => {
      @debug.assert_eq(p.endpoint_variants.length(), 2)
      let urls = p.endpoint_variants.map(fn(v) { v.base_url })
      assert_true(urls.contains("https://api.minimax.io/v1"))
    }
    None => fail("expected minimax preset")
  }
  match Providers::find("kimi") {
    Some(p) => {
      @debug.assert_eq(p.endpoint_variants.length(), 2)
      let urls = p.endpoint_variants.map(fn(v) { v.base_url })
      assert_true(urls.contains("https://api.moonshot.ai/v1"))
    }
    None => fail("expected kimi preset")
  }
}

///|
test "providers: volcengine-ark preset exists" {
  match Providers::find("volcengine-ark") {
    Some(p) => {
      @debug.assert_eq(p.id, "volcengine-ark")
      @debug.assert_eq(p.name, "Volcengine Ark")
      @debug.assert_eq(p.base_url, "https://ark.cn-beijing.volces.com/api/v3")
      assert_true(p.api_type == OpenAICompletions)
      @debug.assert_eq(p.default_model, "doubao-1.5-pro-256k")
      assert_true(p.models.contains("doubao-1.5-pro-256k"))
      assert_true(p.models.contains("deepseek-r1-250120"))
    }
    None => fail("expected volcengine-ark preset")
  }
}

///|
test "providers: volcengine-ark has three regional variants" {
  match Providers::find("volcengine-ark") {
    Some(p) => {
      @debug.assert_eq(p.endpoint_variants.length(), 3)
      let urls = p.endpoint_variants.map(fn(v) { v.base_url })
      assert_true(urls.contains("https://ark.cn-beijing.volces.com/api/v3"))
      assert_true(urls.contains("https://ark.cn-shanghai.volces.com/api/v3"))
      assert_true(urls.contains("https://ark.cn-guangzhou.volces.com/api/v3"))
    }
    None => fail("expected volcengine-ark preset")
  }
}

///|
test "providers: volcengine-ark endpoint resolves" {
  match Providers::resolve("https://ark.cn-shanghai.volces.com/api/v3") {
    Some(p) => @debug.assert_eq(p.id, "volcengine-ark")
    None => fail("expected Shanghai endpoint to resolve to volcengine-ark")
  }
}

///|
test "providers: kimi models include latest" {
  match Providers::find("kimi") {
    Some(p) => {
      assert_true(p.models.contains("kimi-k3"))
      assert_true(p.models.contains("kimi-k2.7-code"))
      assert_true(p.models.contains("kimi-k2.7-code-highspeed"))
      assert_true(p.models.contains("kimi-k2.6"))
      assert_true(p.models.contains("kimi-k2.5"))
    }
    None => fail("expected kimi preset")
  }
}

///|
test "providers: kimi lite model for kimi-k3" {
  let lite = Providers::lite_model("https://api.moonshot.cn/v1", "kimi-k3")
  assert_true(lite == Some("kimi-k2.5"))
}

///|
test "providers: qwen has three regional endpoint variants" {
  match Providers::find("qwen") {
    Some(p) => {
      @debug.assert_eq(p.endpoint_variants.length(), 3)
      let regions = p.endpoint_variants.map(fn(v) {
        match v.region {
          Some(r) => r
          None => ""
        }
      })
      assert_true(regions.contains("cn"))
      assert_true(regions.contains("intl"))
      assert_true(regions.contains("us"))
    }
    None => fail("expected qwen preset")
  }
}

///|
test "providers: qwen international endpoint resolves" {
  match
    Providers::resolve("https://dashscope-intl.aliyuncs.com/compatible-mode/v1") {
    Some(p) => @debug.assert_eq(p.id, "qwen")
    None => fail("expected intl endpoint to resolve to qwen")
  }
}

///|
test "providers: openclacky has image and audio models" {
  match Providers::find("openclacky") {
    Some(p) => {
      assert_true(p.image_models.contains("gpt-4o"))
      assert_true(p.audio_models.contains("tts-1"))
      assert_true(p.video_models.length() == 0)
    }
    None => fail("expected openclacky preset")
  }
}
