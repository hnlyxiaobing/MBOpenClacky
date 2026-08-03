///|
/// Configuration loader: TOML parsing, environment variable overlay, and persistence.
///
/// Config priority: config.toml > environment variables > defaults.
/// Modeled after Ruby's `lib/clacky/agent_config.rb`.
using @toml {type TomlValue}

///|
/// Load an AgentConfig from a TOML file at the given path.
/// Returns default config if the file doesn't exist.
/// Raises on malformed TOML.
pub fn AgentConfig::load(path : String) -> AgentConfig raise {
  if !@fs.path_exists(path) {
    return AgentConfig::default()
  }
  let content = @fs.read_file_to_string(path)
  let toml_value = @toml.parse(content)
  AgentConfig::from_toml(toml_value)
}

///|
/// Load configuration with environment variable overlay.
/// Priority: TOML file (base) < CLAUDE_* < OPENCLACKY_* < CLACKY_* (highest).
/// Environment variables override values from the config file.
pub fn AgentConfig::load_with_env(path : String) -> AgentConfig raise {
  let config = AgentConfig::load(path)
  config.env_source = "toml"
  // Apply legacy MBOPENCLACKY_* overlay for backward compatibility
  let after_legacy = config.apply_env_overlay()
  // Apply priority-based env layers (CLACKY > OPENCLACKY > CLAUDE)
  let env_config = load_config_from_env()
  if env_config.env_source != "toml" {
    merge_config(after_legacy, env_config)
  } else {
    after_legacy
  }
}

///|
/// Save an AgentConfig to a TOML file at the given path.
/// Creates parent directories if they don't exist.
pub fn AgentConfig::save(self : AgentConfig, path : String) -> Unit raise {
  @utils.ensure_dir(@path.Path::dirname(@path.Path(path)).to_string())
  let toml_value = self.to_toml()
  let content = toml_value.to_string()
  @fs.write_string_to_file(path, content)
}

///|
/// Load config from the default location (~/.mbopenclacky/config.toml).
/// Returns default config if the file or home dir doesn't exist.
pub fn AgentConfig::load_default() -> AgentConfig raise {
  match @utils.config_file() {
    Some(path) => AgentConfig::load_with_env(path)
    None => AgentConfig::default()
  }
}

// ---- TOML <-> AgentConfig conversion ----

///|
/// Construct an AgentConfig from a parsed TOML value.
fn AgentConfig::from_toml(value : TomlValue) -> AgentConfig {
  let config = AgentConfig::default()
  match value {
    TomlTable(root) => {
      // Parse [settings] section
      match root.get("settings") {
        Some(TomlTable(settings)) => {
          match settings.get("permission_mode") {
            Some(TomlString(s)) =>
              match PermissionMode::from_string(s) {
                Some(mode) => config.permission_mode = mode
                None => ()
              }
            _ => ()
          }
          match settings.get("max_tokens") {
            Some(TomlInteger(n)) => config.max_tokens = n.to_int()
            _ => ()
          }
          match settings.get("verbose") {
            Some(TomlBoolean(b)) => config.verbose = b
            _ => ()
          }
          match settings.get("enable_compression") {
            Some(TomlBoolean(b)) => config.enable_compression = b
            _ => ()
          }
          match settings.get("enable_prompt_caching") {
            Some(TomlBoolean(b)) => config.enable_prompt_caching = b
            _ => ()
          }
          match settings.get("memory_update_enabled") {
            Some(TomlBoolean(b)) => config.memory_update_enabled = b
            _ => ()
          }
          match settings.get("max_running_agents") {
            Some(TomlInteger(n)) => config.max_running_agents = n.to_int()
            _ => ()
          }
          match settings.get("max_idle_agents") {
            Some(TomlInteger(n)) => config.max_idle_agents = n.to_int()
            _ => ()
          }
          match settings.get("current_model_id") {
            Some(TomlString(s)) => config.current_model_id = Some(s)
            _ => ()
          }
          match settings.get("proxy_url") {
            Some(TomlString(s)) => config.proxy_url = s
            _ => ()
          }
          match settings.get("fallback_model") {
            Some(TomlString(s)) => config.fallback_model = s
            _ => ()
          }
          match settings.get("compression_threshold") {
            Some(TomlInteger(n)) => config.compression_threshold = n.to_int()
            _ => ()
          }
          match settings.get("default_working_dir") {
            Some(TomlString(s)) => config.default_working_dir = Some(s)
            _ => ()
          }
        }
        _ => ()
      }

      // Parse [[models]] array
      match root.get("models") {
        Some(TomlArray(arr)) => {
          let models = []
          for item in arr {
            match ModelConfig::from_toml(item) {
              Some(m) => models.push(m)
              None => ()
            }
          }
          config.models = models
        }
        _ => ()
      }
    }
    _ => ()
  }
  config
}

///|
/// Construct a ModelConfig from a parsed TOML table value.
fn ModelConfig::from_toml(value : TomlValue) -> ModelConfig? {
  match value {
    TomlTable(table) => {
      let id = match table.get("id") {
        Some(TomlString(s)) => s
        _ => return None
      }
      let api_key = match table.get("api_key") {
        Some(TomlString(s)) => s
        _ => ""
      }
      let base_url = match table.get("base_url") {
        Some(TomlString(s)) => s
        _ => return None
      }
      let model = match table.get("model") {
        Some(TomlString(s)) => s
        _ => return None
      }
      let type_ = match table.get("type") {
        Some(TomlString(s)) => Some(s)
        _ => None
      }
      let anthropic_format = match table.get("anthropic_format") {
        Some(TomlBoolean(b)) => b
        _ => false
      }
      let media_type = match table.get("media_type") {
        Some(TomlString(s)) => Some(s)
        _ => None
      }
      Some({
        id,
        type_,
        api_key,
        base_url,
        model,
        anthropic_format,
        runtime_id: id,
        media_type,
      })
    }
    _ => None
  }
}

///|
/// Convert an AgentConfig to a TOML value for serialization.
fn AgentConfig::to_toml(self : AgentConfig) -> TomlValue {
  let root : Map[String, TomlValue] = Map([])

  // Build [settings] section
  let settings : Map[String, TomlValue] = Map([])
  settings["permission_mode"] = TomlString(
    self.permission_mode.to_string_value(),
  )
  settings["max_tokens"] = TomlInteger(Int64::from_int(self.max_tokens))
  settings["verbose"] = TomlBoolean(self.verbose)
  settings["enable_compression"] = TomlBoolean(self.enable_compression)
  settings["enable_prompt_caching"] = TomlBoolean(self.enable_prompt_caching)
  settings["memory_update_enabled"] = TomlBoolean(self.memory_update_enabled)
  settings["max_running_agents"] = TomlInteger(
    Int64::from_int(self.max_running_agents),
  )
  settings["max_idle_agents"] = TomlInteger(
    Int64::from_int(self.max_idle_agents),
  )
  match self.current_model_id {
    Some(id) => settings["current_model_id"] = TomlString(id)
    None => ()
  }
  if !self.proxy_url.is_empty() {
    settings["proxy_url"] = TomlString(self.proxy_url)
  }
  if !self.fallback_model.is_empty() {
    settings["fallback_model"] = TomlString(self.fallback_model)
  }
  if self.compression_threshold != 150000 {
    settings["compression_threshold"] = TomlInteger(
      Int64::from_int(self.compression_threshold),
    )
  }
  match self.default_working_dir {
    Some(dir) => settings["default_working_dir"] = TomlString(dir)
    None => ()
  }
  root["settings"] = TomlTable(settings)

  // Build [[models]] array
  if !self.models.is_empty() {
    let model_arr : Array[TomlValue] = []
    for m in self.models {
      model_arr.push(m.to_toml())
    }
    root["models"] = TomlArray(model_arr)
  }

  TomlTable(root)
}

///|
/// Convert a ModelConfig to a TOML value for serialization.
fn ModelConfig::to_toml(self : ModelConfig) -> TomlValue {
  let table : Map[String, TomlValue] = Map([])
  table["id"] = TomlString(self.id)
  match self.type_ {
    Some(t) => table["type"] = TomlString(t)
    None => ()
  }
  table["api_key"] = TomlString(self.api_key)
  table["base_url"] = TomlString(self.base_url)
  table["model"] = TomlString(self.model)
  if self.anthropic_format {
    table["anthropic_format"] = TomlBoolean(true)
  }
  match self.media_type {
    Some(mt) => table["media_type"] = TomlString(mt)
    None => ()
  }
  TomlTable(table)
}

// ---- Environment variable overlay ----

///|
/// Apply environment variable overrides to the config.
/// MBOPENCLACKY_* variables take precedence over config file values.
pub fn AgentConfig::apply_env_overlay(self : AgentConfig) -> AgentConfig {
  let config = self
  // If no models are configured, try to create one from env vars
  if config.models.is_empty() {
    match @utils.env_var("MBOPENCLACKY_API_KEY") {
      Some(api_key) => {
        let base_url = match @utils.env_var("MBOPENCLACKY_BASE_URL") {
          Some(url) => url
          None => "https://api.anthropic.com"
        }
        let model = match @utils.env_var("MBOPENCLACKY_MODEL") {
          Some(m) => m
          None => "claude-sonnet-4-5"
        }
        let anthropic_format = match
          @utils.env_var("MBOPENCLACKY_ANTHROPIC_FORMAT") {
          Some(v) => v.to_lower() != "false"
          None => true
        }
        let env_model : ModelConfig = {
          id: "default",
          type_: Some("default"),
          api_key,
          base_url,
          model,
          anthropic_format,
          runtime_id: "default",
          media_type: None,
        }
        config.models.push(env_model)
        if config.current_model_id is None {
          config.current_model_id = Some("default")
        }
      }
      None => ()
    }
  }

  // Override verbose flag
  if @utils.env_bool("MBOPENCLACKY_VERBOSE") {
    config.verbose = true
  }

  config
}

// ---- Config helpers ----

///|
/// Find the model badged as "default" in the Settings UI, if any.
fn AgentConfig::default_badged_model(self : AgentConfig) -> ModelConfig? {
  for m in self.models {
    match m.type_ {
      Some(t) if t == "default" => return Some(m)
      _ => ()
    }
  }
  None
}

///|
/// Get the currently active model config, or None if no model is selected.
/// Preference order: the model badged "default" (the user-facing default in
/// Settings) > current_model_id (legacy/TUI selection when no badge exists)
/// > single configured model > None. All write paths (Settings badge,
/// switch_model_by_id/name, session_model_overlay) keep the two notions in
/// sync; where a legacy config still disagrees, the badge is the most recent
/// explicit user choice and wins.
pub fn AgentConfig::current_model(self : AgentConfig) -> ModelConfig? {
  match self.default_badged_model() {
    Some(m) => Some(m)
    None =>
      match self.current_model_id {
        Some(id) => {
          for m in self.models {
            if m.id == id {
              return Some(m)
            }
          }
          None
        }
        None =>
          // If only one model, return it
          if self.models.length() == 1 {
            Some(self.models[0])
          } else {
            None
          }
      }
  }
}

///|
/// Check if at least one model is configured with a valid API key.
pub fn AgentConfig::has_model_configured(self : AgentConfig) -> Bool {
  for m in self.models {
    if !m.api_key.is_empty() {
      return true
    }
  }
  false
}
