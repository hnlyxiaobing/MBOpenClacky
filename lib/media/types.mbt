///|
/// Media generation providers
pub(all) enum MediaProvider {
  OpenAICompat
  Gemini
  DashScope
} derive(Eq, Debug, ToJson)

///|
pub extend MediaProvider with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend MediaProvider with Eq::{not_equal, equal}

///|
pub extend MediaProvider with ToJson::{to_json}

///|
/// Media type
pub(all) enum MediaType {
  Image
  Video
  Audio
} derive(Eq, Debug, ToJson)

///|
pub extend MediaType with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend MediaType with Eq::{not_equal, equal}

///|
pub extend MediaType with ToJson::{to_json}

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
pub extend MediaRequest with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend MediaRequest with Eq::{not_equal, equal}

///|
pub extend MediaRequest with ToJson::{to_json}

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
pub extend MediaResult with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend MediaResult with Eq::{not_equal, equal}

///|
pub extend MediaResult with ToJson::{to_json}

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
pub extend MediaErrorType with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend MediaErrorType with Eq::{not_equal, equal}

///|
pub extend MediaErrorType with ToJson::{to_json}

///|
/// Media generation error
pub(all) suberror MediaError {
  MediaError(String)
} derive(ToJson, Debug)

///|
pub extend MediaError with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend MediaError with ToJson::{to_json}

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
