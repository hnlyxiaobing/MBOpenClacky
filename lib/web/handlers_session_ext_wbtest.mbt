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
    error_code: None,
    top_up_url: None,
    raw_message: None,
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
    model_id: None,
    card_model: None,
    channel_info: None,
    error_code: None,
    top_up_url: None,
    raw_message: None,
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
        Some(Object(s)) => {
          @debug.assert_eq(s.get("id"), Some(id.to_json()))
          assert_false(s.contains("session_id"))
          assert_false(s.contains("messages"))
        }
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
        Some(Object(s)) => {
          @debug.assert_eq(s.get("id"), Some(mem_id.to_json()))
          assert_false(s.contains("session_id"))
          assert_false(s.contains("messages"))
        }
        _ => panic()
      }
    _ => panic()
  }
  wd_pop_profile(old)
}

///|
test "SessionSummary json emits fix-09 fields" {
  let summary = SessionSummary::{
    id: "s_fix09",
    name: "fix09",
    working_dir: ".",
    status: "error",
    created_at: "2026-07-24T12:00:00+08:00",
    updated_at: "2026-07-24T12:00:00+08:00",
    total_tasks: 1,
    total_cost: 0.05,
    cost_source: "estimated",
    error: "Out of credits",
    model: Some("claude-3-5-sonnet"),
    source: "manual",
    latest_latency: None,
    pinned: false,
    agent_profile: "general",
    sub_model: None,
    sub_model_options: [],
    reasoning_effort: None,
    model_id: Some("claude-3-5-sonnet"),
    card_model: Some("claude-3-5-sonnet"),
    channel_info: Some(@agent.ChannelInfo::{
      platform: "telegram",
      channel_id: "ch123",
      user_id: "u456",
      webhook_url: "",
    }),
    error_code: Some("insufficient_credit"),
    top_up_url: Some("https://console.anthropic.com/settings/billing"),
    raw_message: Some("Your credit balance is too low"),
  }
  match ToJson::to_json(summary) {
    Object(map) => {
      @debug.assert_eq(map.get("model_id"), Some("claude-3-5-sonnet".to_json()))
      @debug.assert_eq(
        map.get("card_model"),
        Some("claude-3-5-sonnet".to_json()),
      )
      @debug.assert_eq(
        map.get("error_code"),
        Some("insufficient_credit".to_json()),
      )
      @debug.assert_eq(
        map.get("top_up_url"),
        Some("https://console.anthropic.com/settings/billing".to_json()),
      )
      @debug.assert_eq(
        map.get("raw_message"),
        Some("Your credit balance is too low".to_json()),
      )
      match map.get("channel_info") {
        Some(Object(ci)) => {
          @debug.assert_eq(ci.get("platform"), Some("telegram".to_json()))
          @debug.assert_eq(ci.get("channel_id"), Some("ch123".to_json()))
        }
        _ => panic()
      }
    }
    _ => panic()
  }
}

///|
test "SessionSummary json emits null for absent fix-09 fields" {
  let summary = SessionSummary::{
    id: "s_null",
    name: "null",
    working_dir: ".",
    status: "idle",
    created_at: "2026-07-24T12:00:00+08:00",
    updated_at: "2026-07-24T12:00:00+08:00",
    total_tasks: 0,
    total_cost: 0.0,
    cost_source: "estimated",
    error: "",
    model: None,
    source: "manual",
    latest_latency: None,
    pinned: false,
    agent_profile: "general",
    sub_model: None,
    sub_model_options: [],
    reasoning_effort: None,
    model_id: None,
    card_model: None,
    channel_info: None,
    error_code: None,
    top_up_url: None,
    raw_message: None,
  }
  match ToJson::to_json(summary) {
    Object(map) => {
      @debug.assert_eq(map.get("model_id"), Some(Json::null()))
      @debug.assert_eq(map.get("card_model"), Some(Json::null()))
      @debug.assert_eq(map.get("channel_info"), Some(Json::null()))
      @debug.assert_eq(map.get("error_code"), Some(Json::null()))
      @debug.assert_eq(map.get("top_up_url"), Some(Json::null()))
      @debug.assert_eq(map.get("raw_message"), Some(Json::null()))
    }
    _ => panic()
  }
}

///|
/// web-ui2-01 BUG-002: the fork response must carry session metadata only -
/// messages (which include the system prompt) must not leak.
test "fork response strips messages so system prompt does not leak" {
  let old = wd_push_profile()
  let id = "fork_leak_" + @agent.current_time_ms().to_string()
  let session = @agent.SessionData::{
    ..wd_make_session(id, "."),
    messages: [
      @message.Message::system(
        "[CRITICAL] Brand skill contents are CONFIDENTIAL",
      ),
      @message.Message::user("hello"),
    ],
  }
  @agent.save_session(session) catch {
    _ => ()
  }
  let resp = handle_session_fork(
    wd_make_server_ref(),
    wd_make_event(Post, "/api/sessions/" + id + "/fork", params=[("id", id)]),
  )
  assert_true(
    resp.status_code.to_int() >= 200 && resp.status_code.to_int() < 300,
  )
  let j = wd_response_json(resp)
  guard j is Object(top)
  @debug.assert_eq(top.get("source_session_id"), Some(id.to_json()))
  // forked_session must exist and carry NO messages key.
  match top.get("forked_session") {
    Some(Object(fs)) => {
      assert_false(fs.contains("messages"))
      // metadata still present
      @debug.assert_eq(fs.get("source"), Some("manual".to_json()))
      // cleanup the forked session too
      match fs.get("session_id") {
        Some(String(fid)) => @agent.delete_session(fid)
        _ => ()
      }
    }
    _ => panic()
  }
  // The confidential system prompt must not appear anywhere in the response body.
  assert_false(@utf8.decode(resp.raw_body).contains("CONFIDENTIAL"))
  @agent.delete_session(id)
  wd_pop_profile(old)
}

///|
/// web-ui2-02 BUG-023: POST /api/sessions must return an orig-shaped session
/// object with `id` (so the frontend can subscribe + send the first message)
/// and must NOT include `messages`.
test "create session response has orig shape with id and no messages" {
  let old = wd_push_profile()
  let config = @config.AgentConfig::default()
  config.models.push(
    @config.ModelConfig::new("m1", "sk-test", "https://api.test.com", "model-x"),
  )
  let server_ref = Ref(WebServer::new(config, None))
  let resp = handle_create_session(
    server_ref,
    wd_make_event(Post, "/api/sessions", body="{\"name\":\"ct-test\"}"),
  )
  @debug.assert_eq(resp.status_code.to_int(), 201)
  let j = wd_response_json(resp)
  guard j is Object(top)
  guard top.get("session") is Some(Object(s))
  guard s.get("id") is Some(String(id))
  assert_true(id.length() > 0)
  assert_false(s.contains("session_id"))
  assert_false(s.contains("messages"))
  assert_true(s.contains("status"))
  @debug.assert_eq(s.get("model"), Some("model-x".to_json()))
  @debug.assert_eq(s.get("model_id"), Some("model-x".to_json()))
  @debug.assert_eq(s.get("card_model"), Some("model-x".to_json()))
  @debug.assert_eq(s.get("error"), Some(Json::null()))
  @agent.delete_session(id)
  wd_pop_profile(old)
}

///|
/// web-ui2-02: GET /api/sessions/:id must align to orig field names
/// (id/status/model/model_id/card_model/error(null)/...) and omit messages.
test "detail response aligns orig field names and omits messages" {
  let old = wd_push_profile()
  let id = "orig_" + @agent.current_time_ms().to_string()
  let data = @agent.SessionData::{
    ..wd_make_session(id, "."),
    model_name: Some("model-x"),
    last_status: "idle",
  }
  @agent.save_session(data) catch {
    _ => ()
  }
  let resp = handle_get_session(
    wd_make_server_ref(),
    wd_make_event(Get, "/api/sessions/" + id, params=[("id", id)]),
  )
  @debug.assert_eq(resp.status_code.to_int(), 200)
  let j = wd_response_json(resp)
  guard j is Object(top)
  guard top.get("session") is Some(Object(s))
  @debug.assert_eq(s.get("id"), Some(id.to_json()))
  @debug.assert_eq(s.get("status"), Some("idle".to_json()))
  @debug.assert_eq(s.get("model"), Some("model-x".to_json()))
  @debug.assert_eq(s.get("model_id"), Some("model-x".to_json()))
  @debug.assert_eq(s.get("card_model"), Some("model-x".to_json()))
  @debug.assert_eq(s.get("error"), Some(Json::null()))
  @debug.assert_eq(s.get("error_code"), Some(Json::null()))
  @debug.assert_eq(s.get("top_up_url"), Some(Json::null()))
  @debug.assert_eq(s.get("raw_message"), Some(Json::null()))
  assert_false(s.contains("session_id"))
  assert_false(s.contains("messages"))
  @agent.delete_session(id)
  wd_pop_profile(old)
}
