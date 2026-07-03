///| Media generation REST API handlers.
/// These handlers are currently stubs returning 501 Not Implemented.
/// They will be wired to @media.MediaGenerator once the media-capabilities
/// branch lands and exposes transcription / video-understanding APIs.

// ── Types ─────────────────────────────────────────────────────────

///|
struct MediaErrorResponse {
  ok : Bool
  message : String
} derive(ToJson)

// ── Handlers ──────────────────────────────────────────────────────

///|
/// POST /api/media/image
fn handle_media_image(
  _server_ref : Ref[WebServer],
  _event : @crescent.Event,
) -> @core.HttpResponse {
  @core.HttpResponse::http_response(
    status_code=@core.StatusCode::NotImplemented,
  ).json_value(
    MediaErrorResponse::{
      ok: false,
      message: "Media image generation not yet implemented",
    }.to_json(),
  )
}

///|
/// POST /api/media/video
fn handle_media_video(
  _server_ref : Ref[WebServer],
  _event : @crescent.Event,
) -> @core.HttpResponse {
  @core.HttpResponse::http_response(
    status_code=@core.StatusCode::NotImplemented,
  ).json_value(
    MediaErrorResponse::{
      ok: false,
      message: "Media video generation not yet implemented",
    }.to_json(),
  )
}

///|
/// POST /api/media/audio/speech
fn handle_media_speech(
  _server_ref : Ref[WebServer],
  _event : @crescent.Event,
) -> @core.HttpResponse {
  @core.HttpResponse::http_response(
    status_code=@core.StatusCode::NotImplemented,
  ).json_value(
    MediaErrorResponse::{
      ok: false,
      message: "Media speech synthesis not yet implemented",
    }.to_json(),
  )
}

///|
/// POST /api/media/audio/transcriptions
fn handle_media_transcription(
  _server_ref : Ref[WebServer],
  _event : @crescent.Event,
) -> @core.HttpResponse {
  @core.HttpResponse::http_response(
    status_code=@core.StatusCode::NotImplemented,
  ).json_value(
    MediaErrorResponse::{
      ok: false,
      message: "Media transcription not yet implemented",
    }.to_json(),
  )
}

///|
/// POST /api/media/video/understand
fn handle_media_video_understand(
  _server_ref : Ref[WebServer],
  _event : @crescent.Event,
) -> @core.HttpResponse {
  @core.HttpResponse::http_response(
    status_code=@core.StatusCode::NotImplemented,
  ).json_value(
    MediaErrorResponse::{
      ok: false,
      message: "Video understanding not yet implemented",
    }.to_json(),
  )
}
