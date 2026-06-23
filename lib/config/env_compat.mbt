///| Environment variable compatibility layer for ClaudeCode and legacy prefixes.
///
/// Environment variable prefix priority:
/// 1. CLACKY_* (highest priority, project-specific)
/// 2. OPENCLACKY_* (legacy compatibility)
/// 3. CLAUDE_* (ClaudeCode compatibility)

///|
/// Load configuration from environment variables with priority-based prefix resolution.
/// Tries CLACKY_ first, then OPENCLACKY_, then CLAUDE_ (ClaudeCode compat).
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
        None =>
          match load_claude_compat() {
            Some(config) => {
              config.env_source = "claude_compat"
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
      let base_url = match @utils.env_var(prefix + "_BASE_URL") {
        Some(u) => u
        None => "https://api.anthropic.com"
      }
      // Build a model config from env
      let env_model : ModelConfig = {
        id: "default",
        type_: match @utils.env_var(prefix + "_PROVIDER") {
          Some(p) => Some(p)
          None => Some("default")
        },
        api_key: key,
        base_url,
        model: model_name,
        anthropic_format: true,
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
/// Load configuration from CLAUDE_* environment variables (ClaudeCode compatibility).
/// Maps CLAUDE_API_KEY, CLAUDE_MODEL, CLAUDE_BASE_URL, CLAUDE_MAX_TOKENS.
fn load_claude_compat() -> AgentConfig? {
  let api_key = @utils.env_var("CLAUDE_API_KEY")
  match api_key {
    None => None
    Some(key) => {
      let config = AgentConfig::default()
      let model_name = match @utils.env_var("CLAUDE_MODEL") {
        Some(m) => m
        None => "claude-sonnet-4-5"
      }
      let base_url = match @utils.env_var("CLAUDE_BASE_URL") {
        Some(u) => u
        None => "https://api.anthropic.com"
      }
      let env_model : ModelConfig = {
        id: "default",
        type_: Some("default"),
        api_key: key,
        base_url,
        model: model_name,
        anthropic_format: true,
      }
      config.models = [env_model]
      config.current_model_id = Some("default")
      match @utils.env_int("CLAUDE_MAX_TOKENS") {
        Some(n) => config.max_tokens = n
        None => ()
      }
      Some(config)
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
/// Array fields: non-empty overlay wins.
pub fn merge_config(base : AgentConfig, overlay : AgentConfig) -> AgentConfig {
  let result = base
  // Merge models: overlay wins if it has models
  if !overlay.models.is_empty() {
    result.models = overlay.models
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
  if overlay.compression_threshold != 10000 && overlay.compression_threshold > 0 {
    result.compression_threshold = overlay.compression_threshold
  }
  // env_source: overlay wins if not "toml" (i.e. came from env)
  if overlay.env_source != "toml" {
    result.env_source = overlay.env_source
  }
  result
}
