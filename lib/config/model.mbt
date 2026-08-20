///|
/// Configuration for a single LLM model endpoint.
pub(all) struct ModelConfig {
  /// Model entry id (runtime-only, not persisted; injected when missing).
  mut id : String
  mut type_ : String?
  api_key : String
  base_url : String
  model : String
  mut anthropic_format : Bool
  /// Stable runtime identifier (not persisted). Defaults to model id.
  mut runtime_id : String
  /// Optional media type tag: None=general, "image", "video", "audio", "ocr"
  mut media_type : String?
} derive(Eq, Debug, ToJson)

///|
pub extend ModelConfig with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ModelConfig with Eq::{not_equal, equal}

///|
pub extend ModelConfig with ToJson::{to_json}

///|
/// Create a ModelConfig with sensible defaults.
pub fn ModelConfig::new(
  id : String,
  api_key : String,
  base_url : String,
  model : String,
) -> ModelConfig {
  {
    id,
    type_: None,
    api_key,
    base_url,
    model,
    anthropic_format: false,
    runtime_id: id,
    media_type: None,
  }
}

///|
/// Create a deep copy of this ModelConfig.
pub fn ModelConfig::deep_copy(self : ModelConfig) -> ModelConfig {
  {
    id: self.id,
    type_: self.type_,
    api_key: self.api_key,
    base_url: self.base_url,
    model: self.model,
    anthropic_format: self.anthropic_format,
    runtime_id: self.runtime_id,
    media_type: self.media_type,
  }
}
