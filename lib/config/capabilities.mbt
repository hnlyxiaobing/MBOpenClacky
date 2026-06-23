///| Model capability declarations for provider/model feature detection.
///
/// Used to determine what features a specific model supports,
/// enabling the agent runtime to adapt behavior accordingly.

///|
/// Declares what capabilities a model supports.
pub(all) struct ModelCapabilities {
  /// Supports image input
  vision : Bool
  /// Supports audio input
  audio : Bool
  /// Supports video input
  video : Bool
  /// Supports reasoning/thinking mode
  reasoning : Bool
  /// Supports function/tool calling
  function_calling : Bool
  /// Supports streaming output
  streaming : Bool
  /// Supports structured JSON output mode
  json_mode : Bool
} derive(Debug, Eq, ToJson, FromJson)

///|
/// Full-capability model (e.g. Claude Sonnet/Opus, GPT-5.x).
/// Vision + reasoning + function calling + streaming + JSON mode.
pub fn ModelCapabilities::full() -> ModelCapabilities {
  {
    vision: true,
    audio: false,
    video: false,
    reasoning: true,
    function_calling: true,
    streaming: true,
    json_mode: true,
  }
}

///|
/// Text-only model with no multimodal or reasoning capabilities.
/// Supports function calling, streaming, and JSON mode.
pub fn ModelCapabilities::text_only() -> ModelCapabilities {
  {
    vision: false,
    audio: false,
    video: false,
    reasoning: false,
    function_calling: true,
    streaming: true,
    json_mode: true,
  }
}

///|
/// Vision-capable model without dedicated reasoning mode.
pub fn ModelCapabilities::with_vision() -> ModelCapabilities {
  {
    vision: true,
    audio: false,
    video: false,
    reasoning: false,
    function_calling: true,
    streaming: true,
    json_mode: true,
  }
}

///|
/// Dedicated reasoning model (e.g. o3, DeepSeek-R1).
/// Has vision and reasoning but typically no JSON mode.
pub fn ModelCapabilities::reasoning_model() -> ModelCapabilities {
  {
    vision: true,
    audio: false,
    video: false,
    reasoning: true,
    function_calling: true,
    streaming: true,
    json_mode: false,
  }
}

///|
/// Query the capabilities for a specific provider + model combination.
/// Lookup order:
/// 1. Exact match in provider's model_capabilities map
/// 2. Prefix match (e.g. "claude-" matches "claude-sonnet-4-6")
/// 3. Provider's default capabilities
pub fn get_model_capabilities(
  provider_id : String,
  model : String,
) -> ModelCapabilities {
  match Providers::find(provider_id) {
    Some(preset) => {
      // 1. Exact match
      match preset.model_capabilities.get(model) {
        Some(cap) => return cap
        None => ()
      }
      // 2. Prefix match — find longest matching prefix key
      let mut best_match : ModelCapabilities? = None
      let mut best_len = 0
      preset.model_capabilities.each(fn(key, value) {
        if key.length() > best_len && model.has_prefix(key) {
          best_match = Some(value)
          best_len = key.length()
        }
      })
      match best_match {
        Some(cap) => cap
        None => preset.capabilities
      }
    }
    None => ModelCapabilities::text_only()
  }
}

///|
/// Query the API type override for a specific model on a provider.
/// Some providers (e.g. OpenRouter) route to different upstream APIs
/// depending on the model. Returns the provider's default api_type string
/// if no override is defined.
pub fn get_api_type_for_model(provider_id : String, model : String) -> String {
  match Providers::find(provider_id) {
    Some(preset) =>
      // Check exact match in overrides
      match preset.model_api_overrides.get(model) {
        Some(api_type) => api_type
        None => {
          // Prefix match
          let mut best_match : String? = None
          let mut best_len = 0
          preset.model_api_overrides.each(fn(key, value) {
            if key.length() > best_len && model.has_prefix(key) {
              best_match = Some(value)
              best_len = key.length()
            }
          })
          match best_match {
            Some(api_type) => api_type
            None => preset.api_type.to_string_value()
          }
        }
      }
    None => "openai-completions"
  }
}
