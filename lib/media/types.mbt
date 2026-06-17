///|
/// Media generation providers
pub(all) enum MediaProvider {
  OpenAICompat
  Gemini
  DashScope
} derive(Eq, Debug, ToJson)

///|
/// Media type
pub(all) enum MediaType {
  Image
  Video
  Audio
} derive(Eq, Debug, ToJson)

///|
/// Media generation request
pub(all) struct MediaRequest {
  media_type : MediaType
  prompt : String
  aspect_ratio : String?
  duration_seconds : Int?
  voice : String?
  output_dir : String
  model : String?
} derive(Eq, Debug, ToJson)

///|
/// Media generation result
pub(all) struct MediaResult {
  success : Bool
  file_path : String?
  error : String?
  error_type : MediaErrorType?
  provider : String
  model : String
  prompt : String
} derive(Eq, Debug, ToJson)

///|
/// Media error types
pub(all) enum MediaErrorType {
  NotConfigured
  ApiError
  InvalidPrompt
  QuotaExceeded
  UnsupportedFormat
} derive(Eq, Debug, ToJson)

///|
/// Media generation error
pub(all) suberror MediaError {
  MediaError(String)
} derive(ToJson, Debug)

///|
/// Create a MediaRequest for image generation
pub fn MediaRequest::image(
  prompt : String,
  output_dir : String,
  aspect_ratio? : String? = None,
  model? : String? = None,
) -> MediaRequest {
  {
    media_type: Image,
    prompt,
    aspect_ratio,
    duration_seconds: None,
    voice: None,
    output_dir,
    model,
  }
}

///|
/// Create a MediaRequest for video generation
pub fn MediaRequest::video(
  prompt : String,
  output_dir : String,
  duration_seconds? : Int? = None,
  aspect_ratio? : String? = None,
  model? : String? = None,
) -> MediaRequest {
  {
    media_type: Video,
    prompt,
    aspect_ratio,
    duration_seconds,
    voice: None,
    output_dir,
    model,
  }
}

///|
/// Create a MediaRequest for speech/audio generation
pub fn MediaRequest::speech(
  prompt : String,
  output_dir : String,
  voice? : String? = None,
  model? : String? = None,
) -> MediaRequest {
  {
    media_type: Audio,
    prompt,
    aspect_ratio: None,
    duration_seconds: None,
    voice,
    output_dir,
    model,
  }
}
