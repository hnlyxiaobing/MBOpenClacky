///|
test "agent_config_default_values" {
  let config = AgentConfig::default()
  assert_true(config.permission_mode == ConfirmSafes)
  assert_eq(config.max_tokens, 16384)
  assert_false(config.verbose)
  assert_true(config.enable_compression)
  assert_true(config.enable_prompt_caching)
  assert_true(config.models.is_empty())
  assert_true(config.current_model_id is None)
  assert_false(config.memory_update_enabled)
  assert_eq(config.max_running_agents, 10)
  assert_eq(config.max_idle_agents, 10)
}

///|
test "permission_mode_roundtrip" {
  let modes = [AutoApprove, ConfirmSafes, ConfirmAll]
  for mode in modes {
    let s = mode.to_string_value()
    let parsed = PermissionMode::from_string(s)
    assert_true(parsed is Some(_))
    assert_true(parsed.unwrap() == mode)
  }
}

///|
test "permission_mode_from_string_invalid" {
  assert_true(PermissionMode::from_string("unknown") is None)
  assert_true(PermissionMode::from_string("") is None)
}

///|
test "api_type_roundtrip" {
  let types = [OpenAICompletions, AnthropicMessages, Bedrock, OpenAIResponses]
  let expected = [
    "openai-completions", "anthropic-messages", "bedrock", "openai-responses",
  ]
  let mut i = 0
  while i < types.length() {
    assert_eq(types[i].to_string_value(), expected[i])
    let parsed = ApiType::from_string(expected[i])
    assert_true(parsed is Some(_))
    assert_true(parsed.unwrap() == types[i])
    i = i + 1
  }
}

///|
test "api_type_from_string_invalid" {
  assert_true(ApiType::from_string("unknown") is None)
}

///|
test "providers_all_has_twelve_providers" {
  let all = Providers::all()
  assert_eq(all.length(), 12)
}

///|
test "providers_find_known" {
  let ids = [
    "openclacky", "openrouter", "deepseekv4", "minimax", "kimi", "kimi-coding", "anthropic",
    "mimo", "glm", "openai", "deepseek", "qwen",
  ]
  for id in ids {
    let found = Providers::find(id)
    assert_true(found is Some(_))
    assert_eq(found.unwrap().id, id)
  }
}

///|
test "providers_find_unknown" {
  assert_true(Providers::find("nonexistent") is None)
}

///|
test "providers_resolve_by_base_url" {
  let p = Providers::resolve("https://api.anthropic.com")
  assert_true(p is Some(_))
  assert_eq(p.unwrap().id, "anthropic")

  let p2 = Providers::resolve("https://api.openai.com/v1")
  assert_true(p2 is Some(_))
  assert_eq(p2.unwrap().id, "openai")

  assert_true(Providers::resolve("https://unknown.example.com") is None)

  // New providers
  let p3 = Providers::resolve("https://api.minimaxi.com/v1")
  assert_true(p3 is Some(_))
  assert_eq(p3.unwrap().id, "minimax")

  let p4 = Providers::resolve("https://api.moonshot.cn/v1")
  assert_true(p4 is Some(_))
  assert_eq(p4.unwrap().id, "kimi")

  let p5 = Providers::resolve("https://api.kimi.com/coding")
  assert_true(p5 is Some(_))
  assert_eq(p5.unwrap().id, "kimi-coding")

  let p6 = Providers::resolve("https://open.bigmodel.cn/api/paas/v4")
  assert_true(p6 is Some(_))
  assert_eq(p6.unwrap().id, "glm")
}

///|
test "providers_lite_model_mapping" {
  let lite = Providers::lite_model(
    "https://api.openclacky.com", "abs-claude-opus-4-7",
  )
  assert_true(lite is Some(_))
  assert_eq(lite.unwrap(), "abs-claude-haiku-4-5")

  assert_true(
    Providers::lite_model("https://api.openclacky.com", "unknown-model") is None,
  )
  assert_true(
    Providers::lite_model("https://unknown.example.com", "any") is None,
  )
}

///|
test "providers_fallback_model_mapping" {
  let fb = Providers::fallback_model(
    "https://api.openclacky.com", "abs-claude-sonnet-4-6",
  )
  assert_true(fb is Some(_))
  assert_eq(fb.unwrap(), "abs-claude-sonnet-4-5")

  assert_true(
    Providers::fallback_model(
      "https://api.openclacky.com", "abs-claude-opus-4-7",
    )
    is None,
  )
}

///|
test "providers_api_type_for_known_urls" {
  assert_true(
    Providers::api_type_for("https://api.anthropic.com") == AnthropicMessages,
  )
  assert_true(Providers::api_type_for("https://api.openclacky.com") == Bedrock)
  assert_true(
    Providers::api_type_for("https://api.openai.com/v1") == OpenAICompletions,
  )
  assert_true(
    Providers::api_type_for("https://openrouter.ai/api/v1") == OpenAIResponses,
  )
}

///|
test "providers_api_type_for_unknown_defaults_to_openai" {
  assert_true(
    Providers::api_type_for("https://custom.api.example.com") ==
    OpenAICompletions,
  )
}

// ---- Helper for building TOML strings ----

///|
fn toml(lines : Array[String]) -> @toml.TomlValue raise {
  let s = lines.join("\n")
  @toml.parse(s)
}

///|
fn q(key : String, value : String) -> String {
  "\{key} = \"\{value}\""
}

///|
test "from_toml_empty_string_returns_default" {
  let value = toml([])
  let config = AgentConfig::from_toml(value)
  let default = AgentConfig::default()
  assert_true(config.permission_mode == default.permission_mode)
  assert_eq(config.max_tokens, default.max_tokens)
  assert_eq(config.verbose, default.verbose)
  assert_eq(config.enable_compression, default.enable_compression)
  assert_true(config.models.is_empty())
}

///|
test "from_toml_settings_section" {
  let value = toml([
    "[settings]",
    q("permission_mode", "auto_approve"),
    "max_tokens = 8192",
    "verbose = true",
    "enable_compression = false",
    "enable_prompt_caching = false",
    "memory_update_enabled = true",
    "max_running_agents = 5",
    "max_idle_agents = 3",
    q("current_model_id", "my-model"),
  ])
  let config = AgentConfig::from_toml(value)
  assert_true(config.permission_mode == AutoApprove)
  assert_eq(config.max_tokens, 8192)
  assert_true(config.verbose)
  assert_false(config.enable_compression)
  assert_false(config.enable_prompt_caching)
  assert_true(config.memory_update_enabled)
  assert_eq(config.max_running_agents, 5)
  assert_eq(config.max_idle_agents, 3)
  assert_eq(config.current_model_id, Some("my-model"))
}

///|
test "from_toml_models_array" {
  let value = toml([
    "[[models]]",
    q("id", "m1"),
    q("api_key", "key1"),
    q("base_url", "https://api.anthropic.com"),
    q("model", "claude-sonnet-4-5"),
    "",
    "[[models]]",
    q("id", "m2"),
    q("api_key", "key2"),
    q("base_url", "https://api.openai.com/v1"),
    q("model", "gpt-5.5"),
    q("type", "openai"),
    "anthropic_format = true",
  ])
  let config = AgentConfig::from_toml(value)
  assert_eq(config.models.length(), 2)

  let m1 = config.models[0]
  assert_eq(m1.id, "m1")
  assert_eq(m1.api_key, "key1")
  assert_eq(m1.base_url, "https://api.anthropic.com")
  assert_eq(m1.model, "claude-sonnet-4-5")
  assert_true(m1.type_ is None)
  assert_false(m1.anthropic_format)

  let m2 = config.models[1]
  assert_eq(m2.id, "m2")
  assert_eq(m2.api_key, "key2")
  assert_eq(m2.type_, Some("openai"))
  assert_true(m2.anthropic_format)
}

///|
test "toml_roundtrip" {
  let value = toml([
    "[settings]",
    q("permission_mode", "confirm_all"),
    "max_tokens = 4096",
    "verbose = true",
    "enable_compression = false",
    "enable_prompt_caching = true",
    "memory_update_enabled = true",
    "max_running_agents = 3",
    "max_idle_agents = 2",
    q("current_model_id", "test-id"),
    "",
    "[[models]]",
    q("id", "test-id"),
    q("api_key", "sk-test"),
    q("base_url", "https://api.anthropic.com"),
    q("model", "claude-sonnet-4-5"),
  ])
  let config = AgentConfig::from_toml(value)
  let serialized = config.to_toml()
  let config2 = AgentConfig::from_toml(serialized)

  assert_true(config2.permission_mode == ConfirmAll)
  assert_eq(config2.max_tokens, 4096)
  assert_true(config2.verbose)
  assert_false(config2.enable_compression)
  assert_true(config2.enable_prompt_caching)
  assert_true(config2.memory_update_enabled)
  assert_eq(config2.max_running_agents, 3)
  assert_eq(config2.max_idle_agents, 2)
  assert_eq(config2.current_model_id, Some("test-id"))
  assert_eq(config2.models.length(), 1)
  assert_eq(config2.models[0].id, "test-id")
  assert_eq(config2.models[0].api_key, "sk-test")
}

///|
test "current_model_with_explicit_id" {
  let config = AgentConfig::default()
  config.models.push(
    ModelConfig::new("m1", "key1", "https://api.test.com", "model-a"),
  )
  config.models.push(
    ModelConfig::new("m2", "key2", "https://api.test.com", "model-b"),
  )
  config.current_model_id = Some("m2")
  match config.current_model() {
    Some(m) => assert_eq(m.id, "m2")
    None => fail("expected current_model to return Some")
  }
}

///|
test "current_model_single_model_no_id" {
  let config = AgentConfig::default()
  config.models.push(
    ModelConfig::new("only", "key", "https://api.test.com", "model-x"),
  )
  match config.current_model() {
    Some(m) => assert_eq(m.id, "only")
    None => fail("expected single model to be returned")
  }
}

///|
test "current_model_none_when_empty" {
  let config = AgentConfig::default()
  assert_true(config.current_model() is None)
}

///|
test "has_model_configured" {
  let empty = AgentConfig::default()
  assert_false(empty.has_model_configured())

  let with_key = AgentConfig::default()
  with_key.models.push(
    ModelConfig::new("m1", "sk-abc", "https://api.test.com", "model"),
  )
  assert_true(with_key.has_model_configured())

  let without_key = AgentConfig::default()
  without_key.models.push(
    ModelConfig::new("m1", "", "https://api.test.com", "model"),
  )
  assert_false(without_key.has_model_configured())
}

///|
test "model_config_from_toml_missing_id" {
  let v = toml([
    q("api_key", "key"),
    q("base_url", "https://api.test.com"),
    q("model", "m"),
  ])
  assert_true(ModelConfig::from_toml(v) is None)
}

///|
test "model_config_from_toml_missing_base_url" {
  let v = toml([q("id", "m1"), q("api_key", "key"), q("model", "m")])
  assert_true(ModelConfig::from_toml(v) is None)
}

///|
test "model_config_from_toml_missing_model" {
  let v = toml([
    q("id", "m1"),
    q("api_key", "key"),
    q("base_url", "https://api.test.com"),
  ])
  assert_true(ModelConfig::from_toml(v) is None)
}

///|
test "apply_env_overlay_verbose" {
  @sys.set_env_var("MBOPENCLACKY_VERBOSE", "1")
  let config = AgentConfig::default()
  let result = config.apply_env_overlay()
  assert_true(result.verbose)
  @sys.set_env_var("MBOPENCLACKY_VERBOSE", "")
}

///|
test "apply_env_overlay_creates_model_from_env" {
  @sys.set_env_var("MBOPENCLACKY_API_KEY", "sk-env-key")
  @sys.set_env_var("MBOPENCLACKY_BASE_URL", "https://api.custom.com")
  @sys.set_env_var("MBOPENCLACKY_MODEL", "my-custom-model")
  let config = AgentConfig::default()
  let result = config.apply_env_overlay()
  assert_eq(result.models.length(), 1)
  assert_eq(result.models[0].api_key, "sk-env-key")
  assert_eq(result.models[0].base_url, "https://api.custom.com")
  assert_eq(result.models[0].model, "my-custom-model")
  assert_eq(result.current_model_id, Some("default"))
  @sys.set_env_var("MBOPENCLACKY_API_KEY", "")
  @sys.set_env_var("MBOPENCLACKY_BASE_URL", "")
  @sys.set_env_var("MBOPENCLACKY_MODEL", "")
}

///|
test "apply_env_overlay_skips_when_models_exist" {
  @sys.set_env_var("MBOPENCLACKY_API_KEY", "sk-env-key")
  let config = AgentConfig::default()
  config.models.push(
    ModelConfig::new(
      "existing", "existing-key", "https://api.test.com", "model",
    ),
  )
  let result = config.apply_env_overlay()
  assert_eq(result.models.length(), 1)
  assert_eq(result.models[0].id, "existing")
  @sys.set_env_var("MBOPENCLACKY_API_KEY", "")
}
