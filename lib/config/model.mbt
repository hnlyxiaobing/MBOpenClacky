///|
/// Configuration for a single LLM model endpoint.
pub(all) struct ModelConfig {
  id : String
  type_ : String?
  api_key : String
  base_url : String
  model : String
  anthropic_format : Bool
} derive(Eq, Debug, ToJson)

///|
/// Create a ModelConfig with sensible defaults.
pub fn ModelConfig::new(
  id : String,
  api_key : String,
  base_url : String,
  model : String,
) -> ModelConfig {
  { id, type_: None, api_key, base_url, model, anthropic_format: false }
}
