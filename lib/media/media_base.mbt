///|
/// Media generation capabilities
pub(all) enum MediaCapability {
  ImageGen
  VideoGen
  AudioGen
  SpeechSynth
} derive(Eq, Debug, ToJson)

///|
pub extend MediaCapability with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend MediaCapability with Eq::{not_equal, equal}

///|
pub extend MediaCapability with ToJson::{to_json}

///|
/// Media generator configuration
pub(all) struct MediaGeneratorConfig {
  base_url : String
  api_key : String
  model : String?
  output_dir : String
  timeout_seconds : Int
  retry_count : Int
  max_file_size_mb : Int
} derive(Eq, Debug)

///|
pub extend MediaGeneratorConfig with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend MediaGeneratorConfig with Eq::{not_equal, equal}

///|
/// Create a default configuration
pub fn MediaGeneratorConfig::default(
  base_url : String,
  api_key : String,
) -> MediaGeneratorConfig {
  {
    base_url,
    api_key,
    model: None,
    output_dir: "./output",
    timeout_seconds: 30,
    retry_count: 3,
    max_file_size_mb: 50,
  }
}

///|
/// Validate configuration, returning array of error messages
pub fn MediaGeneratorConfig::validate(
  self : MediaGeneratorConfig,
) -> Array[String] {
  let mut errors : Array[String] = []
  if self.base_url.length() == 0 {
    errors = errors + ["base_url must not be empty"]
  }
  if self.api_key.length() == 0 {
    errors = errors + ["api_key must not be empty"]
  }
  if self.timeout_seconds <= 0 {
    errors = errors + ["timeout_seconds must be greater than 0"]
  }
  if self.retry_count < 0 {
    errors = errors + ["retry_count must be non-negative"]
  }
  if self.max_file_size_mb <= 0 {
    errors = errors + ["max_file_size_mb must be greater than 0"]
  }
  errors
}

///|
/// Get capabilities for a provider
pub fn provider_capabilities(
  provider : MediaProvider,
) -> Array[MediaCapability] {
  match provider {
    OpenAICompat => [ImageGen, SpeechSynth]
    Gemini => [ImageGen, VideoGen]
    DashScope => [ImageGen]
  }
}

///|
/// Check if provider supports a specific capability
pub fn provider_supports(
  provider : MediaProvider,
  capability : MediaCapability,
) -> Bool {
  provider_capabilities(provider).iter().any(fn(c) { c == capability })
}

///|
/// Create a MediaGenerator from config
pub fn MediaGeneratorConfig::create_generator(
  self : MediaGeneratorConfig,
) -> MediaGenerator {
  MediaGenerator::new(self.base_url, self.api_key, self.model)
}

///|
/// Capability name for display
pub fn capability_name(cap : MediaCapability) -> String {
  match cap {
    ImageGen => "Image Generation"
    VideoGen => "Video Generation"
    AudioGen => "Audio Generation"
    SpeechSynth => "Speech Synthesis"
  }
}
