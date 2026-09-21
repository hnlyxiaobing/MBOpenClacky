///| White-box tests for Media API handlers.
/// Image/video/speech/transcription are wired through MediaGenerator; with
/// a default (unconfigured) config they return 400 diagnostics.
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

// ── Wired endpoints (MediaGenerator) ───────────────────────────────

///|
async test "media image rejects invalid JSON" {
  let resp = handle_media_image(
    make_media_server_ref(),
    make_media_event(Post, "/api/media/image", body="not-json"),
  )
  @debug.assert_eq(resp.status_code.to_int(), 400)
  let j = media_response_json(resp)
  guard! j is Json::Object(obj)
  @debug.assert_eq(obj.get("ok"), Some(false.to_json()))
}

///|
async test "media image without prompt returns 400" {
  let resp = handle_media_image(
    make_media_server_ref(),
    make_media_event(Post, "/api/media/image", body="{}"),
  )
  @debug.assert_eq(resp.status_code.to_int(), 400)
  let j = media_response_json(resp)
  guard! j is Json::Object(obj)
  @debug.assert_eq(obj.get("ok"), Some(false.to_json()))
  let msg = match obj.get("message") {
    Some(s) => @debug.to_string(s)
    None => ""
  }
  assert_true(msg.contains("prompt"))
}

///|
async test "media image without configured model returns 400" {
  let resp = handle_media_image(
    make_media_server_ref(),
    make_media_event(Post, "/api/media/image", body="{\"prompt\":\"a cat\"}"),
  )
  @debug.assert_eq(resp.status_code.to_int(), 400)
  let j = media_response_json(resp)
  guard! j is Json::Object(obj)
  @debug.assert_eq(obj.get("ok"), Some(false.to_json()))
  let msg = match obj.get("message") {
    Some(s) => @debug.to_string(s)
    None => ""
  }
  assert_true(msg.contains("image"))
}

///|
async test "media video without configured model returns 400" {
  let resp = handle_media_video(
    make_media_server_ref(),
    make_media_event(Post, "/api/media/video", body="{\"prompt\":\"waves\"}"),
  )
  @debug.assert_eq(resp.status_code.to_int(), 400)
  let j = media_response_json(resp)
  guard! j is Json::Object(obj)
  @debug.assert_eq(obj.get("ok"), Some(false.to_json()))
}

///|
async test "media speech without configured model returns 400" {
  let resp = handle_media_speech(
    make_media_server_ref(),
    make_media_event(
      Post,
      "/api/media/audio/speech",
      body="{\"input\":\"hello\"}",
    ),
  )
  @debug.assert_eq(resp.status_code.to_int(), 400)
  let j = media_response_json(resp)
  guard! j is Json::Object(obj)
  @debug.assert_eq(obj.get("ok"), Some(false.to_json()))
}

///|
async test "media transcription without audio_path returns 400" {
  let resp = handle_media_transcription(
    make_media_server_ref(),
    make_media_event(Post, "/api/media/audio/transcriptions", body="{}"),
  )
  @debug.assert_eq(resp.status_code.to_int(), 400)
  let j = media_response_json(resp)
  guard! j is Json::Object(obj)
  @debug.assert_eq(obj.get("ok"), Some(false.to_json()))
}

///|
async test "media transcription with missing file returns 400" {
  let resp = handle_media_transcription(
    make_media_server_ref(),
    make_media_event(
      Post,
      "/api/media/audio/transcriptions",
      body="{\"audio_path\":\"/nonexistent/clacky-audio.mp3\"}",
    ),
  )
  @debug.assert_eq(resp.status_code.to_int(), 400)
  let j = media_response_json(resp)
  guard! j is Json::Object(obj)
  @debug.assert_eq(obj.get("ok"), Some(false.to_json()))
}

// ── Video Understanding ───────────────────────────────────────────

///|
async test "video understand with empty body returns 400" {
  let resp = handle_media_video_understand(
    make_media_server_ref(),
    make_media_event(Post, "/api/media/video/understand"),
  )
  @debug.assert_eq(resp.status_code.to_int(), 400)
  let j = media_response_json(resp)
  guard! j is Json::Object(obj)
  @debug.assert_eq(obj.get("ok"), Some(false.to_json()))
}

///|
async test "video understand with non-object JSON returns 400" {
  let resp = handle_media_video_understand(
    make_media_server_ref(),
    make_media_event(Post, "/api/media/video/understand", body="42"),
  )
  @debug.assert_eq(resp.status_code.to_int(), 400)
  let j = media_response_json(resp)
  guard! j is Json::Object(obj)
  @debug.assert_eq(obj.get("ok"), Some(false.to_json()))
}

///|
async test "video understand with invalid JSON returns 400" {
  let resp = handle_media_video_understand(
    make_media_server_ref(),
    make_media_event(Post, "/api/media/video/understand", body="not-json"),
  )
  @debug.assert_eq(resp.status_code.to_int(), 400)
  let j = media_response_json(resp)
  guard! j is Json::Object(obj)
  @debug.assert_eq(obj.get("ok"), Some(false.to_json()))
}

///|
async test "video understand with no model configured returns 500" {
  let resp = handle_media_video_understand(
    make_media_server_ref(),
    make_media_event(Post, "/api/media/video/understand", body="{}"),
  )
  @debug.assert_eq(resp.status_code.to_int(), 500)
  let j = media_response_json(resp)
  guard! j is Json::Object(obj)
  @debug.assert_eq(obj.get("ok"), Some(false.to_json()))
  let err = match obj.get("error") {
    Some(s) => @debug.to_string(s)
    None => ""
  }
  assert_true(err.contains("vision"))
}

///|
async test "video understand with video_path but no model returns 500" {
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
  guard! j is Json::Object(obj)
  @debug.assert_eq(obj.get("ok"), Some(false.to_json()))
}
