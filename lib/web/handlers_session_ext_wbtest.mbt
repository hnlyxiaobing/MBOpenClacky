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
  let old = @env.get_env_var("USERPROFILE")
  @env.set_env_var("USERPROFILE", "_build")
  old
}

///|
fn wd_pop_profile(old : String?) -> Unit {
  match old {
    Some(v) => @env.set_env_var("USERPROFILE", v)
    None => @env.set_env_var("USERPROFILE", "")
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
    model_config_id: None,
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
  guard! j is Json::Object(obj)
  @debug.assert_eq(obj.get("working_dir"), Some("sub/dir".to_json()))
  match @agent.load_session(id) {
    Some(d) => @debug.assert_eq(d.working_dir, "sub/dir")
    None => panic()
  }
  @agent.delete_session(id)
  wd_pop_profile(old)
}

///|
test "working_dir update normalizes mixed separators" {
  let old = wd_push_profile()
  let id = "wd_norm_" + @agent.current_time_ms().to_string()
  @agent.save_session(wd_make_session(id, ".")) catch {
    _ => ()
  }
  let resp = handle_update_working_dir(
    wd_make_server_ref(),
    wd_make_event(
      Patch,
      "/api/sessions/" + id + "/working_dir",
      body="{\"working_dir\":\"sub\\\\dir\"}",
      params=[("id", id)],
    ),
  )
  @debug.assert_eq(resp.status_code.to_int(), 200)
  let j = wd_response_json(resp)
  guard! j is Json::Object(obj)
  @debug.assert_eq(obj.get("working_dir"), Some("sub/dir".to_json()))
  match @agent.load_session(id) {
    Some(d) => @debug.assert_eq(d.working_dir, "sub/dir")
    None => panic()
  }
  @agent.delete_session(id)
  wd_pop_profile(old)
}

///|
test "working_dir update normalizes absolute mixed separators within configured dir" {
  let old = wd_push_profile()
  let id = "wd_absnorm_" + @agent.current_time_ms().to_string()
  @agent.save_session(wd_make_session(id, ".")) catch {
    _ => ()
  }
  let cfg = @config.AgentConfig::default()
  cfg.default_working_dir = Some("C:\\base")
  let server_ref = Ref(WebServer::new(cfg, None))
  let resp = handle_update_working_dir(
    server_ref,
    wd_make_event(
      Patch,
      "/api/sessions/" + id + "/working_dir",
      body="{\"working_dir\":\"C:\\\\base/sub\"}",
      params=[("id", id)],
    ),
  )
  @debug.assert_eq(resp.status_code.to_int(), 200)
  match @agent.load_session(id) {
    Some(d) => @debug.assert_eq(d.working_dir, "C:/base/sub")
    None => panic()
  }
  @agent.delete_session(id)
  wd_pop_profile(old)
}

///|
test "create session normalizes mixed separators in working_dir" {
  let old = wd_push_profile()
  let config = @config.AgentConfig::default()
  config.models.push(
    @config.ModelConfig::new("m1", "sk-test", "https://api.test.com", "model-x"),
  )
  let server_ref = Ref(WebServer::new(config, None))
  let resp = handle_create_session(
    server_ref,
    wd_make_event(
      Post,
      "/api/sessions",
      body="{\"name\":\"wd-create\",\"working_dir\":\"sub\\\\dir\"}",
    ),
  )
  @debug.assert_eq(resp.status_code.to_int(), 201)
  let j = wd_response_json(resp)
  guard! j is Json::Object(top)
  guard! top.get("session") is Some(Object(s))
  guard! s.get("id") is Some(String(id))
  @debug.assert_eq(s.get("working_dir"), Some("sub/dir".to_json()))
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
test "working_dir update allows absolute path when no configured dir" {
  let old = wd_push_profile()
  let id = "wd_absok2_" + @agent.current_time_ms().to_string()
  @agent.save_session(wd_make_session(id, ".")) catch {
    _ => ()
  }
  // default config has default_working_dir = None — the sandbox is opt-in,
  // so absolute paths are allowed (mirrors POST /api/sessions).
  let resp = handle_update_working_dir(
    wd_make_server_ref(),
    wd_make_event(
      Patch,
      "/api/sessions/" + id + "/working_dir",
      body="{\"working_dir\":\"/tmp/anywhere\"}",
      params=[("id", id)],
    ),
  )
  @debug.assert_eq(resp.status_code.to_int(), 200)
  match @agent.load_session(id) {
    Some(d) => @debug.assert_eq(d.working_dir, "/tmp/anywhere")
    None => panic()
  }
  @agent.delete_session(id)
  wd_pop_profile(old)
}

///|
test "working_dir update strips trailing slash" {
  let old = wd_push_profile()
  let id = "wd_trail_" + @agent.current_time_ms().to_string()
  @agent.save_session(wd_make_session(id, ".")) catch {
    _ => ()
  }
  let resp = handle_update_working_dir(
    wd_make_server_ref(),
    wd_make_event(
      Patch,
      "/api/sessions/" + id + "/working_dir",
      body="{\"working_dir\":\"sub/dir/\"}",
      params=[("id", id)],
    ),
  )
  @debug.assert_eq(resp.status_code.to_int(), 200)
  match @agent.load_session(id) {
    Some(d) => @debug.assert_eq(d.working_dir, "sub/dir")
    None => panic()
  }
  @agent.delete_session(id)
  wd_pop_profile(old)
}

///|
test "is_placeholder_session_name matches only auto-assigned names" {
  assert_true(is_placeholder_session_name("Session 1"))
  assert_true(is_placeholder_session_name("Session 42"))
  assert_false(is_placeholder_session_name("Session"))
  assert_false(is_placeholder_session_name("Session x"))
  assert_false(is_placeholder_session_name("My Session"))
  assert_false(is_placeholder_session_name("Session 1 beta"))
  assert_false(is_placeholder_session_name("session 1"))
}

///|
test "derive_session_title collapses whitespace and truncates at 30 chars" {
  @debug.assert_eq(derive_session_title("hello world"), "hello world")
  @debug.assert_eq(
    derive_session_title("  帮我\n  总结一下\t这个仓库  "),
    "帮我 总结一下 这个仓库",
  )
  @debug.assert_eq(derive_session_title(""), "")
  @debug.assert_eq(derive_session_title("   \n  "), "")
  let long = "0123456789012345678901234567890123456789"
  @debug.assert_eq(
    derive_session_title(long),
    "012345678901234567890123456789…",
  )
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
  guard! j is Json::Object(top)
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
  guard! j is Json::Object(top)
  guard! top.get("session") is Some(Object(s))
  guard! s.get("id") is Some(String(id))
  assert_true(id.length() > 0)
  assert_false(s.contains("session_id"))
  assert_false(s.contains("messages"))
  assert_true(s.contains("status"))
  @debug.assert_eq(s.get("model"), Some("model-x".to_json()))
  // model_id carries the ModelConfig id, not the API model string.
  @debug.assert_eq(s.get("model_id"), Some("m1".to_json()))
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
    model_config_id: Some("m1"),
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
  guard! j is Json::Object(top)
  guard! top.get("session") is Some(Object(s))
  @debug.assert_eq(s.get("id"), Some(id.to_json()))
  @debug.assert_eq(s.get("status"), Some("idle".to_json()))
  @debug.assert_eq(s.get("model"), Some("model-x".to_json()))
  @debug.assert_eq(s.get("model_id"), Some("m1".to_json()))
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

///|
test "delete session returns 200 ok json (web-ui2-03 BUG-008)" {
  let old = wd_push_profile()
  let id = "del_ok_" + @agent.current_time_ms().to_string()
  @agent.save_session(wd_make_session(id, ".")) catch {
    _ => ()
  }
  // reset global trash state so trash_add_session's disk write is hermetic
  trash_state.val.items = []
  trash_state.val.loaded = true
  let resp = handle_delete_session(
    wd_make_server_ref(),
    wd_make_event(Delete, "/api/sessions/" + id, params=[("id", id)]),
  )
  @debug.assert_eq(resp.status_code.to_int(), 200)
  let j = wd_response_json(resp)
  guard! j is Json::Object(obj)
  @debug.assert_eq(obj.get("ok"), Some(true.to_json()))
  @agent.delete_session(id)
  wd_pop_profile(old)
}

///|
/// web-ui2-09 BUG-010: POST /api/sessions without name must return 400.
test "create session without name returns 400 name is required" {
  let old = wd_push_profile()
  let config = @config.AgentConfig::default()
  config.models.push(
    @config.ModelConfig::new("m1", "sk-test", "https://api.test.com", "model-x"),
  )
  let server_ref = Ref(WebServer::new(config, None))
  let resp = handle_create_session(
    server_ref,
    wd_make_event(Post, "/api/sessions", body="{\"agent_profile\":\"general\"}"),
  )
  @debug.assert_eq(resp.status_code.to_int(), 400)
  let j = wd_response_json(resp)
  guard! j is Json::Object(obj)
  @debug.assert_eq(obj.get("error"), Some("name is required".to_json()))
  wd_pop_profile(old)
}

///|
/// web-ui2-09 BUG-010: POST /api/sessions with empty name must return 400.
test "create session with empty name returns 400 name is required" {
  let old = wd_push_profile()
  let config = @config.AgentConfig::default()
  config.models.push(
    @config.ModelConfig::new("m1", "sk-test", "https://api.test.com", "model-x"),
  )
  let server_ref = Ref(WebServer::new(config, None))
  let resp = handle_create_session(
    server_ref,
    wd_make_event(Post, "/api/sessions", body="{\"name\":\"\"}"),
  )
  @debug.assert_eq(resp.status_code.to_int(), 400)
  let j = wd_response_json(resp)
  guard! j is Json::Object(obj)
  @debug.assert_eq(obj.get("error"), Some("name is required".to_json()))
  wd_pop_profile(old)
}

///|
/// web-ui2-09 BUG-011: PATCH /api/sessions/:id/rename returns {ok,name}.
test "rename session returns ok and name (web-ui2-09 BUG-011)" {
  let old = wd_push_profile()
  let id = "rn_" + @agent.current_time_ms().to_string()
  @agent.save_session(wd_make_session(id, ".")) catch {
    _ => ()
  }
  let resp = handle_session_rename(
    wd_make_server_ref(),
    wd_make_event(
      Patch,
      "/api/sessions/" + id + "/rename",
      body="{\"name\":\"renamed-x\"}",
      params=[("id", id)],
    ),
  )
  @debug.assert_eq(resp.status_code.to_int(), 200)
  let j = wd_response_json(resp)
  guard! j is Json::Object(obj)
  @debug.assert_eq(obj.get("ok"), Some(true.to_json()))
  @debug.assert_eq(obj.get("name"), Some("renamed-x".to_json()))
  assert_false(obj.contains("session_id"))
  assert_false(obj.contains("old_name"))
  @agent.delete_session(id)
  wd_pop_profile(old)
}

///|
/// web-ui2-09 BUG-011: PATCH /api/sessions/:id (pin) returns {ok,pinned}.
test "pin session returns ok and pinned (web-ui2-09 BUG-011)" {
  let old = wd_push_profile()
  let id = "pin_" + @agent.current_time_ms().to_string()
  @agent.save_session(wd_make_session(id, ".")) catch {
    _ => ()
  }
  let resp = handle_session_patch(
    wd_make_server_ref(),
    wd_make_event(Patch, "/api/sessions/" + id, body="{\"pinned\":true}", params=[
      ("id", id),
    ]),
  )
  @debug.assert_eq(resp.status_code.to_int(), 200)
  let j = wd_response_json(resp)
  guard! j is Json::Object(obj)
  @debug.assert_eq(obj.get("ok"), Some(true.to_json()))
  @debug.assert_eq(obj.get("pinned"), Some(true.to_json()))
  assert_false(obj.contains("session_id"))
  assert_false(obj.contains("name"))
  // cleanup pinned entry so the test is hermetic
  let pm = load_pinned_map()
  ignore(pm.remove(id))
  ignore(save_pinned_map(pm))
  @agent.delete_session(id)
  wd_pop_profile(old)
}

///|
/// Regression: PATCH /api/sessions/:id/model returned 404 "Session not
/// found" when the session lived only in active_agents (initial save_session
/// silently failed, or enforce_session_cap pruned the disk file). The handler
/// now falls back to the in-memory agent (mirroring handle_ws_subscribe) and
/// re-persists the session so subsequent reads hit disk.
test "model patch falls back to in-memory agent when disk file is missing" {
  let old = wd_push_profile()
  let mem_id = "modmem_" + @agent.current_time_ms().to_string()
  let config = @config.AgentConfig::default()
  config.models.push(
    @config.ModelConfig::new("m1", "sk-test", "https://api.test.com", "model-x"),
  )
  let server_ref = Ref(WebServer::new(config, None))
  let client = @client.Client::new(
    "k",
    "https://api.test.com",
    "m",
    @config.OpenAICompletions,
  )
  let agent = @agent.Agent::new(mem_id, "mem-session", ".", client, config)
  server_ref.val.active_agents[mem_id] = agent
  // Sanity: nothing on disk yet - this is the bug's precondition.
  match @agent.load_session(mem_id) {
    Some(_) => panic()
    None => ()
  }
  let resp = handle_session_model_patch(
    server_ref,
    wd_make_event(
      Patch,
      "/api/sessions/" + mem_id + "/model",
      body="{\"model_id\":\"m1\"}",
      params=[("id", mem_id)],
    ),
  )
  @debug.assert_eq(resp.status_code.to_int(), 200)
  // The patch must re-persist the session so future reads hit disk.
  match @agent.load_session(mem_id) {
    Some(d) => {
      @debug.assert_eq(d.model_name, Some("model-x"))
      @debug.assert_eq(d.model_config_id, Some("m1"))
    }
    None => panic()
  }
  @agent.delete_session(mem_id)
  wd_pop_profile(old)
}

///|
/// Same fallback for PATCH /:id/reasoning_effort.
test "reasoning_effort patch falls back to in-memory agent when disk file is missing" {
  let old = wd_push_profile()
  let mem_id = "rsmem_" + @agent.current_time_ms().to_string()
  let config = @config.AgentConfig::default()
  let server_ref = Ref(WebServer::new(config, None))
  let client = @client.Client::new(
    "k",
    "https://api.test.com",
    "m",
    @config.OpenAICompletions,
  )
  let agent = @agent.Agent::new(mem_id, "mem-session", ".", client, config)
  server_ref.val.active_agents[mem_id] = agent
  let resp = handle_session_reasoning_effort_patch(
    server_ref,
    wd_make_event(
      Patch,
      "/api/sessions/" + mem_id + "/reasoning_effort",
      body="{\"reasoning_effort\":\"high\"}",
      params=[("id", mem_id)],
    ),
  )
  @debug.assert_eq(resp.status_code.to_int(), 200)
  match @agent.load_session(mem_id) {
    Some(d) => @debug.assert_eq(d.reasoning_effort, Some("high"))
    None => panic()
  }
  @agent.delete_session(mem_id)
  wd_pop_profile(old)
}

// ── Model identity unification (2026-08-03 spec) ─────────────────────────────

///|
/// Create with a config whose id differs from its model string must persist
/// and report the config id (summary.model_id), not the model string.
test "create with id!=model persists and reports config id" {
  let old = wd_push_profile()
  let config = @config.AgentConfig::default()
  config.models.push(
    @config.ModelConfig::new(
      "cfg_1", "sk-test", "https://api.test.com", "model-x",
    ),
  )
  let server_ref = Ref(WebServer::new(config, None))
  let resp = handle_create_session(
    server_ref,
    wd_make_event(
      Post,
      "/api/sessions",
      body="{\"name\":\"mi-e2e\",\"model_id\":\"cfg_1\"}",
    ),
  )
  @debug.assert_eq(resp.status_code.to_int(), 201)
  let j = wd_response_json(resp)
  guard! j is Json::Object(top)
  // Successful lookup must not flag a fallback.
  assert_false(top.contains("model_fallback"))
  guard! top.get("session") is Some(Object(s))
  guard! s.get("id") is Some(String(id))
  @debug.assert_eq(s.get("model_id"), Some("cfg_1".to_json()))
  @debug.assert_eq(s.get("model"), Some("model-x".to_json()))
  // The persisted snapshot carries the config id.
  match @agent.load_session(id) {
    Some(d) => {
      @debug.assert_eq(d.model_config_id, Some("cfg_1"))
      @debug.assert_eq(d.model_name, Some("model-x"))
    }
    None => panic()
  }
  @agent.delete_session(id)
  wd_pop_profile(old)
}

///|
/// Create with an unknown model_id still succeeds (201) on the default model
/// but flags the fallback at the response top level so the UI can warn.
test "create with unknown model_id falls back and flags model_fallback" {
  let old = wd_push_profile()
  let config = @config.AgentConfig::default()
  config.models.push(
    @config.ModelConfig::new(
      "cfg_1", "sk-test", "https://api.test.com", "model-x",
    ),
  )
  let server_ref = Ref(WebServer::new(config, None))
  let resp = handle_create_session(
    server_ref,
    wd_make_event(
      Post,
      "/api/sessions",
      body="{\"name\":\"mi-fb\",\"model_id\":\"nope\"}",
    ),
  )
  @debug.assert_eq(resp.status_code.to_int(), 201)
  let j = wd_response_json(resp)
  guard! j is Json::Object(top)
  @debug.assert_eq(top.get("model_fallback"), Some(true.to_json()))
  guard! top.get("session") is Some(Object(s))
  guard! s.get("id") is Some(String(id))
  // The session runs on the default model and reports that model's id.
  @debug.assert_eq(s.get("model"), Some("model-x".to_json()))
  @debug.assert_eq(s.get("model_id"), Some("cfg_1".to_json()))
  @agent.delete_session(id)
  wd_pop_profile(old)
}

///|
/// PATCH /:id/model on a disk-backed session persists the config id and the
/// detail summary reports it afterwards.
test "model patch persists config id for disk-backed session" {
  let old = wd_push_profile()
  let id = "moddisk_" + @agent.current_time_ms().to_string()
  @agent.save_session(wd_make_session(id, ".")) catch {
    _ => ()
  }
  let config = @config.AgentConfig::default()
  config.models.push(
    @config.ModelConfig::new(
      "cfg_9", "sk-test", "https://api.test.com", "model-y",
    ),
  )
  let server_ref = Ref(WebServer::new(config, None))
  let resp = handle_session_model_patch(
    server_ref,
    wd_make_event(
      Patch,
      "/api/sessions/" + id + "/model",
      body="{\"model_id\":\"cfg_9\"}",
      params=[("id", id)],
    ),
  )
  @debug.assert_eq(resp.status_code.to_int(), 200)
  let j = wd_response_json(resp)
  guard! j is Json::Object(obj)
  @debug.assert_eq(obj.get("model_id"), Some("cfg_9".to_json()))
  match @agent.load_session(id) {
    Some(d) => {
      @debug.assert_eq(d.model_config_id, Some("cfg_9"))
      @debug.assert_eq(d.model_name, Some("model-y"))
    }
    None => panic()
  }
  // The detail summary reports the config id after the switch.
  let resp2 = handle_get_session(
    server_ref,
    wd_make_event(Get, "/api/sessions/" + id, params=[("id", id)]),
  )
  let j2 = wd_response_json(resp2)
  guard! j2 is Json::Object(top2)
  guard! top2.get("session") is Some(Object(s2))
  @debug.assert_eq(s2.get("model_id"), Some("cfg_9".to_json()))
  @agent.delete_session(id)
  wd_pop_profile(old)
}
