///| White-box tests for Version and Restart API handlers.

///|
fn make_version_event(
  method : @crescent.HttpMethod,
  url : String,
) -> @crescent.Event {
  {
    req: @crescent.HttpRequest::http_request(method, url, {}, raw_body=b""),
    res: @crescent.HttpResponse::http_response(status_code=OK),
    params: {},
  }
}

///|
fn make_version_server_ref() -> Ref[WebServer] {
  Ref(WebServer::new(@config.AgentConfig::default(), None))
}

///|
fn version_response_json(resp : @core.HttpResponse) -> Json {
  @json.parse(@utf8.decode(resp.raw_body)) catch {
    _ => Json::object({})
  }
}

// ── Parsing ───────────────────────────────────────────────────────

///|
test "parse latest version strips leading v" {
  let body = "{\"tag_name\":\"v0.2.0\"}"
  let result = parse_latest_version(body)
  assert_eq(result, Ok("0.2.0"))
}

///|
test "parse latest version keeps version without v" {
  let body = "{\"tag_name\":\"0.2.0\"}"
  let result = parse_latest_version(body)
  assert_eq(result, Ok("0.2.0"))
}

///|
test "parse latest version returns error for missing tag" {
  let body = "{\"name\":\"release\"}"
  let result = parse_latest_version(body)
  assert_true(result is Err(_))
}

///|
test "version is newer when major increases" {
  assert_true(version_is_newer("0.1.0", "1.0.0"))
}

///|
test "version is newer when minor increases" {
  assert_true(version_is_newer("0.1.0", "0.2.0"))
}

///|
test "version is newer when patch increases" {
  assert_true(version_is_newer("0.1.0", "0.1.1"))
}

///|
test "version is not newer when equal" {
  assert_true(!version_is_newer("0.1.0", "0.1.0"))
}

///|
test "version is not newer when older" {
  assert_true(!version_is_newer("0.2.0", "0.1.0"))
}

// ── Handlers ──────────────────────────────────────────────────────

///|
test "version upgrade returns current version" {
  let server_ref = make_version_server_ref()
  let resp = handle_version_upgrade(
    server_ref,
    make_version_event(Post, "/api/version/upgrade"),
  )
  assert_eq(resp.status_code.to_int(), 200)
  let j = version_response_json(resp)
  guard j is Object(obj)
  assert_eq(obj.get("current"), Some(VERSION.to_json()))
  assert_true(obj.contains("message"))
}

///|
test "restart returns ok message" {
  let server_ref = make_version_server_ref()
  let resp = handle_restart(
    server_ref,
    make_version_event(Post, "/api/restart"),
  )
  assert_eq(resp.status_code.to_int(), 200)
  let j = version_response_json(resp)
  guard j is Object(obj)
  assert_eq(obj.get("ok"), Some(true.to_json()))
  assert_true(obj.contains("message"))
}
