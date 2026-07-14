///| White-box tests for Media API handlers (stub responses).

///|
fn make_media_event(
  http_method : @crescent.HttpMethod,
  url : String,
) -> @crescent.Event {
  {
    req: @crescent.HttpRequest::HttpRequest(http_method, url, {}, raw_body=b""),
    res: @crescent.HttpResponse::HttpResponse(status_code=OK),
    params: {},
  }
}

///|
fn make_media_server_ref() -> Ref[WebServer] {
  Ref(WebServer::new(@config.AgentConfig::default(), None))
}

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

///|
test "media video understand returns 501 stub" {
  let resp = handle_media_video_understand(
    make_media_server_ref(),
    make_media_event(Post, "/api/media/video/understand"),
  )
  @debug.assert_eq(resp.status_code.to_int(), 501)
}
