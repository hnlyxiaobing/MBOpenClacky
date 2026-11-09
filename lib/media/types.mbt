///|
/// Media generation providers
#derive(Eq, Debug, ToJson)
pub(all) enum MediaProvider {
  OpenAICompat
  Gemini
  DashScope
}

///|
pub extend MediaProvider with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend MediaProvider with Eq::{not_equal, equal}

///|
pub extend MediaProvider with ToJson::{to_json}

///|
/// Media type
#derive(Eq, Debug, ToJson)
pub(all) enum MediaType {
  Image
  Video
  Audio
}

///|
pub extend MediaType with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend MediaType with Eq::{not_equal, equal}

///|
pub extend MediaType with ToJson::{to_json}

///|
/// Media generation request
#derive(Eq, Debug, ToJson)
pub(all) struct MediaRequest {
  media_type : MediaType
  prompt : String
  aspect_ratio : String?
  duration_seconds : Int32?
  voice : String?
  output_dir : String
  model : String?
}

///|
pub extend MediaRequest with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend MediaRequest with Eq::{not_equal, equal}

///|
pub extend MediaRequest with ToJson::{to_json}

///|
/// Media generation result
#derive(Eq, Debug, ToJson)
pub(all) struct MediaResult {
  success : Bool
  file_path : String?
  error : String?
  error_type : MediaErrorType?
  provider : String
  model : String
  prompt : String
}

///|
pub extend MediaResult with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend MediaResult with Eq::{not_equal, equal}

///|
pub extend MediaResult with ToJson::{to_json}

///|
/// Media error types
#derive(Eq, Debug, ToJson)
pub(all) enum MediaErrorType {
  NotConfigured
  ApiError
  InvalidPrompt
  QuotaExceeded
  UnsupportedFormat
}

///|
pub extend MediaErrorType with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend MediaErrorType with Eq::{not_equal, equal}

///|
pub extend MediaErrorType with ToJson::{to_json}

///|
/// Media generation error
#derive(ToJson, Debug)
pub(all) suberror MediaError {
  MediaError(String)
}

///|
pub extend MediaError with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend MediaError with ToJson::{to_json}

///|
/// Speech-to-text request: transcribe a local audio file through an
/// OpenAI-compatible /audio/transcriptions endpoint.
#derive(Eq, Debug, ToJson)
pub(all) struct TranscriptionRequest {
  audio_path : String
  model : String?
}

///|
pub extend TranscriptionRequest with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend TranscriptionRequest with Eq::{not_equal, equal}

///|
pub extend TranscriptionRequest with ToJson::{to_json}

///|
/// Speech-to-text result: the transcript text, or a diagnostic error.
#derive(Eq, Debug, ToJson)
pub(all) struct TranscriptionResult {
  success : Bool
  text : String?
  error : String?
  provider : String
  model : String
}

///|
pub extend TranscriptionResult with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend TranscriptionResult with Eq::{not_equal, equal}

///|
pub extend TranscriptionResult with ToJson::{to_json}

///|
/// Create a MediaRequest for image generation
pub fn MediaRequest::image(
  prompt : String,
  output_dir : String,
  aspect_ratio~ : String? = None,
  model~ : String? = None,
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
  duration_seconds~ : Int32? = None,
  aspect_ratio~ : String? = None,
  model~ : String? = None,
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
  voice~ : String? = None,
  model~ : String? = None,
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
