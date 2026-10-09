///| White-box contract tests for fix-14 (GET /api/media/types semantics):
/// five-modality configuration-state objects aligned with orig
/// api_media_types — {configured, model, base_url, source} with source
/// "custom"/"auto", or {configured:false, source:"off"}.

///|
fn mt_make_event() -> @crescent.Event {
  {
    req: @crescent.HttpRequest::HttpRequest(
      Get,
      "/api/media/types",
      Map([]),
      raw_body=b"",
    ),
    res: @crescent.HttpResponse::HttpResponse(status_code=OK),
    params: Map([]),
  }
}

///|
fn mt_server_ref(config : @config.AgentConfig) -> Ref[WebServer] {
  Ref(WebServer::new(config, None))
}

///|
fn mt_json(resp : @core.HttpResponse) -> Json {
  @json.parse(@utf8.decode(resp.raw_body)) catch {
    _ => Json::object(Map([]))
  }
}

///|
/// Assert one modality entry is exactly {configured:false, source:"off"}.
fn mt_assert_off(entry : Json) -> Unit raise {
  guard! entry is Json::Object(obj)
  @debug.assert_eq(obj.length(), 2)
  @debug.assert_eq(obj.get("configured"), Some(Json(false)))
  @debug.assert_eq(obj.get("source"), Some(Json("off")))
}

///|
test "media types: default config returns five modalities, all off" {
  let resp = handle_media_types_bridge(
    mt_server_ref(@config.AgentConfig::default()),
    mt_make_event(),
  )
  @debug.assert_eq(resp.status_code.to_int(), 200)
  guard! mt_json(resp) is Json::Object(obj)
  for kind in ["image", "video", "audio", "stt", "video_understanding"] {
    guard! obj.get(kind) is Some(entry)
    mt_assert_off(entry)
  }
}

///|
test "media types: explicit image model reports source custom" {
  let config = @config.AgentConfig::default()
  let img = @config.ModelConfig::new(
    "img-1", "key", "https://api.example.com/v1", "gpt-image-1",
  )
  img.media_type = Some("image")
  config.models = [img]
  let resp = handle_media_types_bridge(mt_server_ref(config), mt_make_event())
  @debug.assert_eq(resp.status_code.to_int(), 200)
  guard! mt_json(resp) is Json::Object(obj)
  guard! obj.get("image") is Some(Object(image))
  @debug.assert_eq(image.get("configured"), Some(Json(true)))
  @debug.assert_eq(image.get("model"), Some(Json("gpt-image-1")))
  @debug.assert_eq(
    image.get("base_url"),
    Some(Json("https://api.example.com/v1")),
  )
  @debug.assert_eq(image.get("source"), Some(Json("custom")))
  // no sensitive fields leak
  assert_true(!image.contains("api_key"))
  // other modalities stay off
  for kind in ["video", "audio", "stt", "video_understanding"] {
    guard! obj.get(kind) is Some(entry)
    mt_assert_off(entry)
  }
}

///|
test "media types: derivable provider reports source auto" {
  let config = @config.AgentConfig::default()
  config.models = [
    @config.ModelConfig::new(
      "main", "key", "https://api.openai.com/v1", "gpt-4o",
    ),
  ]
  config.current_model_id = Some("main")
  let resp = handle_media_types_bridge(mt_server_ref(config), mt_make_event())
  @debug.assert_eq(resp.status_code.to_int(), 200)
  guard! mt_json(resp) is Json::Object(obj)
  // openai preset derives image (gpt-4o) and audio (tts-1)
  guard! obj.get("image") is Some(Object(image))
  @debug.assert_eq(image.get("configured"), Some(Json(true)))
  @debug.assert_eq(image.get("source"), Some(Json("auto")))
  @debug.assert_eq(image.get("model"), Some(Json("gpt-4o")))
  @debug.assert_eq(
    image.get("base_url"),
    Some(Json("https://api.openai.com/v1")),
  )
  guard! obj.get("audio") is Some(Object(audio))
  @debug.assert_eq(audio.get("configured"), Some(Json(true)))
  @debug.assert_eq(audio.get("source"), Some(Json("auto")))
  @debug.assert_eq(audio.get("model"), Some(Json("tts-1")))
  // openai preset derives nothing for the remaining modalities
  for kind in ["video", "stt", "video_understanding"] {
    guard! obj.get(kind) is Some(entry)
    mt_assert_off(entry)
  }
}
