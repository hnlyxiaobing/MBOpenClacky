///|
/// Vision processing result status
pub(all) enum VisionStatus {
  Ok
  Empty
  CallFailed
  BadImage
} derive(Eq, Debug, ToJson)

///|
pub extend VisionStatus with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend VisionStatus with Eq::{not_equal, equal}

///|
pub extend VisionStatus with ToJson::{to_json}

///|
/// Vision processing result
pub(all) struct VisionResult {
  status : VisionStatus
  text : String?
  error : String?
  cached : Bool
} derive(Eq, Debug, ToJson)

///|
pub extend VisionResult with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend VisionResult with Eq::{not_equal, equal}

///|
pub extend VisionResult with ToJson::{to_json}

///|
/// Image input types
pub(all) enum VisionInput {
  VisionBytes(Bytes)
  DataUrl(String)
  FilePath(String)
} derive(Debug)

///|
pub extend VisionInput with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// Vision resolver configuration
pub(all) struct VisionConfig {
  api_key : String
  base_url : String
  model : String
  max_tokens : Int
  cache_dir : String
  default_prompt : String
} derive(Eq, Debug)

///|
pub extend VisionConfig with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend VisionConfig with Eq::{not_equal, equal}

///|
/// Default max tokens for vision requests
let default_max_tokens : Int = 8192

///|
/// Default cache directory
let default_cache_dir : String = "~/.mbopenclacky/ocr_cache/"

///|
/// Default vision prompt
let default_vision_prompt : String = "Extract all text content from this image. Describe visual elements. Preserve table layouts using markdown formatting."

///|
/// Create a default VisionConfig
pub fn VisionConfig::default() -> VisionConfig {
  {
    api_key: "",
    base_url: "https://api.openai.com/v1",
    model: "gpt-4o",
    max_tokens: default_max_tokens,
    cache_dir: default_cache_dir,
    default_prompt: default_vision_prompt,
  }
}

///|
/// Create a VisionConfig with custom settings
pub fn VisionConfig::new(
  api_key : String,
  base_url : String,
  model : String,
  max_tokens? : Int = default_max_tokens,
  cache_dir? : String = default_cache_dir,
  default_prompt? : String = default_vision_prompt,
) -> VisionConfig {
  { api_key, base_url, model, max_tokens, cache_dir, default_prompt }
}

///|
/// Build OK result
pub fn ok_result(text : String, cached : Bool) -> VisionResult {
  { status: Ok, text: Some(text), error: None, cached }
}

///|
/// Build error result
pub fn error_result(status : VisionStatus, error : String) -> VisionResult {
  { status, text: None, error: Some(error), cached: false }
}

///|
/// Build empty result
pub fn empty_result() -> VisionResult {
  { status: Empty, text: None, error: None, cached: false }
}
