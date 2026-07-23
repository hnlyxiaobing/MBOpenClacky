///| White-box tests for Media API handlers.
/// Image/video/speech/transcription remain stubs (501).
/// Video understanding is implemented via FFmpeg + LLM vision.

///|
fn make_media_event(
  http_method : @crescent.HttpMethod,
  url : String,
  body? : String = "",
) -> @crescent.Event {
  {
    req: @crescent.HttpRequest::HttpRequest(
      http_method,
      url,
      Map([]),
      raw_body=@utf8.encode(body),
    ),
    res: @crescent.HttpResponse::HttpResponse(status_code=OK),
    params: Map([]),
  }
}

///|
fn make_media_server_ref() -> Ref[WebServer] {
  Ref(WebServer::new(@config.AgentConfig::default(), None))
}

///|
fn media_response_json(resp : @core.HttpResponse) -> Json {
  @json.parse(@utf8.decode(resp.raw_body)) catch {
    _ => Json::object(Map([]))
  }
}

// ── Stub endpoints (501) ───────────────────────────────────────────

///|
test "media image returns 501 stub" {
  let resp = handle_media_image(
    make_media_server_ref(),
    make_media_event(Post, "/api/media/image"),
  )
  @debug.assert_eq(resp.status_code.to_int(), 501)
}

///|
test "media video returns 501 stub" {
  let resp = handle_media_video(
    make_media_server_ref(),
    make_media_event(Post, "/api/media/video"),
  )
  @debug.assert_eq(resp.status_code.to_int(), 501)
}

///|
test "media speech returns 501 stub" {
  let resp = handle_media_speech(
    make_media_server_ref(),
    make_media_event(Post, "/api/media/audio/speech"),
  )
  @debug.assert_eq(resp.status_code.to_int(), 501)
}

///|
test "media transcription returns 501 stub" {
  let resp = handle_media_transcription(
    make_media_server_ref(),
    make_media_event(Post, "/api/media/audio/transcriptions"),
  )
  @debug.assert_eq(resp.status_code.to_int(), 501)
}

// ── Video Understanding ───────────────────────────────────────────

///|
test "video understand with empty body returns 400" {
  let resp = handle_media_video_understand(
    make_media_server_ref(),
    make_media_event(Post, "/api/media/video/understand"),
  )
  @debug.assert_eq(resp.status_code.to_int(), 400)
  let j = media_response_json(resp)
  guard j is Object(obj)
  @debug.assert_eq(obj.get("ok"), Some(false.to_json()))
}

///|
test "video understand with non-object JSON returns 400" {
  let resp = handle_media_video_understand(
    make_media_server_ref(),
    make_media_event(Post, "/api/media/video/understand", body="42"),
  )
  @debug.assert_eq(resp.status_code.to_int(), 400)
  let j = media_response_json(resp)
  guard j is Object(obj)
  @debug.assert_eq(obj.get("ok"), Some(false.to_json()))
}

///|
test "video understand with invalid JSON returns 400" {
  let resp = handle_media_video_understand(
    make_media_server_ref(),
    make_media_event(Post, "/api/media/video/understand", body="not-json"),
  )
  @debug.assert_eq(resp.status_code.to_int(), 400)
  let j = media_response_json(resp)
  guard j is Object(obj)
  @debug.assert_eq(obj.get("ok"), Some(false.to_json()))
}

///|
test "video understand with no model configured returns 500" {
  let resp = handle_media_video_understand(
    make_media_server_ref(),
    make_media_event(Post, "/api/media/video/understand", body="{}"),
  )
  @debug.assert_eq(resp.status_code.to_int(), 500)
  let j = media_response_json(resp)
  guard j is Object(obj)
  @debug.assert_eq(obj.get("ok"), Some(false.to_json()))
  let err = match obj.get("error") {
    Some(s) => @debug.to_string(s)
    None => ""
  }
  assert_true(err.contains("vision"))
}

///|
test "video understand with video_path but no model returns 500" {
  let resp = handle_media_video_understand(
    make_media_server_ref(),
    make_media_event(
      Post,
      "/api/media/video/understand",
      body="{\"video_path\":\"/tmp/nonexistent.mp4\"}",
    ),
  )
  @debug.assert_eq(resp.status_code.to_int(), 500)
  let j = media_response_json(resp)
  guard j is Object(obj)
  @debug.assert_eq(obj.get("ok"), Some(false.to_json()))
}
