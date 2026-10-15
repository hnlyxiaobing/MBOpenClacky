///| White-box tests for Version and Restart API handlers.

///|
fn make_version_event(
  http_method : @crescent.HttpMethod,
  url : String,
) -> @crescent.Event {
  {
    req: @crescent.HttpRequest::HttpRequest(
      http_method,
      url,
      Map([]),
      raw_body=b"",
    ),
    res: @crescent.HttpResponse::HttpResponse(status_code=OK),
    params: Map([]),
  }
}

///|
fn make_version_server_ref() -> Ref[WebServer] {
  Ref(WebServer::new(@config.AgentConfig::default(), None))
}

///|
fn version_response_json(resp : @core.HttpResponse) -> Json {
  @json.parse(@utf8.decode(resp.raw_body)) catch {
    _ => Json::object(Map([]))
  }
}

// ── Parsing ───────────────────────────────────────────────────────

///|
test "parse latest version strips leading v" {
  let body = "{\"tag_name\":\"v0.2.0\"}"
  let result = parse_latest_version(body)
  @debug.assert_eq(result, Ok("0.2.0"))
}

///|
test "parse latest version keeps version without v" {
  let body = "{\"tag_name\":\"0.2.0\"}"
  let result = parse_latest_version(body)
  @debug.assert_eq(result, Ok("0.2.0"))
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
async test "version upgrade returns current version" {
  let server_ref = make_version_server_ref()
  let resp = handle_version_upgrade(
    server_ref,
    make_version_event(Post, "/api/version/upgrade"),
  )
  @debug.assert_eq(resp.status_code.to_int(), 200)
  let j = version_response_json(resp)
  guard! j is Json::Object(obj)
  @debug.assert_eq(obj.get("current"), Some(Json(VERSION)))
  assert_true(obj.contains("message"))
}

///|
test "restart returns ok message" {
  let server_ref = make_version_server_ref()
  let resp = handle_restart(
    server_ref,
    make_version_event(Post, "/api/restart"),
  )
  @debug.assert_eq(resp.status_code.to_int(), 200)
  let j = version_response_json(resp)
  guard! j is Json::Object(obj)
  @debug.assert_eq(obj.get("ok"), Some(Json(true)))
  assert_true(obj.contains("message"))
}

///|
/// `/health` and `/api/info` are the two endpoints deployment tooling reads to
/// learn which build is serving, so they must report the same constant as
/// `/api/version`. Both used to hardcode `0.1.0` while the rest of the repo
/// was at 0.3.0, and the `repo_stats.sh` version guard only checks four
/// constants, so nothing caught it.
test "health and info report the canonical version" {
  let health = @json.parse(health_body())
  guard! health is Json::Object(h)
  @debug.assert_eq(h.get("status"), Some(Json("ok")))
  @debug.assert_eq(h.get("version"), Some(Json(VERSION)))

  let resp = handle_info(
    make_version_server_ref(),
    make_version_event(Get, "/api/info"),
  )
  @debug.assert_eq(resp.status_code.to_int(), 200)
  let j = version_response_json(resp)
  guard! j is Json::Object(obj)
  @debug.assert_eq(obj.get("version"), Some(Json(VERSION)))
}

///|
/// `uptime_seconds` is derived from a millisecond clock, so the field name is
/// only true after conversion. A server started five seconds ago must read as
/// ~5, not ~5000. Int64 serialises as a JSON string.
test "info uptime is reported in seconds" {
  let server_ref = make_version_server_ref()
  server_ref.val.start_time = @env.now().reinterpret_as_int64() - 5000L
  let j = version_response_json(
    handle_info(server_ref, make_version_event(Get, "/api/info")),
  )
  guard! j is Json::Object(obj)
  // Integer division of a 5000 ms delta cannot round below 5 within a test
  // run, and Int64 serialises as a JSON string, so an exact value is stable.
  @debug.assert_eq(obj.get("uptime_seconds"), Some(Json(5L)))
}
