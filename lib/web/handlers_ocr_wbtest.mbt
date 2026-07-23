///| White-box tests for OCR Config API handlers.

///|
fn make_ocr_event(
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
fn make_ocr_server_ref() -> Ref[WebServer] {
  Ref(WebServer::new(@config.AgentConfig::default(), None))
}

///|
fn ocr_response_json(resp : @core.HttpResponse) -> Json {
  @json.parse(@utf8.decode(resp.raw_body)) catch {
    _ => Json::object(Map([]))
  }
}

// ── Config Update ─────────────────────────────────────────────────

///|
test "ocr config update rejects invalid json" {
  let server_ref = make_ocr_server_ref()
  let event = make_ocr_event(Patch, "/api/config/ocr", body="not-json")
  let resp = handle_config_ocr_update(server_ref, event)
  @debug.assert_eq(resp.status_code.to_int(), 400)
}

///|
test "ocr config update switches source off" {
  let server_ref = make_ocr_server_ref()
  let event = make_ocr_event(
    Patch,
    "/api/config/ocr",
    body="{\"source\":\"off\"}",
  )
  let resp = handle_config_ocr_update(server_ref, event)
  @debug.assert_eq(resp.status_code.to_int(), 200)
  let j = ocr_response_json(resp)
  guard j is Object(obj)
  @debug.assert_eq(obj.get("ok"), Some(true.to_json()))
  @debug.assert_eq(obj.get("source"), Some("off".to_json()))
}

///|
test "ocr config update custom requires fields" {
  let server_ref = make_ocr_server_ref()
  let event = make_ocr_event(
    Patch,
    "/api/config/ocr",
    body="{\"source\":\"custom\"}",
  )
  let resp = handle_config_ocr_update(server_ref, event)
  @debug.assert_eq(resp.status_code.to_int(), 400)
  let j = ocr_response_json(resp)
  guard j is Object(obj)
  @debug.assert_eq(obj.get("ok"), Some(false.to_json()))
}

///|
test "ocr config update custom stores model" {
  let server_ref = make_ocr_server_ref()
  let body = "{\"source\":\"custom\",\"base_url\":\"https://api.example.com\",\"api_key\":\"sk-test\",\"model\":\"gpt-4o\"}"
  let event = make_ocr_event(Patch, "/api/config/ocr", body~)
  let resp = handle_config_ocr_update(server_ref, event)
  @debug.assert_eq(resp.status_code.to_int(), 200)
  let j = ocr_response_json(resp)
  guard j is Object(obj)
  @debug.assert_eq(obj.get("ok"), Some(true.to_json()))
  @debug.assert_eq(obj.get("source"), Some("custom".to_json()))
  @debug.assert_eq(obj.get("model"), Some("gpt-4o".to_json()))
  // Verify the model is registered in the config.
  let ocr_model = server_ref.val.config.find_model_by_type("ocr")
  assert_true(ocr_model is Some(_))
}

// ── Config Test ───────────────────────────────────────────────────

///|
test "ocr config test fails without model" {
  let server_ref = make_ocr_server_ref()
  let event = make_ocr_event(Post, "/api/config/ocr/test")
  let resp = handle_config_ocr_test(server_ref, event)
  @debug.assert_eq(resp.status_code.to_int(), 500)
  let j = ocr_response_json(resp)
  guard j is Object(obj)
  @debug.assert_eq(obj.get("ok"), Some(false.to_json()))
}

// ── Internal OCR ──────────────────────────────────────────────────

///|
test "internal ocr requires data_url or path" {
  let server_ref = make_ocr_server_ref()
  let event = make_ocr_event(Post, "/api/internal/ocr-image", body="{}")
  let resp = handle_internal_ocr_image(server_ref, event)
  @debug.assert_eq(resp.status_code.to_int(), 400)
}

///|
test "internal ocr fails without configured model" {
  let server_ref = make_ocr_server_ref()
  let event = make_ocr_event(
    Post,
    "/api/internal/ocr-image",
    body="{\"data_url\":\"data:image/png;base64,abc\"}",
  )
  let resp = handle_internal_ocr_image(server_ref, event)
  @debug.assert_eq(resp.status_code.to_int(), 500)
  let j = ocr_response_json(resp)
  guard j is Object(obj)
  @debug.assert_eq(obj.get("ok"), Some(false.to_json()))
}
