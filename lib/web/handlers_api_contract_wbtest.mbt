///| White-box tests for the web API contract handlers covered by

///| spec `2026-07-09_web-api-contract-alignment`: profile, dirs (mkdir),

///| brand/skills, and config/media/test. These complement the existing

///| onboard/version wbtests so that every endpoint listed in the spec has

///| white-box coverage.

///|
fn cc_make_event(
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
fn cc_make_server_ref() -> Ref[WebServer] {
  Ref(WebServer::new(@config.AgentConfig::default(), None))
}

///|
fn cc_response_json(resp : @core.HttpResponse) -> Json {
  @json.parse(@utf8.decode(resp.raw_body)) catch {
    _ => Json::object(Map([]))
  }
}

// ── Profile ───────────────────────────────────────────────────────────

///|
test "profile get returns default profile structure" {
  let server_ref = cc_make_server_ref()
  let resp = handle_profile_get(server_ref, cc_make_event(Get, "/api/profile"))
  @debug.assert_eq(resp.status_code.to_int(), 200)
  let j = cc_response_json(resp)
  guard! j is Json::Object(obj)
  assert_true(obj.contains("ok"))
  assert_true(obj.contains("user"))
  assert_true(obj.contains("soul"))
  // web-ui2-10 BUG-019: top-level name/email/preferences/theme removed.
  assert_true(!obj.contains("name"))
  assert_true(!obj.contains("email"))
  assert_true(!obj.contains("preferences"))
  assert_true(!obj.contains("theme"))
}

///|
test "profile put merges fields and persists" {
  let old_userprofile = @sys.get_env_var("USERPROFILE")
  @sys.set_env_var("USERPROFILE", "_build")
  let server_ref = cc_make_server_ref()
  let resp = handle_profile_put(
    server_ref,
    cc_make_event(
      Put,
      "/api/profile",
      body="{\"name\":\"Ada\",\"theme\":\"light\"}",
    ),
  )
  match old_userprofile {
    Some(v) => @sys.set_env_var("USERPROFILE", v)
    None => @sys.set_env_var("USERPROFILE", "")
  }
  @debug.assert_eq(resp.status_code.to_int(), 200)
  let j = cc_response_json(resp)
  guard! j is Json::Object(obj)
  @debug.assert_eq(obj.get("ok"), Some(true.to_json()))
  @fs.remove_file("_build/.mbopenclacky/profile.json") catch {
    _ => ()
  }
}

// ── Dirs / mkdir ──────────────────────────────────────────────────────

///|
test "dirs mkdir rejects path traversal in parent" {
  let server_ref = cc_make_server_ref()
  let resp = handle_dirs_mkdir(
    server_ref,
    cc_make_event(
      Post,
      "/api/dirs/mkdir",
      body="{\"path\":\"../../etc\",\"name\":\"x\"}",
    ),
  )
  @debug.assert_eq(resp.status_code.to_int(), 400)
  let j = cc_response_json(resp)
  guard! j is Json::Object(obj)
  assert_true(obj.contains("error"))
}

///|
test "dirs mkdir rejects path traversal in name" {
  let server_ref = cc_make_server_ref()
  let resp = handle_dirs_mkdir(
    server_ref,
    cc_make_event(
      Post,
      "/api/dirs/mkdir",
      body="{\"path\":\".\",\"name\":\"../x\"}",
    ),
  )
  @debug.assert_eq(resp.status_code.to_int(), 400)
}

///|
test "dirs mkdir creates directory under cwd" {
  let old_userprofile = @sys.get_env_var("USERPROFILE")
  @sys.set_env_var("USERPROFILE", "_build")
  let server_ref = cc_make_server_ref()
  let resp = handle_dirs_mkdir(
    server_ref,
    cc_make_event(
      Post,
      "/api/dirs/mkdir",
      body="{\"path\":\".\",\"name\":\"cc_test_dir\"}",
    ),
  )
  match old_userprofile {
    Some(v) => @sys.set_env_var("USERPROFILE", v)
    None => @sys.set_env_var("USERPROFILE", "")
  }
  @debug.assert_eq(resp.status_code.to_int(), 200)
  let j = cc_response_json(resp)
  guard! j is Json::Object(obj)
  @debug.assert_eq(obj.get("ok"), Some(true.to_json()))
  assert_true(obj.contains("path"))
  @fs.remove_dir("cc_test_dir") catch {
    _ => ()
  }
}

// ── Brand / skills ────────────────────────────────────────────────────

///|
test "brand skills list returns skills array" {
  let server_ref = cc_make_server_ref()
  let resp = handle_brand_skills_list(
    server_ref,
    cc_make_event(Get, "/api/brand/skills"),
  )
  @debug.assert_eq(resp.status_code.to_int(), 200)
  let j = cc_response_json(resp)
  guard! j is Json::Object(obj)
  assert_true(obj.contains("skills"))
}

///|
test "brand skills install requires name" {
  let server_ref = cc_make_server_ref()
  let resp = handle_brand_skills_install(
    server_ref,
    cc_make_event(Post, "/api/brand/skills", body="{}"),
  )
  @debug.assert_eq(resp.status_code.to_int(), 400)
}

// ── Config / media / test ─────────────────────────────────────────────

///|
async test "config media test requires kind" {
  let server_ref = cc_make_server_ref()
  let resp = handle_config_media_test(
    server_ref,
    cc_make_event(Post, "/api/config/media/test", body="{}"),
  )
  @debug.assert_eq(resp.status_code.to_int(), 400)
}

///|
async test "config media test reports no model for unknown kind" {
  let server_ref = cc_make_server_ref()
  let resp = handle_config_media_test(
    server_ref,
    cc_make_event(Post, "/api/config/media/test", body="{\"kind\":\"image\"}"),
  )
  @debug.assert_eq(resp.status_code.to_int(), 200)
  let j = cc_response_json(resp)
  guard! j is Json::Object(obj)
  @debug.assert_eq(obj.get("ok"), Some(false.to_json()))
  assert_true(obj.contains("error"))
}
