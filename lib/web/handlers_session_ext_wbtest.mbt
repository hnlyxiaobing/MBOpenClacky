///| White-box tests for PATCH /api/sessions/:id/working_dir (G10, P1).

///| Session JSON is persisted under USERPROFILE -> "_build" for hermetic runs.

///|
fn wd_make_event(
  http_method : @crescent.HttpMethod,
  url : String,
  body? : String = "",
  params? : Array[(String, String)] = [],
) -> @crescent.Event {
  let pmap : Map[String, StringView] = {}
  for t in params {
    let (k, v) = t
    pmap[k] = v.to_string_view()
  }
  {
    req: @crescent.HttpRequest::HttpRequest(
      http_method,
      url,
      {},
      raw_body=@utf8.encode(body),
    ),
    res: @crescent.HttpResponse::HttpResponse(status_code=OK),
    params: pmap,
  }
}

///|
fn wd_make_server_ref() -> Ref[WebServer] {
  Ref(WebServer::new(@config.AgentConfig::default(), None))
}

///|
fn wd_response_json(resp : @core.HttpResponse) -> Json {
  @json.parse(@utf8.decode(resp.raw_body)) catch {
    _ => Json::object({})
  }
}

///|
/// Redirect USERPROFILE to a temp dir so session files are hermetic.
fn wd_push_profile() -> String? {
  let old = @sys.get_env_var("USERPROFILE")
  @sys.set_env_var("USERPROFILE", "_build")
  old
}

///|
fn wd_pop_profile(old : String?) -> Unit {
  match old {
    Some(v) => @sys.set_env_var("USERPROFILE", v)
    None => @sys.set_env_var("USERPROFILE", "")
  }
}

///|
/// Build a minimal persisted SessionData for tests.
fn wd_make_session(id : String, wd : String) -> @agent.SessionData {
  @agent.SessionData::{
    session_id: id,
    name: "wd-test-session",
    messages: [],
    stats: {
      total_iterations: 0,
      total_cost_usd: 0.0,
      total_tasks: 0,
      cost_source: "",
      cache_creation_input_tokens: 0,
      cache_read_input_tokens: 0,
      total_requests: 0,
      cache_hit_requests: 0,
    },
    working_dir: wd,
    created_at: "2026-01-01T00:00:00Z",
    source: "manual",
    reasoning_effort: None,
    model_name: None,
    channel_info: None,
    latest_latency_ms: None,
    latest_ttft_ms: None,
    time_machine: None,
    pending_error_rollback: false,
    model_base_url: "",
    last_status: "",
    last_error: "",
    forked_from: None,
    chunk_count: 0,
  }
}

///|
test "working_dir update accepts relative path and persists" {
  let old = wd_push_profile()
  let id = "wd_rel_" + @agent.current_timestamp_ms()
  @agent.save_session(wd_make_session(id, ".")) catch {
    _ => ()
  }
  let resp = handle_update_working_dir(
    wd_make_server_ref(),
    wd_make_event(
      Patch,
      "/api/sessions/" + id + "/working_dir",
      body="{\"working_dir\":\"sub/dir\"}",
      params=[("id", id)],
    ),
  )
  @debug.assert_eq(resp.status_code.to_int(), 200)
  let j = wd_response_json(resp)
  guard j is Object(obj)
  @debug.assert_eq(obj.get("working_dir"), Some("sub/dir".to_json()))
  match @agent.load_session(id) {
    Some(d) => @debug.assert_eq(d.working_dir, "sub/dir")
    None => panic()
  }
  @agent.delete_session(id)
  wd_pop_profile(old)
}

///|
test "working_dir update rejects path traversal" {
  let old = wd_push_profile()
  let id = "wd_trav_" + @agent.current_timestamp_ms()
  @agent.save_session(wd_make_session(id, ".")) catch {
    _ => ()
  }
  let resp = handle_update_working_dir(
    wd_make_server_ref(),
    wd_make_event(
      Patch,
      "/api/sessions/" + id + "/working_dir",
      body="{\"working_dir\":\"../evil\"}",
      params=[("id", id)],
    ),
  )
  @debug.assert_eq(resp.status_code.to_int(), 400)
  @agent.delete_session(id)
  wd_pop_profile(old)
}

///|
test "working_dir update rejects absolute path without configured dir" {
  let old = wd_push_profile()
  let id = "wd_absnone_" + @agent.current_timestamp_ms()
  @agent.save_session(wd_make_session(id, ".")) catch {
    _ => ()
  }
  // default config has default_working_dir = None
  let resp = handle_update_working_dir(
    wd_make_server_ref(),
    wd_make_event(
      Patch,
      "/api/sessions/" + id + "/working_dir",
      body="{\"working_dir\":\"/etc/passwd\"}",
      params=[("id", id)],
    ),
  )
  @debug.assert_eq(resp.status_code.to_int(), 400)
  @agent.delete_session(id)
  wd_pop_profile(old)
}

///|
test "working_dir update accepts absolute path within configured dir" {
  let old = wd_push_profile()
  let id = "wd_absok_" + @agent.current_timestamp_ms()
  @agent.save_session(wd_make_session(id, ".")) catch {
    _ => ()
  }
  let cfg = @config.AgentConfig::default()
  cfg.default_working_dir = Some("/home/user/project")
  let server_ref = Ref(WebServer::new(cfg, None))
  let resp = handle_update_working_dir(
    server_ref,
    wd_make_event(
      Patch,
      "/api/sessions/" + id + "/working_dir",
      body="{\"working_dir\":\"/home/user/project/sub\"}",
      params=[("id", id)],
    ),
  )
  @debug.assert_eq(resp.status_code.to_int(), 200)
  @agent.delete_session(id)
  wd_pop_profile(old)
}

///|
test "working_dir update returns 404 for missing session" {
  let old = wd_push_profile()
  let resp = handle_update_working_dir(
    wd_make_server_ref(),
    wd_make_event(
      Patch,
      "/api/sessions/does-not-exist/working_dir",
      body="{\"working_dir\":\"sub\"}",
      params=[("id", "does-not-exist")],
    ),
  )
  @debug.assert_eq(resp.status_code.to_int(), 404)
  wd_pop_profile(old)
}

///|
test "working_dir update rejects missing working_dir field" {
  let old = wd_push_profile()
  let id = "wd_missing_" + @agent.current_timestamp_ms()
  @agent.save_session(wd_make_session(id, ".")) catch {
    _ => ()
  }
  let resp = handle_update_working_dir(
    wd_make_server_ref(),
    wd_make_event(
      Patch,
      "/api/sessions/" + id + "/working_dir",
      body="{\"name\":\"x\"}",
      params=[("id", id)],
    ),
  )
  @debug.assert_eq(resp.status_code.to_int(), 400)
  @agent.delete_session(id)
  wd_pop_profile(old)
}
