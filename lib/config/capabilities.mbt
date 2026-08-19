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
pub extend ModelCapabilities with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ModelCapabilities with @moonbitlang/core/json.FromJson::{from_json}

///|
pub extend ModelCapabilities with Eq::{not_equal, equal}

///|
pub extend ModelCapabilities with ToJson::{to_json}

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
/// Per-model maximum output token limits (mirrors Ruby
/// `Providers::MODEL_MAX_OUTPUT`, providers.rb:690).
///
/// The agent global default (16_384) is tuned for the lowest common
/// denominator. Strong reasoning models (GLM-5.2, Kimi-K3, MiMo-V2.5)
/// support 64K–128K output but are artificially throttled to 16K, causing
/// truncation on long reasoning chains and code generation.
///
/// Entries are matched in order; the first match wins. Models not listed
/// here fall back to the caller's max_tokens.
pub fn max_output_for(model : String) -> Int? {
  let m = model.to_lower()
  if m.find("glm") is Some(_) {
    Some(65536) // GLM-5.2: 128K output ceiling; 64K ample for reasoning+answer
  } else if m.find("kimi-k3") is Some(_) {
    Some(65536) // Kimi K3: max_completion_tokens=131072 (max 1M); 64K ample
  } else if m.find("mimo-v2.5-pro") is Some(_) {
    Some(65536) // MiMo-V2.5-Pro: max_completion_tokens=131072; 64K ample
  } else if m.find("mimo") is Some(_) {
    Some(32768) // MiMo-V2.5: max_completion_tokens=32768; full default ceiling
  } else if m.find("gemini") is Some(_) {
    Some(65536) // Gemini 3.x: 64K max output ceiling
  } else {
    None
  }
}

///|
/// Whether a provider+model supports vision input, using the conservative
/// default semantics of Ruby `Providers.supports?` (providers.rb:1151):
/// an unknown provider (or missing provider_id) defaults to `true`, and only
/// an explicitly-declared `vision: false` capability yields `false`.
/// Unlike `get_model_capabilities`, this never falls back to `text_only()`
/// for unknown presets, so a freshly-added provider is assumed vision-capable
/// until declared otherwise.
pub fn model_supports_vision(provider_id : String?, model : String) -> Bool {
  match provider_id {
    None => true
    Some(pid) =>
      match Providers::find(pid) {
        None => true
        Some(_) => get_model_capabilities(pid, model).vision
      }
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
