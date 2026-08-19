///|
test "agent_config_default_values" {
  let config = AgentConfig::default()
  assert_true(config.permission_mode == ConfirmSafes)
  @debug.assert_eq(config.max_tokens, 16384)
  assert_false(config.verbose)
  assert_true(config.enable_compression)
  assert_true(config.enable_prompt_caching)
  assert_true(config.models.is_empty())
  assert_true(config.current_model_id is None)
  assert_true(config.memory_update_enabled)
  @debug.assert_eq(config.max_running_agents, 10)
  @debug.assert_eq(config.max_idle_agents, 10)
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
    @debug.assert_eq(types[i].to_string_value(), expected[i])
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
test "providers_all_has_thirteen_providers" {
  let all = Providers::all()
  @debug.assert_eq(all.length(), 13)
}

///|
test "providers_find_known" {
  let ids = [
    "openclacky", "openrouter", "deepseekv4", "minimax", "kimi", "kimi-coding", "anthropic",
    "mimo", "glm", "openai", "deepseek", "qwen", "volcengine-ark",
  ]
  for id in ids {
    let found = Providers::find(id)
    assert_true(found is Some(_))
    @debug.assert_eq(found.unwrap().id, id)
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
  @debug.assert_eq(p.unwrap().id, "anthropic")

  let p2 = Providers::resolve("https://api.openai.com/v1")
  assert_true(p2 is Some(_))
  @debug.assert_eq(p2.unwrap().id, "openai")

  assert_true(Providers::resolve("https://unknown.example.com") is None)

  // New providers
  let p3 = Providers::resolve("https://api.minimaxi.com/v1")
  assert_true(p3 is Some(_))
  @debug.assert_eq(p3.unwrap().id, "minimax")

  let p4 = Providers::resolve("https://api.moonshot.cn/v1")
  assert_true(p4 is Some(_))
  @debug.assert_eq(p4.unwrap().id, "kimi")

  let p5 = Providers::resolve("https://api.kimi.com/coding")
  assert_true(p5 is Some(_))
  @debug.assert_eq(p5.unwrap().id, "kimi-coding")

  let p6 = Providers::resolve("https://open.bigmodel.cn/api/paas/v4")
  assert_true(p6 is Some(_))
  @debug.assert_eq(p6.unwrap().id, "glm")
}

///|
test "providers_lite_model_mapping" {
  let lite = Providers::lite_model(
    "https://api.openclacky.com", "abs-claude-opus-4-7",
  )
  assert_true(lite is Some(_))
  @debug.assert_eq(lite.unwrap(), "abs-claude-haiku-4-5")

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
  @debug.assert_eq(fb.unwrap(), "abs-claude-sonnet-4-5")

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
  @debug.assert_eq(config.max_tokens, default.max_tokens)
  @debug.assert_eq(config.verbose, default.verbose)
  @debug.assert_eq(config.enable_compression, default.enable_compression)
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
  @debug.assert_eq(config.max_tokens, 8192)
  assert_true(config.verbose)
  assert_false(config.enable_compression)
  assert_false(config.enable_prompt_caching)
  assert_true(config.memory_update_enabled)
  @debug.assert_eq(config.max_running_agents, 5)
  @debug.assert_eq(config.max_idle_agents, 3)
  @debug.assert_eq(config.current_model_id, Some("my-model"))
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
  @debug.assert_eq(config.models.length(), 2)

  let m1 = config.models[0]
  @debug.assert_eq(m1.id, "m1")
  @debug.assert_eq(m1.api_key, "key1")
  @debug.assert_eq(m1.base_url, "https://api.anthropic.com")
  @debug.assert_eq(m1.model, "claude-sonnet-4-5")
  assert_true(m1.type_ is None)
  assert_false(m1.anthropic_format)

  let m2 = config.models[1]
  @debug.assert_eq(m2.id, "m2")
  @debug.assert_eq(m2.api_key, "key2")
  @debug.assert_eq(m2.type_, Some("openai"))
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
  @debug.assert_eq(config2.max_tokens, 4096)
  assert_true(config2.verbose)
  assert_false(config2.enable_compression)
  assert_true(config2.enable_prompt_caching)
  assert_true(config2.memory_update_enabled)
  @debug.assert_eq(config2.max_running_agents, 3)
  @debug.assert_eq(config2.max_idle_agents, 2)
  @debug.assert_eq(config2.current_model_id, Some("test-id"))
  @debug.assert_eq(config2.models.length(), 1)
  @debug.assert_eq(config2.models[0].id, "test-id")
  @debug.assert_eq(config2.models[0].api_key, "sk-test")
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
    Some(m) => @debug.assert_eq(m.id, "m2")
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
    Some(m) => @debug.assert_eq(m.id, "only")
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
  @env.set_env_var("MBOPENCLACKY_VERBOSE", "1")
  let config = AgentConfig::default()
  let result = config.apply_env_overlay()
  assert_true(result.verbose)
  @env.set_env_var("MBOPENCLACKY_VERBOSE", "")
}

///|
test "apply_env_overlay_creates_model_from_env" {
  @env.set_env_var("MBOPENCLACKY_API_KEY", "sk-env-key")
  @env.set_env_var("MBOPENCLACKY_BASE_URL", "https://api.custom.com")
  @env.set_env_var("MBOPENCLACKY_MODEL", "my-custom-model")
  let config = AgentConfig::default()
  let result = config.apply_env_overlay()
  @debug.assert_eq(result.models.length(), 1)
  @debug.assert_eq(result.models[0].api_key, "sk-env-key")
  @debug.assert_eq(result.models[0].base_url, "https://api.custom.com")
  @debug.assert_eq(result.models[0].model, "my-custom-model")
  @debug.assert_eq(result.current_model_id, Some("default"))
  @env.set_env_var("MBOPENCLACKY_API_KEY", "")
  @env.set_env_var("MBOPENCLACKY_BASE_URL", "")
  @env.set_env_var("MBOPENCLACKY_MODEL", "")
}

///|
test "apply_env_overlay_skips_when_models_exist" {
  @env.set_env_var("MBOPENCLACKY_API_KEY", "sk-env-key")
  let config = AgentConfig::default()
  config.models.push(
    ModelConfig::new(
      "existing", "existing-key", "https://api.test.com", "model",
    ),
  )
  let result = config.apply_env_overlay()
  @debug.assert_eq(result.models.length(), 1)
  @debug.assert_eq(result.models[0].id, "existing")
  @env.set_env_var("MBOPENCLACKY_API_KEY", "")
}

///|
test "current_model falls back to default-badged model when current_model_id is stale" {
  let config = AgentConfig::default()
  let m1 = ModelConfig::new("m1", "k", "https://a", "model-a")
  let m2 = ModelConfig::new("m2", "k", "https://b", "model-b")
  m2.type_ = Some("default")
  config.models.push(m1)
  config.models.push(m2)
  config.current_model_id = Some("deleted-id")
  @debug.assert_eq(config.current_model().map(m => m.id), Some("m2"))
}

///|
test "current_model uses default-badged model when current_model_id is unset" {
  let config = AgentConfig::default()
  let m1 = ModelConfig::new("m1", "k", "https://a", "model-a")
  let m2 = ModelConfig::new("m2", "k", "https://b", "model-b")
  m2.type_ = Some("default")
  config.models.push(m1)
  config.models.push(m2)
  @debug.assert_eq(config.current_model().map(m => m.id), Some("m2"))
}

///|
test "current_model without badge keeps prior semantics" {
  let config = AgentConfig::default()
  let m1 = ModelConfig::new("m1", "k", "https://a", "model-a")
  let m2 = ModelConfig::new("m2", "k", "https://b", "model-b")
  config.models.push(m1)
  config.models.push(m2)
  // No badge, no current_model_id, multiple models -> None (unchanged).
  assert_true(config.current_model() is None)
  // Unmatched id with no badge -> None (unchanged).
  config.current_model_id = Some("deleted-id")
  assert_true(config.current_model() is None)
  // Single model fallback (unchanged).
  let solo = AgentConfig::default()
  solo.models.push(m1)
  @debug.assert_eq(solo.current_model().map(m => m.id), Some("m1"))
}

///|
test "current_model prefers badge over a valid current_model_id (legacy drift)" {
  // Legacy drift: current_model_id set by an older code path, badge set later
  // via Settings - the badge is the most recent explicit user choice.
  let config = AgentConfig::default()
  let m1 = ModelConfig::new("m1", "k", "https://a", "model-a")
  let m2 = ModelConfig::new("m2", "k", "https://b", "model-b")
  m2.type_ = Some("default")
  config.models.push(m1)
  config.models.push(m2)
  config.current_model_id = Some("m1")
  @debug.assert_eq(config.current_model().map(m => m.id), Some("m2"))
}

///|
test "switch_model_by_id moves the default badge" {
  let config = AgentConfig::default()
  let m1 = ModelConfig::new("m1", "k", "https://a", "model-a")
  let m2 = ModelConfig::new("m2", "k", "https://b", "model-b")
  m1.type_ = Some("default")
  config.models.push(m1)
  config.models.push(m2)
  @debug.assert_eq(config.switch_model_by_id("m2"), Ok(()))
  @debug.assert_eq(config.current_model_id, Some("m2"))
  @debug.assert_eq(config.models[1].type_, Some("default"))
  @debug.assert_eq(config.models[0].type_, None)
  @debug.assert_eq(config.current_model().map(m => m.id), Some("m2"))
}

///|
test "session_model_overlay honors session model despite different global badge" {
  let config = AgentConfig::default()
  let m1 = ModelConfig::new("m1", "k", "https://a", "model-a")
  let m2 = ModelConfig::new("m2", "k", "https://b", "model-b")
  m1.type_ = Some("default")
  config.models.push(m1)
  config.models.push(m2)
  let overlay = config.session_model_overlay("m2").unwrap()
  @debug.assert_eq(overlay.current_model().map(m => m.id), Some("m2"))
  // The global config's badge must not be polluted by the overlay.
  @debug.assert_eq(config.models[0].type_, Some("default"))
  @debug.assert_eq(config.models[1].type_, None)
}

// ── BUG-0041: MBOPENCLACKY_COMPRESSION_THRESHOLD via apply_env_overlay ──────

///|
test "apply_env_overlay_reads_compression_threshold" {
  @env.set_env_var("MBOPENCLACKY_COMPRESSION_THRESHOLD", "1")
  let config = AgentConfig::default()
  let result = config.apply_env_overlay()
  @debug.assert_eq(result.compression_threshold, 1)
  @env.unset_env_var("MBOPENCLACKY_COMPRESSION_THRESHOLD")
}

// ── BUG-0052: <prefix>_ANTHROPIC_FORMAT honored in env load ─────────────────

///|
test "env_anthropic_format_false_via_clacky" {
  @env.set_env_var("CLACKY_API_KEY", "sk-test")
  @env.set_env_var("CLACKY_ANTHROPIC_FORMAT", "false")
  let config = load_config_from_env()
  @debug.assert_eq(config.models.length(), 1)
  assert_true(!config.models[0].anthropic_format)
  @env.unset_env_var("CLACKY_API_KEY")
  @env.unset_env_var("CLACKY_ANTHROPIC_FORMAT")
}

///|
test "env_anthropic_format_unset_or_true_defaults" {
  @env.set_env_var("CLACKY_API_KEY", "sk-test")
  // unset -> true
  let unset = load_config_from_env()
  assert_true(unset.models[0].anthropic_format)
  // uppercase "TRUE" -> true (case-insensitive, Ruby downcase == "true")
  @env.set_env_var("CLACKY_ANTHROPIC_FORMAT", "TRUE")
  let upper = load_config_from_env()
  assert_true(upper.models[0].anthropic_format)
  @env.unset_env_var("CLACKY_API_KEY")
  @env.unset_env_var("CLACKY_ANTHROPIC_FORMAT")
}

// ── BUG-0015: merge_config appends env models by type ───────────────────────

///|
test "merge_config_appends_env_model_by_type" {
  let base = AgentConfig::default()
  base.models.push(
    ModelConfig::new("file", "sk-file", "https://file.com", "gpt-4"),
  )
  let overlay = AgentConfig::default()
  overlay.models.push({
    id: "default",
    type_: Some("default"),
    api_key: "sk-env",
    base_url: "https://env.com",
    model: "gpt-4-turbo",
    anthropic_format: true,
    runtime_id: "default",
    media_type: None,
  })
  overlay.current_model_id = Some("default")
  let merged = merge_config(base, overlay)
  // File model preserved + env model appended (no duplicate type).
  @debug.assert_eq(merged.models.length(), 2)
  @debug.assert_eq(merged.models[0].api_key, "sk-file")
  @debug.assert_eq(merged.models[1].type_, Some("default"))
  // Env model is the default badge -> current_model resolves to it,
  // matching Ruby ruby_results.json config-003 (current=sk-env).
  match merged.current_model() {
    Some(m) => @debug.assert_eq(m.api_key, "sk-env")
    None => fail("expected env model as current")
  }
}

///|
test "merge_config_skips_duplicate_type" {
  let base = AgentConfig::default()
  base.models.push({
    id: "file",
    type_: Some("default"),
    api_key: "sk-file",
    base_url: "https://file.com",
    model: "gpt-4",
    anthropic_format: false,
    runtime_id: "file",
    media_type: None,
  })
  let overlay = AgentConfig::default()
  overlay.models.push({
    id: "default",
    type_: Some("default"),
    api_key: "sk-env",
    base_url: "https://env.com",
    model: "gpt-4-turbo",
    anthropic_format: true,
    runtime_id: "default",
    media_type: None,
  })
  let merged = merge_config(base, overlay)
  // type=default already present in base -> env model not appended.
  @debug.assert_eq(merged.models.length(), 1)
  @debug.assert_eq(merged.models[0].api_key, "sk-file")
}

///|
test "merge_config_badges_first_model_when_no_default" {
  let base = AgentConfig::default()
  base.models.push(ModelConfig::new("m1", "k1", "https://a.com", "model-a"))
  base.models.push(ModelConfig::new("m2", "k2", "https://b.com", "model-b"))
  // Empty overlay (no env models): merge must still badge first model
  // as default, matching Ruby agent_config.rb:305-307.
  let merged = merge_config(base, AgentConfig::default())
  @debug.assert_eq(merged.models.length(), 2)
  @debug.assert_eq(merged.models[0].type_, Some("default"))
  @debug.assert_eq(merged.models[1].type_, None)
}

///|
/// BUG-0014：from_toml 自动锚定 current_model_id——无 default badge 时回退
/// 第一个模型；有 default badge 时锚定 badge 模型；显式 current_model_id 优先。
test "from_toml_auto_anchors_current_model_id" {
  let no_badge_toml =
    #|[[models]]
    #|id = "m1"
    #|api_key = "sk-1"
    #|base_url = "https://api.1.com"
    #|model = "gpt-4"
    #|
    #|[[models]]
    #|id = "m2"
    #|api_key = "sk-2"
    #|base_url = "https://api.2.com"
    #|model = "gpt-4-turbo"
  let c1 = AgentConfig::from_toml(@toml.parse(no_badge_toml))
  @debug.assert_eq(c1.current_model_id, Some("m1"))

  let with_badge_toml =
    #|[[models]]
    #|id = "m1"
    #|api_key = "sk-1"
    #|base_url = "https://api.1.com"
    #|model = "gpt-4"
    #|
    #|[[models]]
    #|id = "m2"
    #|api_key = "sk-2"
    #|base_url = "https://api.2.com"
    #|model = "gpt-4-turbo"
    #|type = "default"
  let c2 = AgentConfig::from_toml(@toml.parse(with_badge_toml))
  @debug.assert_eq(c2.current_model_id, Some("m2"))

  // 显式 current_model_id 不被自动锚定覆盖
  let explicit_toml =
    #|[settings]
    #|current_model_id = "m1"
    #|
    #|[[models]]
    #|id = "m1"
    #|api_key = "sk-1"
    #|base_url = "https://api.1.com"
    #|model = "gpt-4"
    #|
    #|[[models]]
    #|id = "m2"
    #|api_key = "sk-2"
    #|base_url = "https://api.2.com"
    #|model = "gpt-4-turbo"
    #|type = "default"
  let c3 = AgentConfig::from_toml(@toml.parse(explicit_toml))
  @debug.assert_eq(c3.current_model_id, Some("m1"))
}
