///| White-box tests for the supplementary REST API handlers (P1-5):

///| Memories, Settings, Share, Model presets, Benchmark session model,

///| Session-scoped Time Machine points, and Config /api/config/models.

///| Config-model tests cover the bug where POST/PATCH silently dropped

///| anthropic_format and type_ from the frontend payload.

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
fn ex_make_server_ref() -> Ref[WebServer] {
  Ref(WebServer::new(@config.AgentConfig::default(), None))
}

///|
fn ex_response_json(resp : @core.HttpResponse) -> Json {
  @json.parse(@utf8.decode(resp.raw_body)) catch {
    _ => Json::object(Map([]))
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
    _ => Json::object(Map([]))
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
    _ => Json::object(Map([]))
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

// ── Config /api/config/models (regression for anthropic_format / type_) ─

///|
/// Helper: find a model entry in the GET /api/config/models response by id.
fn ex_find_model(j : Json, id : String) -> Json {
  let arr = ex_arr_field(j, "models")
  for m in arr {
    match m {
      Object(o) =>
        match o.get("id") {
          Some(String(sid)) if sid == id => return Json::object(o)
          _ => ()
        }
      _ => ()
    }
  }
  Json::object(Map([]))
}

///|
/// Helper: extract a nested string field from a JSON object via dotted key
/// path, e.g. `ex_nested_str_field(j, "model.id")` returns the "id" inside
/// the value of the "model" key. Returns "" for missing/non-string values.
fn ex_nested_str_field(j : Json, path : String) -> String {
  let parts = path.split(".")
  let mut cur = j
  for part in parts {
    let k = part.to_owned()
    match cur {
      Object(o) =>
        match o.get(k) {
          Some(v) => cur = v
          None => return ""
        }
      _ => return ""
    }
  }
  match cur {
    String(s) => s
    _ => ""
  }
}

///|
/// POST /api/config/models must persist anthropic_format and type_ from the
/// payload. Without this, a Claude model would be silently saved as OpenAI.
test "config models post honors anthropic_format and type_" {
  let old = ex_push_profile()
  let sref = ex_make_server_ref()
  let resp = handle_config_models_post(
    sref,
    ex_make_event(
      Post,
      "/api/config/models",
      body="{\"model\":\"claude-test\",\"base_url\":\"https://api.anthropic.com\",\"api_key\":\"sk-test\",\"anthropic_format\":true,\"type\":\"claude\"}",
    ),
  )
  @debug.assert_eq(resp.status_code.to_int(), 201)
  let post_json = ex_response_json(resp)
  let id = ex_nested_str_field(post_json, "model.id")
  @debug.assert_eq(id.is_empty(), false)
  // Confirm GET also reflects the saved values.
  let get = handle_list_models(sref, ex_make_event(Get, "/api/config/models"))
  @debug.assert_eq(get.status_code.to_int(), 200)
  let get_json = ex_response_json(get)
  let found = ex_find_model(get_json, id)
  // GET response goes through model_to_web_json, which renames type_ -> type
  // (the frontend consumes `model.type`).
  @debug.assert_eq(ex_str_field(found, "type"), "claude")
  // anthropic_format is a Bool — assert via a JSON path-style extraction
  match found {
    Object(o) =>
      match o.get("anthropic_format") {
        Some(True) => ()
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
  ex_pop_profile(old)
}

///|
/// PATCH /api/config/models/:id must overwrite anthropic_format and type_
/// when they are present in the payload.
test "config models patch updates anthropic_format and type_" {
  let old = ex_push_profile()
  let sref = ex_make_server_ref()
  // Seed a Claude model
  let post = handle_config_models_post(
    sref,
    ex_make_event(
      Post,
      "/api/config/models",
      body="{\"model\":\"m\",\"base_url\":\"https://api.anthropic.com\",\"api_key\":\"k\",\"anthropic_format\":true,\"type\":\"claude\"}",
    ),
  )
  let id = ex_nested_str_field(ex_response_json(post), "model.id")
  @debug.assert_eq(id.is_empty(), false)
  // Flip it to OpenAI
  let patch = handle_config_models_patch(
    sref,
    ex_make_event(
      Patch,
      "/api/config/models/" + id,
      body="{\"model\":\"m\",\"base_url\":\"https://api.openai.com\",\"api_key\":\"k\",\"anthropic_format\":false,\"type\":\"openai-completions\"}",
      params=[("id", id)],
    ),
  )
  @debug.assert_eq(patch.status_code.to_int(), 200)
  let get = handle_list_models(sref, ex_make_event(Get, "/api/config/models"))
  let found = ex_find_model(ex_response_json(get), id)
  // GET response goes through model_to_web_json, which renames type_ -> type.
  @debug.assert_eq(ex_str_field(found, "type"), "openai-completions")
  match found {
    Object(o) =>
      match o.get("anthropic_format") {
        Some(False) => ()
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
  ex_pop_profile(old)
}

///|
/// PATCH /api/config/models/:id must preserve anthropic_format and type_
/// when they are absent from the payload (otherwise partial edits would
/// silently revert the protocol back to OpenAI).
test "config models patch preserves anthropic_format and type_ when absent" {
  let old = ex_push_profile()
  let sref = ex_make_server_ref()
  let post = handle_config_models_post(
    sref,
    ex_make_event(
      Post,
      "/api/config/models",
      body="{\"model\":\"m\",\"base_url\":\"https://api.anthropic.com\",\"api_key\":\"k\",\"anthropic_format\":true,\"type\":\"claude\"}",
    ),
  )
  let id = ex_nested_str_field(ex_response_json(post), "model.id")
  @debug.assert_eq(id.is_empty(), false)
  // Send only model/base_url/api_key — type_ and anthropic_format must NOT
  // be reset to defaults.
  let patch = handle_config_models_patch(
    sref,
    ex_make_event(
      Patch,
      "/api/config/models/" + id,
      body="{\"model\":\"renamed\",\"base_url\":\"https://api.anthropic.com\",\"api_key\":\"k\"}",
      params=[("id", id)],
    ),
  )
  @debug.assert_eq(patch.status_code.to_int(), 200)
  let get = handle_list_models(sref, ex_make_event(Get, "/api/config/models"))
  let found = ex_find_model(ex_response_json(get), id)
  @debug.assert_eq(ex_str_field(found, "model"), "renamed")
  // GET response goes through model_to_web_json, which renames type_ -> type.
  @debug.assert_eq(ex_str_field(found, "type"), "claude")
  match found {
    Object(o) =>
      match o.get("anthropic_format") {
        Some(True) => ()
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
  ex_pop_profile(old)
}

// ── Config /api/config/models (required-field validation) ──────────────

///|
/// POST /api/config/models must reject a fully-empty body with HTTP 400
/// instead of silently creating a phantom empty model entry.
test "config models post rejects empty body" {
  let old = ex_push_profile()
  let sref = ex_make_server_ref()
  let resp = handle_config_models_post(
    sref,
    ex_make_event(Post, "/api/config/models", body="{}"),
  )
  ex_pop_profile(old)
  @debug.assert_eq(resp.status_code.to_int(), 400)
}

///|
/// When api_key is missing the response must name it specifically,
/// not say "all of base_url and api_key are required".
test "config models post rejects missing api_key with field name" {
  let old = ex_push_profile()
  let sref = ex_make_server_ref()
  let resp = handle_config_models_post(
    sref,
    ex_make_event(
      Post,
      "/api/config/models",
      body="{\"model\":\"m\",\"base_url\":\"https://api.x.com\"}",
    ),
  )
  ex_pop_profile(old)
  @debug.assert_eq(resp.status_code.to_int(), 400)
  let body = ex_response_json(resp)
  let msg = ex_str_field(body, "error")
  assert_true(msg.contains("api_key"))
  assert_true(!msg.contains("base_url"))
  assert_true(!msg.contains("model"))
}

///|
/// When only base_url is missing the response must list only base_url.
test "config models post rejects missing base_url with field name" {
  let old = ex_push_profile()
  let sref = ex_make_server_ref()
  let resp = handle_config_models_post(
    sref,
    ex_make_event(
      Post,
      "/api/config/models",
      body="{\"model\":\"m\",\"api_key\":\"k\"}",
    ),
  )
  ex_pop_profile(old)
  @debug.assert_eq(resp.status_code.to_int(), 400)
  let msg = ex_str_field(ex_response_json(resp), "error")
  assert_true(msg.contains("base_url"))
  assert_true(!msg.contains("api_key"))
}

///|
/// All three missing should list all three field names.
test "config models post lists every missing field" {
  let old = ex_push_profile()
  let sref = ex_make_server_ref()
  let resp = handle_config_models_post(
    sref,
    ex_make_event(Post, "/api/config/models", body="{\"other\":\"x\"}"),
  )
  ex_pop_profile(old)
  @debug.assert_eq(resp.status_code.to_int(), 400)
  let msg = ex_str_field(ex_response_json(resp), "error")
  assert_true(msg.contains("model"))
  assert_true(msg.contains("base_url"))
  assert_true(msg.contains("api_key"))
}

///|
/// Regression: a valid payload must still succeed after the validator
/// landed, otherwise the new check would over-block the happy path.
test "config models post still accepts a complete payload" {
  let old = ex_push_profile()
  let sref = ex_make_server_ref()
  let resp = handle_config_models_post(
    sref,
    ex_make_event(
      Post,
      "/api/config/models",
      body="{\"model\":\"m\",\"base_url\":\"https://api.x.com\",\"api_key\":\"k\"}",
    ),
  )
  ex_pop_profile(old)
  @debug.assert_eq(resp.status_code.to_int(), 201)
}

///|
/// GET /api/providers must serve the real preset registry (not a hardcoded
/// stub), including default_model, website_url and endpoint_variants which
/// the settings UI consumes for quick setup and regional endpoint dropdowns.
test "providers list serves the full preset registry" {
  let resp = handle_providers_list(
    ex_make_server_ref(),
    ex_make_event(Get, "/api/providers"),
  )
  @debug.assert_eq(resp.status_code.to_int(), 200)
  guard ex_response_json(resp) is Object(top)
  guard top.get("providers") is Some(Array(arr))
  @debug.assert_eq(arr.length(), @config.Providers::all().length())
  // Every entry must expose the fields the frontend needs.
  let mut saw_openclacky = false
  let mut saw_glm_variants = false
  for item in arr {
    match item {
      Object(p) =>
        match p.get("id") {
          Some(String(pid)) => {
            if pid == "openclacky" {
              saw_openclacky = true
            }
            // default_model + models + base_url are always present.
            assert_true(p.get("default_model") is Some(String(_)))
            assert_true(p.get("models") is Some(Array(_)))
            assert_true(p.get("base_url") is Some(String(_)))
            if pid == "glm" {
              match p.get("endpoint_variants") {
                Some(Array(variants)) => {
                  @debug.assert_eq(variants.length(), 4)
                  saw_glm_variants = true
                }
                _ => assert_true(false)
              }
            }
          }
          _ => assert_true(false)
        }
      _ => assert_true(false)
    }
  }
  assert_true(saw_openclacky)
  assert_true(saw_glm_variants)
}
