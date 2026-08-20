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
/// Priority: TOML file (base) < MBOPENCLACKY_* legacy < OPENCLACKY_* < CLACKY_*.
/// Environment variables override values from the config file.
/// After the env layers, CLACKY_LITE_* models are injected when missing
/// (Ruby agent_config.rb:111-141/297-301), CLACKY_WORKSPACE_DIR fills an
/// unset default_working_dir, and at least one "default" badge is ensured
/// (Ruby agent_config.rb:303-307).
pub fn AgentConfig::load_with_env(path : String) -> AgentConfig raise {
  let config = AgentConfig::load(path)
  config.env_source = "toml"
  // Apply legacy MBOPENCLACKY_* overlay for backward compatibility
  let after_legacy = config.apply_env_overlay()
  // Apply priority-based env layers (CLACKY > OPENCLACKY)
  let env_config = load_config_from_env()
  let merged = if env_config.env_source != "toml" {
    merge_config(after_legacy, env_config)
  } else {
    after_legacy
  }
  // Inject a lite model from CLACKY_LITE_* when no type="lite" model exists
  let has_lite = merged.models.any(fn(m) {
    match m.type_ {
      Some(t) => t == "lite"
      None => false
    }
  })
  if !has_lite {
    match lite_env_model() {
      Some(lite) => merged.models.push(lite)
      None => ()
    }
  }
  // CLACKY_WORKSPACE_DIR applies only when the file didn't set a value
  if merged.default_working_dir is None {
    match @utils.env_var("CLACKY_WORKSPACE_DIR") {
      Some(dir) => merged.default_working_dir = Some(dir)
      None => ()
    }
  }
  // Ensure at least one model carries the "default" badge (Ruby 303-307)
  let has_default = merged.models.any(fn(m) {
    match m.type_ {
      Some(t) => t == "default"
      None => false
    }
  })
  if !has_default && !merged.models.is_empty() {
    merged.models[0].type_ = Some("default")
  }
  merged
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
          match settings.get("enable_idle_compression") {
            Some(TomlBoolean(b)) => config.enable_idle_compression = b
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
          match settings.get("skill_evolution") {
            Some(v) => config.skill_evolution = Some(toml_to_json(v))
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
          // current_model_id is read for backward compatibility with configs
          // persisted by older builds; it is no longer written back
          // (p6 decision 2 - Ruby never persists it).
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
          match settings.get("clacky_license_server") {
            Some(TomlString(s)) => config.clacky_license_server = Some(s)
            _ => ()
          }
          match settings.get("compression_threshold") {
            Some(TomlInteger(n)) => config.compression_threshold = n.to_int()
            _ => ()
          }
          match settings.get("message_count_threshold") {
            Some(TomlInteger(n)) => config.message_count_threshold = n.to_int()
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
  // Inject runtime ids for models loaded without one and warn about models
  // missing base_url/model (Ruby keeps such entries; they are not dropped -
  // p6 decision 6). Ids are runtime-only and never persisted.
  for i = 0; i < config.models.length(); i = i + 1 {
    let m = config.models[i]
    if m.id.is_empty() {
      m.id = config.generate_model_id()
      m.runtime_id = m.id
    }
    if m.base_url.is_empty() {
      println("[config] warning: model '\{m.model}' has no base_url")
    }
    if m.model.is_empty() {
      println("[config] warning: model '\{m.id}' has no model name")
    }
  }
  // BUG-0014: 对齐 Ruby load（agent_config.rb:326-338）——无显式
  // current_model_id 时自动锚定 default badge 模型，否则回退第一个模型。
  if config.current_model_id is None && config.models.length() > 0 {
    match config.default_badged_model() {
      Some(m) => config.current_model_id = Some(m.id)
      None => config.current_model_id = Some(config.models[0].id)
    }
  }
  config
}

///|
/// Construct a ModelConfig from a parsed TOML table value.
/// Missing id/base_url/model no longer drop the entry (p6 decision 6,
/// Ruby parse_models keeps incomplete entries): id is injected at runtime by
/// AgentConfig::from_toml; missing base_url/model stay empty with a warning.
/// Returns None only for non-table values.
fn ModelConfig::from_toml(value : TomlValue) -> ModelConfig? {
  match value {
    TomlTable(table) => {
      let id = match table.get("id") {
        Some(TomlString(s)) => s
        _ => ""
      }
      let api_key = match table.get("api_key") {
        Some(TomlString(s)) => s
        _ => ""
      }
      let base_url = match table.get("base_url") {
        Some(TomlString(s)) => s
        _ => ""
      }
      let model = match table.get("model") {
        Some(TomlString(s)) => s
        _ => ""
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
/// current_model_id and model ids are runtime-only and never written back
/// (p6 decision 2/6 - Ruby to_yaml strips RUNTIME_ONLY_FIELDS and never
/// persists current_model_id).
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
  settings["enable_idle_compression"] = TomlBoolean(
    self.enable_idle_compression,
  )
  settings["enable_prompt_caching"] = TomlBoolean(self.enable_prompt_caching)
  settings["memory_update_enabled"] = TomlBoolean(self.memory_update_enabled)
  match self.skill_evolution {
    Some(json) => settings["skill_evolution"] = json_to_toml(json)
    None => ()
  }
  settings["max_running_agents"] = TomlInteger(
    Int64::from_int(self.max_running_agents),
  )
  settings["max_idle_agents"] = TomlInteger(
    Int64::from_int(self.max_idle_agents),
  )
  if !self.proxy_url.is_empty() {
    settings["proxy_url"] = TomlString(self.proxy_url)
  }
  if !self.fallback_model.is_empty() {
    settings["fallback_model"] = TomlString(self.fallback_model)
  }
  match self.clacky_license_server {
    Some(s) => settings["clacky_license_server"] = TomlString(s)
    None => ()
  }
  if self.compression_threshold != 150000 {
    settings["compression_threshold"] = TomlInteger(
      Int64::from_int(self.compression_threshold),
    )
  }
  if self.message_count_threshold != 200 {
    settings["message_count_threshold"] = TomlInteger(
      Int64::from_int(self.message_count_threshold),
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
/// The id is runtime-only and stripped (Ruby RUNTIME_ONLY_FIELDS).
fn ModelConfig::to_toml(self : ModelConfig) -> TomlValue {
  let table : Map[String, TomlValue] = Map([])
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

  // Override compression threshold
  match @utils.env_int("MBOPENCLACKY_COMPRESSION_THRESHOLD") {
    Some(n) => config.compression_threshold = n
    None => ()
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
/// Get the currently active model config, or None if no model is configured.
/// Resolution order (p6 decision 2, aligned with Ruby
/// resolve_current_model_entry): current_model_id (primary truth; a stale
/// id is cleared and resolution falls through) > the model badged
/// "default" > the first model (Ruby falls back to current_model_index,
/// which defaults to 0). A non-empty model list always resolves.
pub fn AgentConfig::current_model(self : AgentConfig) -> ModelConfig? {
  match self.current_model_id {
    Some(id) => {
      for m in self.models {
        if m.id == id {
          return Some(m)
        }
      }
      // Stale id (model deleted) - clear and fall through
      self.current_model_id = None
    }
    None => ()
  }
  match self.default_badged_model() {
    Some(m) => Some(m)
    None => if !self.models.is_empty() { Some(self.models[0]) } else { None }
  }
}

///|
/// Check if a usable model is configured: current_model() must resolve and
/// carry a non-empty api_key (p6 decision 7 - Ruby models_configured?
/// requires current_model to resolve; the api_key check tightens the web
/// server startup gate).
pub fn AgentConfig::has_model_configured(self : AgentConfig) -> Bool {
  match self.current_model() {
    Some(m) => !m.api_key.is_empty()
    None => false
  }
}

// ---- TomlValue <-> Json converters (for skill_evolution) ----

///|
/// Convert a TomlValue into the equivalent Json value.
/// Integers become JSON numbers (double); datetime becomes its string form.
fn toml_to_json(value : TomlValue) -> Json {
  match value {
    TomlString(s) => Json::string(s)
    TomlInteger(n) => Json::number(n.to_double())
    TomlFloat(f) => Json::number(f)
    TomlBoolean(b) => Json::boolean(b)
    TomlArray(arr) => {
      let items : Array[Json] = []
      for item in arr {
        items.push(toml_to_json(item))
      }
      Json::array(items)
    }
    TomlTable(table) => {
      let obj : Map[String, Json] = Map([])
      for k, v in table {
        obj[k] = toml_to_json(v)
      }
      Json::object(obj)
    }
    TomlDateTime(_) =>
      match value.datetime_info() {
        Some((_, s)) => Json::string(s)
        None => Json::string("")
      }
  }
}

///|
/// Convert a Json value into the equivalent TomlValue.
/// Json::Null becomes an empty string (TOML has no null).
fn json_to_toml(value : Json) -> TomlValue {
  match value {
    Null => TomlString("")
    True => TomlBoolean(true)
    False => TomlBoolean(false)
    Number(f, ..) => TomlFloat(f)
    String(s) => TomlString(s)
    Array(arr) => {
      let items : Array[TomlValue] = []
      for item in arr {
        items.push(json_to_toml(item))
      }
      TomlArray(items)
    }
    Object(obj) => {
      let table : Map[String, TomlValue] = Map([])
      for k, v in obj {
        table[k] = json_to_toml(v)
      }
      TomlTable(table)
    }
  }
}
