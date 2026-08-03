///|
/// Agent configuration, loaded from TOML config file and environment variables.
pub(all) struct AgentConfig {
  mut permission_mode : PermissionMode
  mut max_tokens : Int
  mut verbose : Bool
  mut enable_compression : Bool
  mut enable_prompt_caching : Bool
  mut models : Array[ModelConfig]
  mut current_model_id : String?
  mut memory_update_enabled : Bool
  mut skill_evolution : Json?
  mut max_running_agents : Int
  mut max_idle_agents : Int
  mut proxy_url : String
  mut fallback_model : String
  mut fallback_base_url : String?
  mut compression_threshold : Int
  mut env_source : String
  /// Default working directory for spawned processes.
  mut default_working_dir : String?
} derive(Eq, Debug, ToJson)

///|
/// Create an AgentConfig with sensible defaults.
pub fn AgentConfig::default() -> AgentConfig {
  {
    permission_mode: ConfirmSafes,
    max_tokens: 16384,
    verbose: false,
    enable_compression: true,
    enable_prompt_caching: true,
    models: [],
    current_model_id: None,
    memory_update_enabled: true,
    skill_evolution: None,
    max_running_agents: 10,
    max_idle_agents: 10,
    proxy_url: "",
    fallback_model: "",
    fallback_base_url: None,
    compression_threshold: 150000,
    env_source: "toml",
    default_working_dir: None,
  }
}

///|
/// Switch the current model by its stable runtime_id.
/// Returns Ok(()) on success, Err(message) if the id is not found.
pub fn AgentConfig::switch_model_by_id(
  self : AgentConfig,
  id : String,
) -> Result[Unit, String] {
  if id.is_empty() {
    return Err("model id must not be empty")
  }
  for m in self.models {
    if m.runtime_id == id || m.id == id {
      self.current_model_id = Some(m.id)
      // Keep the Settings "default" badge in sync so the two notions of
      // "default model" can never drift apart.
      self.set_default_badge(m.id)
      return Ok(())
    }
  }
  Err("model not found with id: \{id}")
}

///|
/// Switch the current model by its display name (case-insensitive exact match).
/// Returns Ok(()) on success, Err(message) if the name is not found.
pub fn AgentConfig::switch_model_by_name(
  self : AgentConfig,
  name : String,
) -> Result[Unit, String] {
  let trimmed = name.trim()
  if trimmed.is_empty() {
    return Err("model name must not be empty")
  }
  let lower : String = "\{name.trim().to_lower()}"
  for m in self.models {
    let ml : String = "\{m.model.to_lower()}"
    if ml == lower {
      self.current_model_id = Some(m.id)
      // Keep the Settings "default" badge in sync (see switch_model_by_id).
      self.set_default_badge(m.id)
      return Ok(())
    }
  }
  Err("model not found with name: \{trimmed}")
}

///|
/// Move the Settings "default" badge onto the given model id, clearing it
/// from every other model. The badge and current_model_id are two views of
/// the same "default model" notion and must never disagree.
fn AgentConfig::set_default_badge(self : AgentConfig, id : String) -> Unit {
  for m in self.models {
    if m.id == id {
      m.type_ = Some("default")
    } else {
      match m.type_ {
        Some(t) if t == "default" => m.type_ = None
        _ => ()
      }
    }
  }
}

///|
/// Dynamically add a model to the models mapping.
/// Assigns a runtime_id if one is not already set.
/// If a model with the same id already exists, it is replaced (dedup).
pub fn AgentConfig::add_model(self : AgentConfig, model : ModelConfig) -> Unit {
  if model.runtime_id.is_empty() {
    model.runtime_id = model.id
  }
  for i = 0; i < self.models.length(); i = i + 1 {
    if self.models[i].id == model.id {
      self.models[i] = model
      return
    }
  }
  self.models.push(model)
}

///|
/// Create a shallow copy of this config with the overlay replacing the current
/// model. Used by sub-agent forks to run on different credentials without
/// polluting the parent's shared model list.
/// The original config is NOT modified.
pub fn AgentConfig::virtual_model_overlay(
  self : AgentConfig,
  overlay : ModelConfig,
) -> AgentConfig {
  // Deep-copy so moving the "default" badge does not pollute the parent's
  // shared model list (current_model() is badge-first).
  let copy = self.deep_copy()
  // Replace current_model_id to point to the overlay
  copy.current_model_id = Some(overlay.id)
  // Add overlay to the copy's models if not already present
  let mut found = false
  for m in copy.models {
    if m.id == overlay.id {
      found = true
      break
    }
  }
  if !found {
    copy.models.push(overlay.deep_copy())
  }
  copy.set_default_badge(overlay.id)
  copy
}

///|
/// Create a copy of this config with a different model selected as current.
/// Used by WebUI for session-level model switching.
/// Returns Err if the model_id is not found.
pub fn AgentConfig::session_model_overlay(
  self : AgentConfig,
  model_id : String,
) -> Result[AgentConfig, String] {
  if model_id.is_empty() {
    return Err("model_id must not be empty")
  }
  let mut matched_id : String? = None
  for m in self.models {
    // The restore path passes the persisted API model string (model_name),
    // which may differ from both id and runtime_id.
    if m.id == model_id || m.runtime_id == model_id || m.model == model_id {
      matched_id = Some(m.id)
      break
    }
  }
  let matched = match matched_id {
    Some(id) => id
    None => return Err("model not found: \{model_id}")
  }
  // Deep-copy so moving the "default" badge on the copy does not mutate the
  // shared global config's models.
  let copy = self.deep_copy()
  // Normalize to the model id so current_model() lookups always succeed,
  // and move the badge so current_model() (badge-first) honors the session's
  // model selection on this copy.
  copy.current_model_id = Some(matched)
  copy.set_default_badge(matched)
  Ok(copy)
}

///|
/// Deep copy the entire configuration. Models array is deep-copied so
/// modifications to the copy do not affect the original.
pub fn AgentConfig::deep_copy(self : AgentConfig) -> AgentConfig {
  let new_models : Array[ModelConfig] = []
  for m in self.models {
    new_models.push(m.deep_copy())
  }
  {
    permission_mode: self.permission_mode,
    max_tokens: self.max_tokens,
    verbose: self.verbose,
    enable_compression: self.enable_compression,
    enable_prompt_caching: self.enable_prompt_caching,
    models: new_models,
    current_model_id: self.current_model_id,
    memory_update_enabled: self.memory_update_enabled,
    skill_evolution: self.skill_evolution,
    max_running_agents: self.max_running_agents,
    max_idle_agents: self.max_idle_agents,
    proxy_url: self.proxy_url,
    fallback_model: self.fallback_model,
    fallback_base_url: self.fallback_base_url,
    compression_threshold: self.compression_threshold,
    env_source: self.env_source,
    default_working_dir: self.default_working_dir,
  }
}

///|
/// Shallow copy of this config. Models array is shared (same reference).
fn AgentConfig::shallow_copy(self : AgentConfig) -> AgentConfig {
  let new_models : Array[ModelConfig] = []
  for m in self.models {
    new_models.push(m)
  }
  {
    permission_mode: self.permission_mode,
    max_tokens: self.max_tokens,
    verbose: self.verbose,
    enable_compression: self.enable_compression,
    enable_prompt_caching: self.enable_prompt_caching,
    models: new_models,
    current_model_id: self.current_model_id,
    memory_update_enabled: self.memory_update_enabled,
    skill_evolution: self.skill_evolution,
    max_running_agents: self.max_running_agents,
    max_idle_agents: self.max_idle_agents,
    proxy_url: self.proxy_url,
    fallback_model: self.fallback_model,
    fallback_base_url: self.fallback_base_url,
    compression_threshold: self.compression_threshold,
    env_source: self.env_source,
    default_working_dir: self.default_working_dir,
  }
}

///|
/// Derive a media model from the current provider for the given media_type.
/// For example: OpenAI → gpt-4o (image), tts-1 (audio).
/// Returns None if no current model or provider cannot be resolved.
pub fn AgentConfig::derive_media_model(
  self : AgentConfig,
  media_type : String,
) -> ModelConfig? {
  let anchor = self.current_model()
  match anchor {
    None => None
    Some(m) =>
      match Providers::resolve(m.base_url) {
        None => None
        Some(preset) => {
          let model_name = resolve_media_model_name(preset.id, media_type)
          match model_name {
            None => None
            Some(name) =>
              Some({
                id: "media-\{media_type}",
                type_: Some(media_type),
                api_key: m.api_key,
                base_url: m.base_url,
                model: name,
                anthropic_format: m.anthropic_format,
                runtime_id: "media-\{media_type}",
                media_type: Some(media_type),
              })
          }
        }
      }
  }
}

///|
/// Resolve a suitable media model name for a given provider and media type.
fn resolve_media_model_name(
  provider_id : String,
  media_type : String,
) -> String? {
  match provider_id {
    "openai" | "openclacky" | "openrouter" =>
      match media_type {
        "image" => Some("gpt-4o")
        "video" => None
        "audio" => Some("tts-1")
        "ocr" => Some("gpt-4o")
        _ => None
      }
    "anthropic" =>
      match media_type {
        "image" | "ocr" => Some("claude-sonnet-4-6")
        _ => None
      }
    "glm" =>
      match media_type {
        "image" | "ocr" => Some("glm-5v-turbo")
        _ => None
      }
    _ => None
  }
}

///|
/// Find a model by its media_type tag.
/// First looks for an explicitly configured model with matching media_type.
/// If not found, attempts to derive one from the current provider.
pub fn AgentConfig::find_model_by_type(
  self : AgentConfig,
  media_type : String,
) -> ModelConfig? {
  // 1. Look for an explicit model with matching media_type
  for m in self.models {
    match m.media_type {
      Some(mt) if mt == media_type => return Some(m)
      _ => ()
    }
    // Also check type_ field for backward compat
    match m.type_ {
      Some(t) if t == media_type => return Some(m)
      _ => ()
    }
  }
  // 2. Try to derive from provider
  self.derive_media_model(media_type)
}

///|
/// Get a lite model config for the currently active model.
/// Resolution:
///   1. Explicit user-configured lite model (type_="lite")
///   2. Provider preset lite_models mapping
///   3. None if unavailable
pub fn AgentConfig::lite_model_config_for_current(
  self : AgentConfig,
) -> ModelConfig? {
  // 1. Explicit lite model
  for m in self.models {
    match m.type_ {
      Some("lite") => return Some(m)
      _ => ()
    }
  }
  // 2. Provider preset derivation
  match self.current_model() {
    None => None
    Some(primary) =>
      match Providers::lite_model(primary.base_url, primary.model) {
        None => None
        Some(lite_name) => {
          // If the current model IS already the lite model, skip
          if lite_name == primary.model {
            return None
          }
          Some({
            id: "lite:\{primary.id}",
            type_: Some("lite"),
            api_key: primary.api_key,
            base_url: primary.base_url,
            model: lite_name,
            anthropic_format: primary.anthropic_format,
            runtime_id: "lite:\{primary.id}",
            media_type: None,
          })
        }
      }
  }
}
