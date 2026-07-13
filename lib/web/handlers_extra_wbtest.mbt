///| White-box tests for the supplementary REST API handlers (P1-5):

///| Memories, Settings, Share, Model presets, Benchmark session model,

///| and Session-scoped Time Machine points.

///|

///| These handlers persist JSON files under the config directory, so each

///| test redirects USERPROFILE to "_build" and cleans up afterward. The

///| handlers are invoked directly (no live server).

///|
fn ex_make_event(
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
    req: @crescent.HttpRequest::http_request(
      http_method,
      url,
      {},
      raw_body=@utf8.encode(body),
    ),
    res: @crescent.HttpResponse::http_response(status_code=OK),
    params: pmap,
  }
}

///|
fn ex_make_server_ref() -> Ref[WebServer] {
  Ref(WebServer::new(@config.AgentConfig::default(), None))
}

///|
fn ex_response_json(resp : @core.HttpResponse) -> Json {
  @json.parse(@utf8.decode(resp.raw_body)) catch {
    _ => Json::object({})
  }
}

///|
/// Redirect USERPROFILE to a temp dir and return the previous value.
fn ex_push_profile() -> String? {
  let old = @sys.get_env_var("USERPROFILE")
  @sys.set_env_var("USERPROFILE", "_build")
  old
}

///|
fn ex_pop_profile(old : String?) -> Unit {
  match old {
    Some(v) => @sys.set_env_var("USERPROFILE", v)
    None => @sys.set_env_var("USERPROFILE", "")
  }
}

///|
/// Remove a config-dir-backed data file (ignored if missing).
fn ex_clean(filename : String) -> Unit {
  match @utils.config_dir() {
    Some(d) =>
      @fs.remove_file(
        @path.Path::join(@path.Path(d), @path.Path(filename)).to_string(),
      ) catch {
        _ => ()
      }
    None => ()
  }
}

///|
fn ex_str_field(j : Json, key : String) -> String {
  match j {
    Object(o) =>
      match o.get(key) {
        Some(String(s)) => s
        _ => ""
      }
    _ => ""
  }
}

///|
fn ex_arr_field(j : Json, key : String) -> Array[Json] {
  match j {
    Object(o) =>
      match o.get(key) {
        Some(Array(a)) => a
        _ => []
      }
    _ => []
  }
}

// ── Memories ────────────────────────────────────────────────────────────

///|
test "memories get returns empty list when no store exists" {
  let old = ex_push_profile()
  let resp = handle_memories_get(
    ex_make_server_ref(),
    ex_make_event(Get, "/api/memories"),
  )
  ex_pop_profile(old)
  @debug.assert_eq(resp.status_code.to_int(), 200)
  @debug.assert_eq(ex_arr_field(ex_response_json(resp), "memories").length(), 0)
}

///|
test "memories post rejects empty content" {
  let resp = handle_memories_post(
    ex_make_server_ref(),
    ex_make_event(Post, "/api/memories", body="{}"),
  )
  @debug.assert_eq(resp.status_code.to_int(), 400)
}

///|
test "memories lifecycle create update get delete" {
  let old = ex_push_profile()
  ex_clean("memories.json")
  let sref = ex_make_server_ref()
  let post = handle_memories_post(
    sref,
    ex_make_event(Post, "/api/memories", body="{\"content\":\"hello\"}"),
  )
  @debug.assert_eq(post.status_code.to_int(), 200)
  let mid = ex_str_field(ex_response_json(post), "id")
  assert_true(!mid.is_empty())
  let put = handle_memories_put(
    sref,
    ex_make_event(
      Put,
      "/api/memories",
      body="{\"id\":\"" + mid + "\",\"content\":\"world\"}",
    ),
  )
  @debug.assert_eq(put.status_code.to_int(), 200)
  let get = handle_memories_get(sref, ex_make_event(Get, "/api/memories"))
  let arr = ex_arr_field(ex_response_json(get), "memories")
  @debug.assert_eq(arr.length(), 1)
  let first = match arr[0] {
    Object(o) => Json::object(o)
    _ => Json::object({})
  }
  @debug.assert_eq(ex_str_field(first, "content"), "world")
  let del = handle_memories_delete(
    sref,
    ex_make_event(Delete, "/api/memories?id=" + mid),
  )
  @debug.assert_eq(del.status_code.to_int(), 200)
  let get2 = handle_memories_get(sref, ex_make_event(Get, "/api/memories"))
  @debug.assert_eq(ex_arr_field(ex_response_json(get2), "memories").length(), 0)
  ex_clean("memories.json")
  ex_pop_profile(old)
}

///|
test "memories delete rejects missing id" {
  let resp = handle_memories_delete(
    ex_make_server_ref(),
    ex_make_event(Delete, "/api/memories"),
  )
  @debug.assert_eq(resp.status_code.to_int(), 400)
}

// ── Settings ────────────────────────────────────────────────────────────

///|
test "settings put then get persists values" {
  let old = ex_push_profile()
  ex_clean("settings.json")
  let sref = ex_make_server_ref()
  let put = handle_settings_put(
    sref,
    ex_make_event(Put, "/api/settings", body="{\"theme\":\"light\"}"),
  )
  @debug.assert_eq(put.status_code.to_int(), 200)
  let get = handle_settings_get(sref, ex_make_event(Get, "/api/settings"))
  @debug.assert_eq(ex_str_field(ex_response_json(get), "theme"), "light")
  ex_clean("settings.json")
  ex_pop_profile(old)
}

// ── Share ──────────────────────────────────────────────────────────────

///|
test "share post then get lists entry" {
  let old = ex_push_profile()
  ex_clean("shares.json")
  let sref = ex_make_server_ref()
  let post = handle_share_post(
    sref,
    ex_make_event(
      Post,
      "/api/share",
      body="{\"type\":\"link\",\"target\":\"http://example\"}",
    ),
  )
  @debug.assert_eq(post.status_code.to_int(), 200)
  let get = handle_share_get(sref, ex_make_event(Get, "/api/share"))
  @debug.assert_eq(ex_arr_field(ex_response_json(get), "shares").length(), 1)
  ex_clean("shares.json")
  ex_pop_profile(old)
}

///|
test "share post requires type and target" {
  let resp = handle_share_post(
    ex_make_server_ref(),
    ex_make_event(Post, "/api/share", body="{\"type\":\"link\"}"),
  )
  @debug.assert_eq(resp.status_code.to_int(), 400)
}

// ── Model presets ──────────────────────────────────────────────────────

///|
test "models lifecycle create list update delete" {
  let old = ex_push_profile()
  ex_clean("models.json")
  let sref = ex_make_server_ref()
  let post = handle_models_post(
    sref,
    ex_make_event(
      Post,
      "/api/models",
      body="{\"name\":\"m1\",\"model\":\"gpt\"}",
    ),
  )
  @debug.assert_eq(post.status_code.to_int(), 200)
  let mid = ex_str_field(ex_response_json(post), "id")
  assert_true(!mid.is_empty())
  let get = handle_models_get(sref, ex_make_event(Get, "/api/models"))
  @debug.assert_eq(ex_arr_field(ex_response_json(get), "models").length(), 1)
  let put = handle_models_put(
    sref,
    ex_make_event(Put, "/api/models/" + mid, body="{\"name\":\"m2\"}", params=[
      ("id", mid),
    ]),
  )
  @debug.assert_eq(put.status_code.to_int(), 200)
  let get2 = handle_models_get(sref, ex_make_event(Get, "/api/models"))
  let arr = ex_arr_field(ex_response_json(get2), "models")
  @debug.assert_eq(arr.length(), 1)
  let first = match arr[0] {
    Object(o) => Json::object(o)
    _ => Json::object({})
  }
  @debug.assert_eq(ex_str_field(first, "name"), "m2")
  let del = handle_models_delete(
    sref,
    ex_make_event(Delete, "/api/models/" + mid, params=[("id", mid)]),
  )
  @debug.assert_eq(del.status_code.to_int(), 200)
  let get3 = handle_models_get(sref, ex_make_event(Get, "/api/models"))
  @debug.assert_eq(ex_arr_field(ex_response_json(get3), "models").length(), 0)
  ex_clean("models.json")
  ex_pop_profile(old)
}

///|
test "models put rejects missing id" {
  let resp = handle_models_put(
    ex_make_server_ref(),
    ex_make_event(Put, "/api/models/xyz", body="{}", params=[]),
  )
  @debug.assert_eq(resp.status_code.to_int(), 400)
}

// ── Benchmark session model ─────────────────────────────────────────────

///|
test "benchmark model get default then post updates" {
  let old = ex_push_profile()
  ex_clean("benchmark_models.json")
  let sref = ex_make_server_ref()
  let sid = "sess-bm"
  let g0 = handle_benchmark_model_get(
    sref,
    ex_make_event(Get, "/api/benchmark/sessions/" + sid + "/model", params=[
      ("id", sid),
    ]),
  )
  @debug.assert_eq(g0.status_code.to_int(), 200)
  @debug.assert_eq(ex_str_field(ex_response_json(g0), "model"), "")
  let p = handle_benchmark_model_post(
    sref,
    ex_make_event(
      Post,
      "/api/benchmark/sessions/" + sid + "/model",
      body="{\"model\":\"gpt-4\"}",
      params=[("id", sid)],
    ),
  )
  @debug.assert_eq(p.status_code.to_int(), 200)
  @debug.assert_eq(ex_str_field(ex_response_json(p), "model"), "gpt-4")
  let g1 = handle_benchmark_model_get(
    sref,
    ex_make_event(Get, "/api/benchmark/sessions/" + sid + "/model", params=[
      ("id", sid),
    ]),
  )
  @debug.assert_eq(ex_str_field(ex_response_json(g1), "model"), "gpt-4")
  ex_clean("benchmark_models.json")
  ex_pop_profile(old)
}

///|
test "benchmark model post rejects missing model" {
  let resp = handle_benchmark_model_post(
    ex_make_server_ref(),
    ex_make_event(Post, "/api/benchmark/sessions/x/model", body="{}", params=[
      ("id", "x"),
    ]),
  )
  @debug.assert_eq(resp.status_code.to_int(), 400)
}

// ── Session-scoped Time Machine ─────────────────────────────────────────

///|
test "time machine add point then list" {
  let old = ex_push_profile()
  let sid = "sess-tm"
  ex_clean("time_machine_" + sid + ".json")
  let sref = ex_make_server_ref()
  let post = handle_session_time_machine_post(
    sref,
    ex_make_event(
      Post,
      "/api/sessions/" + sid + "/time-machine",
      body="{\"description\":\"point1\"}",
      params=[("id", sid)],
    ),
  )
  @debug.assert_eq(post.status_code.to_int(), 200)
  let pid = ex_str_field(ex_response_json(post), "id")
  assert_true(!pid.is_empty())
  let get = handle_session_time_machine_get(
    sref,
    ex_make_event(Get, "/api/sessions/" + sid + "/time-machine", params=[
      ("id", sid),
    ]),
  )
  @debug.assert_eq(get.status_code.to_int(), 200)
  @debug.assert_eq(ex_arr_field(ex_response_json(get), "points").length(), 1)
  ex_clean("time_machine_" + sid + ".json")
  ex_pop_profile(old)
}

///|
test "time machine get rejects missing id" {
  let resp = handle_session_time_machine_get(
    ex_make_server_ref(),
    ex_make_event(Get, "/api/sessions/x/time-machine", params=[]),
  )
  @debug.assert_eq(resp.status_code.to_int(), 400)
}
