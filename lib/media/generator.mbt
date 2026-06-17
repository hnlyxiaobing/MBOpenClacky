///|
/// Main entry point for media generation - routes to correct provider
pub(all) struct MediaGenerator {
  base_url : String
  api_key : String
  model : String?
} derive(Debug)

///|
/// Create a new MediaGenerator
pub fn MediaGenerator::new(
  base_url : String,
  api_key : String,
  model : String?,
) -> MediaGenerator {
  { base_url, api_key, model }
}

///|
/// Detect provider from base_url
pub fn MediaGenerator::detect_provider(self : MediaGenerator) -> MediaProvider {
  let url = self.base_url.to_lower()
  if url.contains("generativelanguage.googleapis.com") ||
    url.contains("aiplatform.googleapis.com") {
    Gemini
  } else if url.contains("aliyuncs.com") || url.contains("dashscope") {
    DashScope
  } else {
    OpenAICompat
  }
}

///|
/// Generate image - routes to correct provider
pub fn MediaGenerator::generate_image(
  self : MediaGenerator,
  request : MediaRequest,
) -> MediaResult {
  let model = match self.model {
    Some(m) => m
    None =>
      match request.model {
        Some(m) => m
        None => "default"
      }
  }
  match self.detect_provider() {
    OpenAICompat =>
      openai_generate_image(self.base_url, self.api_key, model, request)
    Gemini => gemini_generate_image(self.base_url, self.api_key, model, request)
    DashScope =>
      dashscope_generate_image(self.base_url, self.api_key, model, request)
  }
}

///|
/// Generate video - routes to correct provider
pub fn MediaGenerator::generate_video(
  self : MediaGenerator,
  request : MediaRequest,
) -> MediaResult {
  let model = match self.model {
    Some(m) => m
    None =>
      match request.model {
        Some(m) => m
        None => "default"
      }
  }
  match self.detect_provider() {
    Gemini => gemini_generate_video(self.base_url, self.api_key, model, request)
    _ =>
      build_error(
        "Video generation is only supported by Gemini provider",
        UnsupportedFormat,
        provider_name(self.detect_provider()),
        model,
        request.prompt,
      )
  }
}

///|
/// Generate speech/audio - routes to correct provider
pub fn MediaGenerator::generate_speech(
  self : MediaGenerator,
  request : MediaRequest,
) -> MediaResult {
  let model = match self.model {
    Some(m) => m
    None =>
      match request.model {
        Some(m) => m
        None => "tts-1"
      }
  }
  match self.detect_provider() {
    OpenAICompat =>
      openai_generate_speech(self.base_url, self.api_key, model, request)
    _ =>
      build_error(
        "Speech generation is only supported by OpenAI-compatible providers",
        UnsupportedFormat,
        provider_name(self.detect_provider()),
        model,
        request.prompt,
      )
  }
}

///|
/// Build success result
pub fn build_success(
  file_path : String,
  provider : String,
  model : String,
  prompt : String,
) -> MediaResult {
  {
    success: true,
    file_path: Some(file_path),
    error: None,
    error_type: None,
    provider,
    model,
    prompt,
  }
}

///|
/// Build error result
pub fn build_error(
  error : String,
  error_type : MediaErrorType,
  provider : String,
  model : String,
  prompt : String,
) -> MediaResult {
  {
    success: false,
    file_path: None,
    error: Some(error),
    error_type: Some(error_type),
    provider,
    model,
    prompt,
  }
}

///|
/// Get provider name as string
pub fn provider_name(provider : MediaProvider) -> String {
  match provider {
    OpenAICompat => "openai_compat"
    Gemini => "gemini"
    DashScope => "dashscope"
  }
}
