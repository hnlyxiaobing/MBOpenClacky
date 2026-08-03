///| White-box tests for Onboarding API handlers.

///|
/// Helper to build a crescent Event for handler tests.
fn make_event(
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
/// Helper to decode a JSON response body; returns an empty object on failure.
fn response_json(resp : @core.HttpResponse) -> Json {
  @json.parse(@utf8.decode(resp.raw_body)) catch {
    _ => Json::object(Map([]))
  }
}

///|
fn make_server_ref() -> Ref[WebServer] {
  Ref(WebServer::new(@config.AgentConfig::default(), None))
}

// ── Device Start ──────────────────────────────────────────────────

///|
test "onboard device start returns device and user codes" {
  let server_ref = make_server_ref()
  let event = make_event(Post, "/api/onboard/device/start")
  let resp = handle_onboard_device_start(server_ref, event)
  @debug.assert_eq(resp.status_code.to_int(), 200)
  let j = response_json(resp)
  guard! j is Json::Object(obj)
  @debug.assert_eq(obj.get("ok"), Some(true.to_json()))
  assert_true(obj.contains("device_code"))
  assert_true(obj.contains("user_code"))
  assert_true(obj.contains("verification_uri"))
  assert_true(obj.contains("verification_uri_complete"))
  @debug.assert_eq(obj.get("interval"), Some((5).to_json()))
}

// ── Device Poll ───────────────────────────────────────────────────

///|
test "onboard device poll returns pending for a registered code" {
  let server_ref = make_server_ref()
  let now_ms = @agent.current_time_ms()
  let sess = server_ref.val.device_auth_store.start_device_flow(
    now_ms, "wbtest-dev",
  )
  let event = make_event(
    Get,
    "/api/onboard/device/poll?device_code=" + sess.device_code,
  )
  let resp = handle_onboard_device_poll(server_ref, event)
  @debug.assert_eq(resp.status_code.to_int(), 200)
  let j = response_json(resp)
  guard! j is Json::Object(obj)
  @debug.assert_eq(obj.get("ok"), Some(true.to_json()))
  @debug.assert_eq(obj.get("status"), Some("pending".to_json()))
}

///|
test "onboard device poll returns approved for approved prefix" {
  let server_ref = make_server_ref()
  let event = make_event(
    Get,
    "/api/onboard/device/poll?device_code=DEV-APPROVED-123",
  )
  let resp = handle_onboard_device_poll(server_ref, event)
  @debug.assert_eq(resp.status_code.to_int(), 200)
  let j = response_json(resp)
  guard! j is Json::Object(obj)
  @debug.assert_eq(obj.get("ok"), Some(true.to_json()))
  @debug.assert_eq(obj.get("status"), Some("approved".to_json()))
  // Note: the approved response returns ok/status/device_token; default_model is
  // intentionally not asserted because it is not part of the current contract.
}

///|
test "onboard device poll requires device_code" {
  let server_ref = make_server_ref()
  let event = make_event(Get, "/api/onboard/device/poll")
  let resp = handle_onboard_device_poll(server_ref, event)
  @debug.assert_eq(resp.status_code.to_int(), 400)
}

// ── Complete ──────────────────────────────────────────────────────

///|
test "onboard complete fails without configured model" {
  let server_ref = make_server_ref()
  let event = make_event(Post, "/api/onboard/complete")
  let resp = handle_onboard_complete(server_ref, event)
  @debug.assert_eq(resp.status_code.to_int(), 500)
  let j = response_json(resp)
  guard! j is Json::Object(obj)
  @debug.assert_eq(obj.get("error"), Some("No model configured".to_json()))
}

// ── Skip Soul ─────────────────────────────────────────────────────

///|
test "onboard skip soul returns ok" {
  let old_userprofile = @sys.get_env_var("USERPROFILE")
  // Use an existing base directory so nested dir creation succeeds.
  let test_home = "_build"
  @sys.set_env_var("USERPROFILE", test_home)
  let server_ref = make_server_ref()
  let event = make_event(
    Post,
    "/api/onboard/skip-soul",
    body="{\"lang\":\"en\"}",
  )
  let resp = handle_onboard_skip_soul(server_ref, event)
  // Restore original USERPROFILE.
  match old_userprofile {
    Some(v) => @sys.set_env_var("USERPROFILE", v)
    None => @sys.set_env_var("USERPROFILE", "")
  }
  @debug.assert_eq(resp.status_code.to_int(), 200)
  let j = response_json(resp)
  guard! j is Json::Object(obj)
  @debug.assert_eq(obj.get("ok"), Some(true.to_json()))
  assert_true(obj.contains("path"))
  // Cleanup created config dir.
  @fs.remove_dir("_build/.mbopenclacky") catch {
    _ => ()
  }
}
