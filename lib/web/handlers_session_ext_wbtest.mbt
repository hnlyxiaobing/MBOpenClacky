///| White-box tests for PATCH /api/sessions/:id/working_dir (G10, P1).

///| Session JSON is persisted under USERPROFILE -> "_build" for hermetic runs.

///|
fn wd_make_event(
  http_method : @crescent.HttpMethod,
  url : String,
  body? : String = "",
  params? : Array[(String, String)] = [],
) -> @crescent.Event {
  let pmap : Map[String, StringView] = Map([])
  for t in params {
    let (k, v) = t
    pmap[k] = v.to_string_view()
  }
  {
    req: @crescent.HttpRequest::HttpRequest(
      http_method,
      url,
      Map([]),
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
    _ => Json::object(Map([]))
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
    agent_profile: "general",
    sub_model: None,
  }
}

///|
test "working_dir update accepts relative path and persists" {
  let old = wd_push_profile()
  let id = "wd_rel_" + @agent.current_time_ms().to_string()
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
  let id = "wd_trav_" + @agent.current_time_ms().to_string()
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
  let id = "wd_absnone_" + @agent.current_time_ms().to_string()
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
  let id = "wd_absok_" + @agent.current_time_ms().to_string()
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
  let id = "wd_missing_" + @agent.current_time_ms().to_string()
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

// ── latest_latency object shape (web-ui fix-03) ──────────────────────────────

///|
test "SessionLatency::from_session_data builds object or none" {
  let base = wd_make_session("lat_test", ".")
  // No latency data -> None (frontend hides the signal).
  @debug.assert_eq(SessionLatency::from_session_data(base), None)
  // ttft + duration -> object with both fields.
  let with_lat = @agent.SessionData::{
    ..base,
    latest_ttft_ms: Some(80),
    latest_latency_ms: Some(350),
  }
  @debug.assert_eq(
    SessionLatency::from_session_data(with_lat),
    Some({ ttft_ms: Some(80), duration_ms: Some(350) }),
  )
  // duration only -> still an object (ttft null, signal hidden by frontend).
  let dur_only = @agent.SessionData::{ ..base, latest_latency_ms: Some(120) }
  @debug.assert_eq(
    SessionLatency::from_session_data(dur_only),
    Some({ ttft_ms: None, duration_ms: Some(120) }),
  )
}

///|
test "SessionSummary json emits latest_latency object" {
  let summary = SessionSummary::{
    id: "s_lat",
    name: "lat",
    working_dir: ".",
    status: "idle",
    created_at: "2026-07-24T12:00:00+08:00",
    updated_at: "2026-07-24T12:00:00+08:00",
    total_tasks: 0,
    total_cost: 0.0,
    cost_source: "estimated",
    error: "",
    model: Some("kimi-k2"),
    source: "manual",
    latest_latency: Some({ ttft_ms: Some(80), duration_ms: Some(350) }),
    pinned: false,
    agent_profile: "general",
    sub_model: None,
    sub_model_options: [],
    reasoning_effort: None,
  }
  match ToJson::to_json(summary) {
    Object(map) =>
      match map.get("latest_latency") {
        Some(Object(lat)) => {
          @debug.assert_eq(lat.get("ttft_ms"), Some((80).to_json()))
          @debug.assert_eq(lat.get("duration_ms"), Some((350).to_json()))
        }
        _ => panic()
      }
    _ => panic()
  }
  let no_lat = SessionSummary::{ ..summary, latest_latency: None }
  match ToJson::to_json(no_lat) {
    Object(map) =>
      @debug.assert_eq(map.get("latest_latency"), Some(Json::null()))
    _ => panic()
  }
}

// ── GET /api/sessions/:id wrapper (web-ui fix-04) ────────────────────────────

///|
test "get session wraps response in session key" {
  let old = wd_push_profile()
  let id = "wrap_" + @agent.current_time_ms().to_string()
  @agent.save_session(wd_make_session(id, ".")) catch {
    _ => ()
  }
  // Disk-hit branch.
  let resp = handle_get_session(
    wd_make_server_ref(),
    wd_make_event(Get, "/api/sessions/" + id, params=[("id", id)]),
  )
  @debug.assert_eq(resp.status_code.to_int(), 200)
  match wd_response_json(resp) {
    Object(top) =>
      match top.get("session") {
        Some(Object(s)) =>
          @debug.assert_eq(s.get("session_id"), Some(id.to_json()))
        _ => panic()
      }
    _ => panic()
  }
  @agent.delete_session(id)
  // In-memory fallback branch (no disk file, agent in active_agents).
  let mem_id = "wrapmem_" + @agent.current_time_ms().to_string()
  let server_ref = wd_make_server_ref()
  let client = @client.Client::new(
    "k",
    "https://api.test.com",
    "m",
    @config.OpenAICompletions,
  )
  let agent = @agent.Agent::new(
    mem_id,
    "mem-session",
    ".",
    client,
    @config.AgentConfig::default(),
  )
  server_ref.val.active_agents[mem_id] = agent
  let resp2 = handle_get_session(
    server_ref,
    wd_make_event(Get, "/api/sessions/" + mem_id, params=[("id", mem_id)]),
  )
  @debug.assert_eq(resp2.status_code.to_int(), 200)
  match wd_response_json(resp2) {
    Object(top) =>
      match top.get("session") {
        Some(Object(s)) =>
          @debug.assert_eq(s.get("session_id"), Some(mem_id.to_json()))
        _ => panic()
      }
    _ => panic()
  }
  wd_pop_profile(old)
}
