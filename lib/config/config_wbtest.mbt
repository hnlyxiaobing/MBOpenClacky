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
  // p6 decision 2/6: runtime-only fields are stripped from serialization -
  // settings never carries current_model_id, models never carry id
  // (Ruby to_yaml strips RUNTIME_ONLY_FIELDS).
  match serialized {
    TomlTable(root) => {
      match root.get("settings") {
        Some(TomlTable(settings)) =>
          assert_true(settings.get("current_model_id") is None)
        _ => fail("expected settings table")
      }
      match root.get("models") {
        Some(TomlArray(models)) => {
          assert_true(models.length() == 1)
          match models[0] {
            TomlTable(m) => assert_true(m.get("id") is None)
            _ => fail("expected model table")
          }
        }
        _ => fail("expected models array")
      }
    }
    _ => fail("expected root table")
  }
  let config2 = AgentConfig::from_toml(serialized)

  assert_true(config2.permission_mode == ConfirmAll)
  @debug.assert_eq(config2.max_tokens, 4096)
  assert_true(config2.verbose)
  assert_false(config2.enable_compression)
  assert_true(config2.enable_prompt_caching)
  assert_true(config2.memory_update_enabled)
  @debug.assert_eq(config2.max_running_agents, 3)
  @debug.assert_eq(config2.max_idle_agents, 2)
  @debug.assert_eq(config2.models.length(), 1)
  // id was stripped and re-injected at load time (positional id)
  @debug.assert_eq(config2.models[0].id, "model-1")
  @debug.assert_eq(config2.models[0].runtime_id, "model-1")
  @debug.assert_eq(config2.models[0].api_key, "sk-test")
  // current_model_id re-anchored to the first model by from_toml (BUG-0014)
  @debug.assert_eq(config2.current_model_id, Some("model-1"))
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
test "model_config_from_toml_missing_id_keeps_entry" {
  // p6 decision 6: a missing id no longer drops the entry (Ruby parse_models
  // keeps incomplete entries); AgentConfig::from_toml injects a runtime id.
  let v = toml([
    q("api_key", "key"),
    q("base_url", "https://api.test.com"),
    q("model", "m"),
  ])
  match ModelConfig::from_toml(v) {
    Some(m) => {
      @debug.assert_eq(m.id, "")
      @debug.assert_eq(m.api_key, "key")
    }
    None => fail("expected Some for missing id")
  }
  // Full config load injects the runtime id
  let value = toml([
    "[[models]]",
    q("api_key", "key"),
    q("base_url", "https://api.test.com"),
    q("model", "m"),
  ])
  let config = AgentConfig::from_toml(value)
  @debug.assert_eq(config.models.length(), 1)
  @debug.assert_eq(config.models[0].id, "model-1")
  @debug.assert_eq(config.models[0].runtime_id, "model-1")
}

///|
test "model_config_from_toml_missing_base_url_keeps_entry" {
  let v = toml([q("id", "m1"), q("api_key", "key"), q("model", "m")])
  match ModelConfig::from_toml(v) {
    Some(m) => {
      @debug.assert_eq(m.id, "m1")
      @debug.assert_eq(m.base_url, "")
    }
    None => fail("expected Some for missing base_url")
  }
}

///|
test "model_config_from_toml_missing_model_keeps_entry" {
  let v = toml([
    q("id", "m1"),
    q("api_key", "key"),
    q("base_url", "https://api.test.com"),
  ])
  match ModelConfig::from_toml(v) {
    Some(m) => {
      @debug.assert_eq(m.id, "m1")
      @debug.assert_eq(m.model, "")
    }
    None => fail("expected Some for missing model")
  }
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
test "current_model without badge falls back to first model" {
  // p6 decision 2: with no current_model_id and no badge, a non-empty model
  // list always resolves - Ruby falls back to current_model_index (default 0).
  let config = AgentConfig::default()
  let m1 = ModelConfig::new("m1", "k", "https://a", "model-a")
  let m2 = ModelConfig::new("m2", "k", "https://b", "model-b")
  config.models.push(m1)
  config.models.push(m2)
  // No badge, no current_model_id, multiple models -> first model.
  @debug.assert_eq(config.current_model().map(m => m.id), Some("m1"))
  // Stale id (model deleted) is cleared and resolution falls back to first.
  config.current_model_id = Some("deleted-id")
  @debug.assert_eq(config.current_model().map(m => m.id), Some("m1"))
  @debug.assert_eq(config.current_model_id, None)
  // Empty model list -> None.
  let empty = AgentConfig::default()
  assert_true(empty.current_model() is None)
}

///|
test "current_model prefers current_model_id over badge (id-first)" {
  // p6 decision 2: current_model_id is the primary truth (Ruby
  // resolve_current_model_entry checks id first); the badge is the fallback.
  let config = AgentConfig::default()
  let m1 = ModelConfig::new("m1", "k", "https://a", "model-a")
  let m2 = ModelConfig::new("m2", "k", "https://b", "model-b")
  m2.type_ = Some("default")
  config.models.push(m1)
  config.models.push(m2)
  config.current_model_id = Some("m1")
  @debug.assert_eq(config.current_model().map(m => m.id), Some("m1"))
  // Without an id, the badge wins.
  config.current_model_id = None
  @debug.assert_eq(config.current_model().map(m => m.id), Some("m2"))
}

///|
test "switch_model_by_id does not move the default badge" {
  // p6 decision 2: switch is session-level (Ruby switch_model_by_id only
  // sets current_model_id); set_default_model_by_id moves the badge.
  let config = AgentConfig::default()
  let m1 = ModelConfig::new("m1", "k", "https://a", "model-a")
  let m2 = ModelConfig::new("m2", "k", "https://b", "model-b")
  m1.type_ = Some("default")
  config.models.push(m1)
  config.models.push(m2)
  @debug.assert_eq(config.switch_model_by_id("m2"), Ok(()))
  @debug.assert_eq(config.current_model_id, Some("m2"))
  // Badge stays on m1
  @debug.assert_eq(config.models[0].type_, Some("default"))
  @debug.assert_eq(config.models[1].type_, None)
  // But current resolution follows the id
  @debug.assert_eq(config.current_model().map(m => m.id), Some("m2"))
  // set_default_model_by_id moves the badge (and normalizes the id)
  @debug.assert_eq(config.set_default_model_by_id("m2"), Ok(()))
  @debug.assert_eq(config.models[1].type_, Some("default"))
  @debug.assert_eq(config.models[0].type_, None)
  @debug.assert_eq(config.current_model().map(m => m.id), Some("m2"))
  // Error paths
  @debug.assert_eq(
    config.set_default_model_by_id("nope"),
    Err("model not found"),
  )
  @debug.assert_eq(
    config.set_default_model_by_id(""),
    Err("model id must not be empty"),
  )
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

// ── p6: model management APIs (Ruby agent_config.rb) ────────────────────────

///|
test "remove_model refuses last model and clears current_model_id" {
  let config = AgentConfig::default()
  let m1 = ModelConfig::new("m1", "k", "https://a", "model-a")
  config.models.push(m1)
  // Last remaining model cannot be removed
  assert_false(config.remove_model(0))
  @debug.assert_eq(config.models.length(), 1)
  // Bad index
  assert_false(config.remove_model(5))
  assert_false(config.remove_model(-1))

  let m2 = ModelConfig::new("m2", "k", "https://b", "model-b")
  config.models.push(m2)
  config.current_model_id = Some("m2")
  // Removing the current model clears current_model_id
  assert_true(config.remove_model(1))
  @debug.assert_eq(config.current_model_id, None)
  @debug.assert_eq(config.models.length(), 1)
  @debug.assert_eq(config.current_model().map(m => m.id), Some("m1"))

  // Removing a non-current model keeps current_model_id
  let m3 = ModelConfig::new("m3", "k", "https://c", "model-c")
  config.models.push(m3)
  config.current_model_id = Some("m1")
  assert_true(config.remove_model(1))
  @debug.assert_eq(config.current_model_id, Some("m1"))
}

///|
test "set_model_type validates and moves tags" {
  let config = AgentConfig::default()
  let m1 = ModelConfig::new("m1", "k", "https://a", "model-a")
  let m2 = ModelConfig::new("m2", "k", "https://b", "model-b")
  m1.type_ = Some("default")
  config.models.push(m1)
  config.models.push(m2)
  // Valid types
  assert_true(config.set_model_type(1, Some("lite")))
  @debug.assert_eq(config.models[1].type_, Some("lite"))
  // Moving "default" to m2 clears it from m1
  assert_true(config.set_model_type(1, Some("default")))
  @debug.assert_eq(config.models[0].type_, None)
  @debug.assert_eq(config.models[1].type_, Some("default"))
  // None clears the tag
  assert_true(config.set_model_type(1, None))
  @debug.assert_eq(config.models[1].type_, None)
  // Invalid type refused
  assert_false(config.set_model_type(0, Some("bogus")))
  // Bad index refused
  assert_false(config.set_model_type(9, Some("lite")))
}

///|
test "add_model appends and injects ids" {
  let config = AgentConfig::default()
  config.models.push(ModelConfig::new("m1", "k1", "https://a", "model-a"))
  // Empty id -> generated positional id, runtime_id synced
  config.add_model(ModelConfig::new("", "k2", "https://b", "model-b"))
  @debug.assert_eq(config.models.length(), 2)
  @debug.assert_eq(config.models[1].id, "model-1")
  @debug.assert_eq(config.models[1].runtime_id, "model-1")
  // Same model name still appends (no dedup-replace, Ruby add_model)
  config.add_model(ModelConfig::new("m3", "k3", "https://b", "model-b"))
  @debug.assert_eq(config.models.length(), 3)
  @debug.assert_eq(config.models[2].id, "m3")
}

///|
test "has_model_configured requires resolvable current model with api_key" {
  // p6 decision 7: the badge/current model must itself carry a key - a
  // different keyed model no longer satisfies the gate.
  let config = AgentConfig::default()
  let m1 = ModelConfig::new("m1", "key1", "https://a", "model-a")
  let m2 = ModelConfig::new("m2", "", "https://b", "model-b")
  m2.type_ = Some("default")
  config.models.push(m1)
  config.models.push(m2)
  assert_false(config.has_model_configured())
  // Switching to the keyed model satisfies it
  config.current_model_id = Some("m1")
  assert_true(config.has_model_configured())
  // No models at all
  assert_false(AgentConfig::default().has_model_configured())
}

// ── p6: CLACKY_LITE_* model injection and workspace env ────────────────────

///|
test "lite_env_model reads CLACKY_LITE_* variables" {
  @env.set_env_var("CLACKY_LITE_API_KEY", "sk-lite")
  @env.set_env_var("CLACKY_LITE_BASE_URL", "https://lite.example.com")
  @env.set_env_var("CLACKY_LITE_MODEL", "claude-haiku-4")
  match lite_env_model() {
    Some(m) => {
      @debug.assert_eq(m.api_key, "sk-lite")
      @debug.assert_eq(m.base_url, "https://lite.example.com")
      @debug.assert_eq(m.model, "claude-haiku-4")
      @debug.assert_eq(m.id, "lite")
      @debug.assert_eq(m.type_, Some("lite"))
      assert_true(m.anthropic_format)
    }
    None => fail("expected lite model from env")
  }
  // Defaults when BASE_URL/MODEL are unset
  @env.unset_env_var("CLACKY_LITE_BASE_URL")
  @env.unset_env_var("CLACKY_LITE_MODEL")
  match lite_env_model() {
    Some(m) => {
      @debug.assert_eq(m.base_url, "https://api.anthropic.com")
      @debug.assert_eq(m.model, "claude-haiku-4")
    }
    None => fail("expected lite model with defaults")
  }
  @env.unset_env_var("CLACKY_LITE_API_KEY")
  assert_true(lite_env_model() is None)
}

///|
test "load_with_env injects lite model, workspace dir and default badge" {
  let path = "/tmp/p6_load_with_env_test.toml"
  let content =
    #|[[models]]
    #|id = "m1"
    #|api_key = "sk-1"
    #|base_url = "https://api.1.com"
    #|model = "gpt-4"
  @fs.write_string_to_file(path, content) catch {
    _ => fail("write failed")
  }
  @env.set_env_var("CLACKY_LITE_API_KEY", "sk-lite")
  @env.set_env_var("CLACKY_WORKSPACE_DIR", "/tmp/p6-ws")
  let config = AgentConfig::load_with_env(path) catch {
    _ => fail("load failed")
  }
  // Lite model injected
  let lite = config.find_model_by_type("lite")
  assert_true(lite is Some(_))
  // Badge normalized onto the first model (none was badged in the file)
  @debug.assert_eq(config.models[0].type_, Some("default"))
  // Workspace dir filled from env
  @debug.assert_eq(config.default_working_dir, Some("/tmp/p6-ws"))
  @env.unset_env_var("CLACKY_LITE_API_KEY")
  @env.unset_env_var("CLACKY_WORKSPACE_DIR")
  @fs.remove_file(path) catch {
    _ => ()
  }
}

///|
test "load_with_env skips lite injection when a lite model exists" {
  let path = "/tmp/p6_load_with_env_test2.toml"
  let content =
    #|[[models]]
    #|api_key = "sk-1"
    #|base_url = "https://api.1.com"
    #|model = "gpt-4"
    #|
    #|[[models]]
    #|id = "lite"
    #|type = "lite"
    #|api_key = "sk-lite"
    #|base_url = "https://api.1.com"
    #|model = "haiku"
  @fs.write_string_to_file(path, content) catch {
    _ => fail("write failed")
  }
  @env.set_env_var("CLACKY_LITE_API_KEY", "sk-lite-other")
  let config = AgentConfig::load_with_env(path) catch {
    _ => fail("load failed")
  }
  let lite_models = config.models.filter(m => m.type_ == Some("lite"))
  @debug.assert_eq(lite_models.length(), 1)
  @debug.assert_eq(lite_models[0].api_key, "sk-lite")
  @env.unset_env_var("CLACKY_LITE_API_KEY")
  @fs.remove_file(path) catch {
    _ => ()
  }
}
