///| Environment variable compatibility layer.
///
/// Environment variable prefix priority:
/// 1. CLACKY_* (highest priority, project-specific)
/// 2. OPENCLACKY_* (legacy compatibility)
///
/// CLAUDE_* (ClaudeCode) support is disabled, matching Ruby agent_config.rb
/// where the ClaudeCodeEnv branch is commented out (p6 decision 5).

///|
/// Load configuration from environment variables with priority-based prefix resolution.
/// Tries CLACKY_ first, then OPENCLACKY_.
/// Returns a config with env_source set to the matched prefix layer.
pub fn load_config_from_env() -> AgentConfig {
  // Try each prefix in priority order
  match try_load_with_prefix("CLACKY") {
    Some(config) => {
      config.env_source = "env"
      config
    }
    None =>
      match try_load_with_prefix("OPENCLACKY") {
        Some(config) => {
          config.env_source = "env"
          config
        }
        None => {
          let config = AgentConfig::default()
          config.env_source = "toml"
          config
        }
      }
  }
}

///|
/// Try to load configuration from environment variables with a given prefix.
/// Returns Some(config) if at least an API key is found, None otherwise.
fn try_load_with_prefix(prefix : String) -> AgentConfig? {
  let api_key = @utils.env_var(prefix + "_API_KEY")
  match api_key {
    None => None
    Some(key) => {
      let config = AgentConfig::default()
      let model_name = match @utils.env_var(prefix + "_MODEL") {
        Some(m) => m
        None => "claude-sonnet-4-5"
      }
      let provider = @utils.env_var(prefix + "_PROVIDER")
      // Base URL resolution (p6 decision 4): explicit _BASE_URL >
      // provider preset default (when _PROVIDER names a known preset) >
      // Anthropic default.
      let base_url = match @utils.env_var(prefix + "_BASE_URL") {
        Some(u) => u
        None =>
          match provider {
            Some(p) =>
              match Providers::find(p) {
                Some(preset) => preset.base_url
                None => "https://api.anthropic.com"
              }
            None => "https://api.anthropic.com"
          }
      }
      // <prefix>_ANTHROPIC_FORMAT: unset/empty -> true, else "true"
      // (case-insensitive), matching ClackyEnv.default_anthropic_format.
      let anthropic_format = match
        @utils.env_var(prefix + "_ANTHROPIC_FORMAT") {
        Some(v) => v.to_lower() == "true"
        None => true
      }
      // Build a model config from env
      let env_model : ModelConfig = {
        id: "default",
        type_: match provider {
          Some(p) => Some(p)
          None => Some("default")
        },
        api_key: key,
        base_url,
        model: model_name,
        anthropic_format,
        runtime_id: "default",
        media_type: None,
      }
      config.models = [env_model]
      config.current_model_id = Some("default")
      // Apply optional fields
      match @utils.env_var(prefix + "_PROXY_URL") {
        Some(v) => config.proxy_url = v
        None => ()
      }
      match @utils.env_var(prefix + "_FALLBACK_MODEL") {
        Some(v) => config.fallback_model = v
        None => ()
      }
      match @utils.env_int(prefix + "_MAX_TOKENS") {
        Some(n) => config.max_tokens = n
        None => ()
      }
      match @utils.env_int(prefix + "_COMPRESSION_THRESHOLD") {
        Some(n) => config.compression_threshold = n
        None => ()
      }
      Some(config)
    }
  }
}

///|
/// Build a lite model config from CLACKY_LITE_* environment variables,
/// or None when CLACKY_LITE_API_KEY is unset (Ruby ClackyEnv.lite_model_config,
/// agent_config.rb:111-141).
pub fn lite_env_model() -> ModelConfig? {
  let api_key = @utils.env_var("CLACKY_LITE_API_KEY")
  match api_key {
    None => None
    Some(key) => {
      // Base URL resolution mirrors the default-model chain: explicit
      // _BASE_URL > Anthropic default (Ruby leaves it nil; MB requires a
      // non-optional string).
      let base_url = match @utils.env_var("CLACKY_LITE_BASE_URL") {
        Some(u) => u
        None => "https://api.anthropic.com"
      }
      let model = match @utils.env_var("CLACKY_LITE_MODEL") {
        Some(m) => m
        None => "claude-haiku-4"
      }
      let anthropic_format = match
        @utils.env_var("CLACKY_LITE_ANTHROPIC_FORMAT") {
        Some(v) => v.to_lower() == "true"
        None => true
      }
      Some({
        id: "lite",
        type_: Some("lite"),
        api_key: key,
        base_url,
        model,
        anthropic_format,
        runtime_id: "lite",
        media_type: None,
      })
    }
  }
}

///|
/// Get the environment variable key mappings for a given prefix.
/// Returns an array of (env_key, config_field_name) pairs.
pub fn env_key_mappings(prefix : String) -> Array[(String, String)] {
  [
    (prefix + "_API_KEY", "api_key"),
    (prefix + "_MODEL", "model"),
    (prefix + "_PROVIDER", "provider"),
    (prefix + "_BASE_URL", "base_url"),
    (prefix + "_PROXY_URL", "proxy_url"),
    (prefix + "_FALLBACK_MODEL", "fallback_model"),
    (prefix + "_MAX_TOKENS", "max_tokens"),
    (prefix + "_COMPRESSION_THRESHOLD", "compression_threshold"),
  ]
}

///|
/// Merge two AgentConfigs: non-default values in overlay override values in base.
/// String fields: non-empty overlay wins.
/// Int fields: non-zero overlay wins (except max_tokens where overlay > 0 wins).
/// Array fields: overlay models are appended by type (no duplicate type),
/// matching Ruby agent_config.rb:287-307; if no model is badged "default"
/// afterwards, the first model is badged default (agent_config.rb:305-307).
pub fn merge_config(base : AgentConfig, overlay : AgentConfig) -> AgentConfig {
  let result = base
  // Merge models: append overlay models whose type is not already present
  for m in overlay.models {
    let t = match m.type_ {
      Some(t) => t
      None => "default"
    }
    // A base model without an explicit type does NOT count as "default"
    // (Ruby has_default checks m["type"] == "default" exactly).
    let exists = result.models.any(fn(bm) {
      match bm.type_ {
        Some(bt) => bt == t
        None => false
      }
    })
    if !exists {
      result.models.push(m)
    }
  }
  // Ensure at least one model carries the "default" badge
  let has_default = result.models.any(fn(m) {
    match m.type_ {
      Some(t) => t == "default"
      None => false
    }
  })
  if !has_default && !result.models.is_empty() {
    result.models[0].type_ = Some("default")
  }
  // Merge current_model_id
  match overlay.current_model_id {
    Some(id) => result.current_model_id = Some(id)
    None => ()
  }
  // Merge scalar settings: overlay wins if non-default
  if overlay.max_tokens != 16384 && overlay.max_tokens > 0 {
    result.max_tokens = overlay.max_tokens
  }
  if !overlay.proxy_url.is_empty() {
    result.proxy_url = overlay.proxy_url
  }
  if !overlay.fallback_model.is_empty() {
    result.fallback_model = overlay.fallback_model
  }
  if overlay.compression_threshold != 150000 &&
    overlay.compression_threshold > 0 {
    result.compression_threshold = overlay.compression_threshold
  }
  // env_source: overlay wins if not "toml" (i.e. came from env)
  if overlay.env_source != "toml" {
    result.env_source = overlay.env_source
  }
  result
}
