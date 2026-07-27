///| Extended config tests: AgentConfig defaults, ModelCapabilities presets, model switching.

// ── AgentConfig::default Tests ──────────────────────────────────────────────

///|
test "ext_agent_config_default_fields" {
  let cfg = AgentConfig::default()
  assert_eq(cfg.max_tokens, 16384)
  assert_false(cfg.verbose)
  assert_true(cfg.enable_compression)
  assert_true(cfg.enable_prompt_caching)
  assert_eq(cfg.models.length(), 0)
  assert_true(cfg.current_model_id is None)
  assert_true(cfg.memory_update_enabled)
  assert_eq(cfg.max_running_agents, 10)
  assert_eq(cfg.max_idle_agents, 10)
  assert_eq(cfg.compression_threshold, 150000)
  assert_eq(cfg.env_source, "toml")
}

///|
test "ext_agent_config_mutable_fields" {
  let cfg = AgentConfig::default()
  cfg.max_tokens = 32768
  cfg.verbose = true
  cfg.memory_update_enabled = true
  cfg.proxy_url = "http://proxy:8080"
  cfg.fallback_model = "gpt-5.4"
  assert_eq(cfg.max_tokens, 32768)
  assert_true(cfg.verbose)
  assert_true(cfg.memory_update_enabled)
  assert_eq(cfg.proxy_url, "http://proxy:8080")
  assert_eq(cfg.fallback_model, "gpt-5.4")
}

///|
test "ext_agent_config_switch_model_empty_id" {
  let cfg = AgentConfig::default()
  let result = cfg.switch_model_by_id("")
  assert_true(result is Err(_))
}

///|
test "ext_agent_config_switch_model_not_found" {
  let cfg = AgentConfig::default()
  let result = cfg.switch_model_by_id("nonexistent")
  assert_true(result is Err(_))
}

///|
test "ext_agent_config_switch_model_by_name_empty" {
  let cfg = AgentConfig::default()
  let result = cfg.switch_model_by_name("  ")
  assert_true(result is Err(_))
}

///|
test "ext_agent_config_deep_copy_independence" {
  let cfg = AgentConfig::default()
  cfg.max_tokens = 100
  let copy = cfg.deep_copy()
  copy.max_tokens = 200
  assert_eq(cfg.max_tokens, 100)
  assert_eq(copy.max_tokens, 200)
}

// ── ModelCapabilities Presets ──────────────────────────────────────────────

///|
test "ext_capabilities_full" {
  let cap = ModelCapabilities::full()
  assert_true(cap.vision)
  assert_false(cap.audio)
  assert_false(cap.video)
  assert_true(cap.reasoning)
  assert_true(cap.function_calling)
  assert_true(cap.streaming)
  assert_true(cap.json_mode)
}

///|
test "ext_capabilities_text_only" {
  let cap = ModelCapabilities::text_only()
  assert_false(cap.vision)
  assert_false(cap.audio)
  assert_false(cap.video)
  assert_false(cap.reasoning)
  assert_true(cap.function_calling)
  assert_true(cap.streaming)
  assert_true(cap.json_mode)
}

///|
test "ext_capabilities_with_vision" {
  let cap = ModelCapabilities::with_vision()
  assert_true(cap.vision)
  assert_false(cap.reasoning)
  assert_true(cap.function_calling)
  assert_true(cap.streaming)
  assert_true(cap.json_mode)
}

///|
test "ext_capabilities_reasoning_model" {
  let cap = ModelCapabilities::reasoning_model()
  assert_true(cap.vision)
  assert_true(cap.reasoning)
  assert_true(cap.function_calling)
  assert_true(cap.streaming)
  assert_false(cap.json_mode)
}

///|
test "ext_capabilities_equality" {
  let c1 = ModelCapabilities::full()
  let c2 = ModelCapabilities::full()
  assert_true(c1 == c2)
  let c3 = ModelCapabilities::text_only()
  assert_true(c1 != c3)
}

// ── get_model_capabilities Tests ────────────────────────────────────────────

///|
test "ext_get_capabilities_unknown_provider" {
  let cap = get_model_capabilities("unknown-provider", "some-model")
  assert_false(cap.vision)
  assert_true(cap.function_calling)
  assert_true(cap.streaming)
}

///|
test "ext_get_api_type_unknown_provider" {
  let api_type = get_api_type_for_model("unknown-provider", "some-model")
  assert_eq(api_type, "openai-completions")
}

// ── ModelCapabilities Construction ─────────────────────────────────────────

///|
test "ext_capabilities_custom_construction" {
  let cap : ModelCapabilities = {
    vision: true,
    audio: true,
    video: false,
    reasoning: false,
    function_calling: true,
    streaming: false,
    json_mode: true,
  }
  assert_true(cap.vision)
  assert_true(cap.audio)
  assert_false(cap.video)
  assert_false(cap.streaming)
}

///|
test "ext_capabilities_to_json" {
  let cap = ModelCapabilities::full()
  let json = cap.to_json()
  match json {
    Object(obj) => {
      assert_eq(obj.get("vision"), Some(true.to_json()))
      assert_eq(obj.get("reasoning"), Some(true.to_json()))
    }
    _ => assert_true(false)
  }
}

// ── Additional AgentConfig Tests ────────────────────────────────────────────

///|
test "ext_agent_config_compression_threshold" {
  let cfg = AgentConfig::default()
  assert_eq(cfg.compression_threshold, 150000)
  cfg.compression_threshold = 5000
  assert_eq(cfg.compression_threshold, 5000)
}

///|
test "ext_agent_config_enable_caching" {
  let cfg = AgentConfig::default()
  assert_true(cfg.enable_prompt_caching)
  cfg.enable_prompt_caching = false
  assert_false(cfg.enable_prompt_caching)
}

///|
test "ext_agent_config_max_agents" {
  let cfg = AgentConfig::default()
  cfg.max_running_agents = 20
  cfg.max_idle_agents = 15
  assert_eq(cfg.max_running_agents, 20)
  assert_eq(cfg.max_idle_agents, 15)
}

///|
test "ext_agent_config_env_source" {
  let cfg = AgentConfig::default()
  cfg.env_source = "env"
  assert_eq(cfg.env_source, "env")
}

///|
test "ext_agent_config_deep_copy_independence_models" {
  let cfg = AgentConfig::default()
  let copy = cfg.deep_copy()
  assert_eq(copy.models.length(), 0)
}

///|
test "ext_agent_config_switch_model_by_name_not_found" {
  let cfg = AgentConfig::default()
  assert_true(cfg.switch_model_by_name("nonexistent") is Err(_))
}

// ── Additional ModelCapabilities Tests ───────────────────────────────────────

///|
test "ext_capabilities_full_has_vision_and_reasoning" {
  let cap = ModelCapabilities::full()
  assert_true(cap.vision)
  assert_true(cap.reasoning)
}

///|
test "ext_capabilities_text_only_no_special" {
  let cap = ModelCapabilities::text_only()
  assert_false(cap.vision)
  assert_false(cap.reasoning)
}

///|
test "ext_capabilities_reasoning_no_json_mode" {
  let cap = ModelCapabilities::reasoning_model()
  assert_true(cap.reasoning)
  assert_false(cap.json_mode)
}

///|
test "ext_get_capabilities_known_provider" {
  let cap = get_model_capabilities("anthropic", "claude-sonnet-4-5")
  assert_true(cap.function_calling)
  assert_true(cap.streaming)
}
