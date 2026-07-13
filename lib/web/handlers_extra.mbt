///| Supplementary REST API handlers (P1-5 completion).
///
/// File-backed stores under ~/.mbopenclacky for the API groups that
/// were missing from the original contract:
///   - Memories CRUD      (/api/memories)
///   - Settings read/write (/api/settings)
///   - Share create/list    (/api/share)
///   - Model presets CRUD  (/api/models, custom user presets)
///   - Benchmark session model (/api/benchmark/sessions/:id/model)
///   - Session-scoped Time Machine points (/api/sessions/:id/time-machine)
///
/// NOTE: true session-scoped *Git* execution requires a chdir-style
/// capability not yet exposed by the git_exec layer, so it is deferred;
/// the global /api/git endpoints already cover git operations.

///|
/// Resolve a data file path under the config directory.
fn extra_path(filename : String) -> String? {
  match @utils.config_dir() {
    Some(dir) =>
      Some(@path.Path::join(@path.Path(dir), @path.Path(filename)).to_string())
    None => None
  }
}

///|
/// Empty JSON array with a concrete element type.
fn empty_arr() -> Array[Json] {
  []
}

///|
/// Load a JSON array from `path`, returning [] when missing/invalid.
fn load_array(path : String) -> Array[Json] {
  let content = @fs.read_file_to_string(path) catch { _ => return empty_arr() }
  if content.is_empty() {
    return empty_arr()
  }
  let parsed = @json.parse(content) catch { _ => return empty_arr() }
  match parsed {
    Array(arr) => arr
    _ => empty_arr()
  }
}

///|
/// Persist a JSON array to `path`, ensuring the config dir exists.
fn save_array(path : String, arr : Array[Json]) -> Result[Unit, String] {
  match @utils.config_dir() {
    Some(dir) => @utils.ensure_dir(dir)
    None => ()
  }
  @fs.write_string_to_file(path, Json::array(arr).stringify()) catch {
    e => return Err(e.to_string())
  }
  Ok(())
}

///|
/// Read a String field from a JSON object ("" when absent/invalid).
fn extra_json_str(j : Json, key : String) -> String {
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
/// JSON error body helpers.
fn bad_json() -> @core.HttpResponse {
  @core.HttpResponse::bad_request().json_value(
    Json::object({ "error": "Invalid JSON body".to_json() }),
  )
}

///|
fn err_no_config() -> @core.HttpResponse {
  @core.HttpResponse::internal_server_error().json_value(
    Json::object({ "error": "Config directory unavailable".to_json() }),
  )
}

///|
fn err_msg(msg : String) -> @core.HttpResponse {
  @core.HttpResponse::internal_server_error().json_value(
    Json::object({ "error": msg.to_json() }),
  )
}

///|
/// Parse a single query parameter value from a raw query string.
fn query_param(qs : String, key : String) -> String? {
  if qs.is_empty() {
    return None
  }
  let prefix = key + "="
  for p in qs.split("&") {
    let ps = p.to_owned()
    if ps.has_prefix(prefix) {
      return Some(ps[prefix.length():].to_owned())
    }
  }
  None
}

///|
/// Short unique id for new records.
fn extra_id() -> String {
  @agent.generate_session_id()[:12].to_owned()
}

///|
/// Current time in milliseconds.
fn now_ms() -> Int64 {
  @agent.current_time_ms()
}

///|
/// Extract a `:id` path parameter (returns "" when missing).
fn path_id(event : @crescent.Event) -> String {
  match event.param("id") {
    Some(v) => v.to_owned()
    None => ""
  }
}

// ── Memories ─────────────────────────────────────────────

///|
/// GET /api/memories -> list all memories.
pub fn handle_memories_get(
  _server_ref : Ref[WebServer],
  _event : @crescent.Event,
) -> @core.HttpResponse {
  match extra_path("memories.json") {
    Some(p) =>
      @core.HttpResponse::ok().json_value(
        Json::object({ "memories": Json::array(load_array(p)) }),
      )
    None => err_no_config()
  }
}

///|
/// POST /api/memories -> create {content, tags?}.
pub fn handle_memories_post(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let body : Json = event.req.body() catch { _ => return bad_json() }
  let content = extra_json_str(body, "content")
  if content.is_empty() {
    return @core.HttpResponse::bad_request().json_value(
      Json::object({ "error": "content required".to_json() }),
    )
  }
  match extra_path("memories.json") {
    Some(p) => {
      let arr = load_array(p)
      let id = extra_id()
      let tags = match body {
        Object(o) =>
          match o.get("tags") {
            Some(t) => t
            None => Json::array(empty_arr())
          }
        _ => Json::array(empty_arr())
      }
      let entry = Json::object({
        "id": id.to_json(),
        "content": content.to_json(),
        "tags": tags,
        "created_at": now_ms().to_json(),
      })
      arr.push(entry)
      match save_array(p, arr) {
        Ok(_) =>
          @core.HttpResponse::ok().json_value(
            Json::object({ "ok": true.to_json(), "id": id.to_json() }),
          )
        Err(e) => err_msg(e)
      }
    }
    None => err_no_config()
  }
}

///|
/// PUT /api/memories -> update by id {id, content?, tags?}.
pub fn handle_memories_put(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let body : Json = event.req.body() catch { _ => return bad_json() }
  let id = extra_json_str(body, "id")
  if id.is_empty() {
    return @core.HttpResponse::bad_request().json_value(
      Json::object({ "error": "id required".to_json() }),
    )
  }
  match extra_path("memories.json") {
    Some(p) => {
      let arr = load_array(p)
      let mut found = false
      for i = 0; i < arr.length(); i = i + 1 {
        match arr[i] {
          Object(o) =>
            match o.get("id") {
              Some(String(existing)) if existing == id => {
                let content = if extra_json_str(body, "content").is_empty() {
                  match o.get("content") {
                    Some(c) => c
                    None => "".to_json()
                  }
                } else {
                  extra_json_str(body, "content").to_json()
                }
                let tags = match body {
                  Object(bo) =>
                    if bo.contains("tags") {
                      match bo.get("tags") {
                        Some(t) => t
                        None => Json::array(empty_arr())
                      }
                    } else {
                      match o.get("tags") {
                        Some(t) => t
                        None => Json::array(empty_arr())
                      }
                    }
                  _ => Json::array(empty_arr())
                }
                arr[i] = Json::object({
                  "id": id.to_json(),
                  "content": content,
                  "tags": tags,
                  "created_at": match o.get("created_at") {
                    Some(c) => c
                    None => now_ms().to_json()
                  },
                })
                found = true
              }
              _ => ()
            }
          _ => ()
        }
      }
      if !found {
        return @core.HttpResponse::not_found().json_value(
          Json::object({ "error": "memory not found".to_json() }),
        )
      }
      match save_array(p, arr) {
        Ok(_) =>
          @core.HttpResponse::ok().json_value(
            Json::object({ "ok": true.to_json() }),
          )
        Err(e) => err_msg(e)
      }
    }
    None => err_no_config()
  }
}

///|
/// DELETE /api/memories?id=<id>.
pub fn handle_memories_delete(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let qs = match event.req.query_string() {
    Some(q) => q
    None => ""
  }
  let id = match query_param(qs, "id") {
    Some(v) => v
    None => ""
  }
  if id.is_empty() {
    return @core.HttpResponse::bad_request().json_value(
      Json::object({ "error": "id query parameter required".to_json() }),
    )
  }
  match extra_path("memories.json") {
    Some(p) => {
      let arr = load_array(p)
      let filtered = arr.filter(fn(e) {
        match e {
          Object(o) =>
            match o.get("id") {
              Some(String(existing)) => existing != id
              _ => true
            }
          _ => true
        }
      })
      match save_array(p, filtered) {
        Ok(_) =>
          @core.HttpResponse::ok().json_value(
            Json::object({ "ok": true.to_json() }),
          )
        Err(e) => err_msg(e)
      }
    }
    None => err_no_config()
  }
}

// ── Settings ───────────────────────────────────────────

///|
/// GET /api/settings -> stored settings object.
pub fn handle_settings_get(
  _server_ref : Ref[WebServer],
  _event : @crescent.Event,
) -> @core.HttpResponse {
  match extra_path("settings.json") {
    Some(p) => {
      let arr = load_array(p)
      for e in arr {
        match e {
          Object(_) => return @core.HttpResponse::ok().json_value(e)
          _ => ()
        }
      }
      @core.HttpResponse::ok().json_value(Json::object({}))
    }
    None => err_no_config()
  }
}

///|
/// PUT /api/settings -> merge & persist a settings object.
pub fn handle_settings_put(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let body : Json = event.req.body() catch { _ => return bad_json() }
  match body {
    Object(_) => ()
    _ =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": "settings object required".to_json() }),
      )
  }
  match extra_path("settings.json") {
    Some(p) => {
      let mut merged = body
      let arr = load_array(p)
      for e in arr {
        match e {
          Object(_) => merged = merge_objects(merged, e)
          _ => ()
        }
      }
      match save_array(p, [merged]) {
        Ok(_) =>
          @core.HttpResponse::ok().json_value(
            Json::object({ "ok": true.to_json(), "settings": merged }),
          )
        Err(e) => err_msg(e)
      }
    }
    None => err_no_config()
  }
}

///|
/// Shallow-merge two JSON objects (b overrides a).
fn merge_objects(a : Json, b : Json) -> Json {
  match (a, b) {
    (Object(oa), Object(ob)) => {
      let result : Map[String, Json] = oa
      for k, v in ob {
        result[k] = v
      }
      Json::object(result)
    }
    (_, Object(ob)) => Json::object(ob)
    _ => a
  }
}

// ── Share ──────────────────────────────────────────────

///|
/// GET /api/share -> list shares.
pub fn handle_share_get(
  _server_ref : Ref[WebServer],
  _event : @crescent.Event,
) -> @core.HttpResponse {
  match extra_path("shares.json") {
    Some(p) =>
      @core.HttpResponse::ok().json_value(
        Json::object({ "shares": Json::array(load_array(p)) }),
      )
    None => err_no_config()
  }
}

///|
/// POST /api/share -> create {type, target, content?}.
pub fn handle_share_post(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let body : Json = event.req.body() catch { _ => return bad_json() }
  let stype = extra_json_str(body, "type")
  let target = extra_json_str(body, "target")
  if stype.is_empty() || target.is_empty() {
    return @core.HttpResponse::bad_request().json_value(
      Json::object({ "error": "type and target required".to_json() }),
    )
  }
  match extra_path("shares.json") {
    Some(p) => {
      let arr = load_array(p)
      let id = extra_id()
      let content = extra_json_str(body, "content")
      let entry = Json::object({
        "id": id.to_json(),
        "type": stype.to_json(),
        "target": target.to_json(),
        "content": content.to_json(),
        "created_at": now_ms().to_json(),
      })
      arr.push(entry)
      match save_array(p, arr) {
        Ok(_) =>
          @core.HttpResponse::ok().json_value(
            Json::object({ "ok": true.to_json(), "id": id.to_json() }),
          )
        Err(e) => err_msg(e)
      }
    }
    None => err_no_config()
  }
}

// ── Model presets (custom) ──────────────────────────────

///|
/// GET /api/models -> list custom model presets.
pub fn handle_models_get(
  _server_ref : Ref[WebServer],
  _event : @crescent.Event,
) -> @core.HttpResponse {
  match extra_path("models.json") {
    Some(p) =>
      @core.HttpResponse::ok().json_value(
        Json::object({ "models": Json::array(load_array(p)) }),
      )
    None => err_no_config()
  }
}

///|
/// POST /api/models -> create {name, base_url, model, api_key?}.
pub fn handle_models_post(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let body : Json = event.req.body() catch { _ => return bad_json() }
  let name = extra_json_str(body, "name")
  let model = extra_json_str(body, "model")
  if name.is_empty() || model.is_empty() {
    return @core.HttpResponse::bad_request().json_value(
      Json::object({ "error": "name and model required".to_json() }),
    )
  }
  match extra_path("models.json") {
    Some(p) => {
      let arr = load_array(p)
      let id = extra_id()
      let entry = Json::object({
        "id": id.to_json(),
        "name": name.to_json(),
        "base_url": extra_json_str(body, "base_url").to_json(),
        "model": model.to_json(),
        "api_key": extra_json_str(body, "api_key").to_json(),
      })
      arr.push(entry)
      match save_array(p, arr) {
        Ok(_) =>
          @core.HttpResponse::ok().json_value(
            Json::object({ "ok": true.to_json(), "id": id.to_json() }),
          )
        Err(e) => err_msg(e)
      }
    }
    None => err_no_config()
  }
}

///|
/// PUT /api/models/:id -> update a custom model preset.
pub fn handle_models_put(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let id = path_id(event)
  if id.is_empty() {
    return @core.HttpResponse::bad_request().json_value(
      Json::object({ "error": "id path parameter required".to_json() }),
    )
  }
  let body : Json = event.req.body() catch { _ => return bad_json() }
  match extra_path("models.json") {
    Some(p) => {
      let arr = load_array(p)
      let mut found = false
      for i = 0; i < arr.length(); i = i + 1 {
        match arr[i] {
          Object(o) =>
            match o.get("id") {
              Some(String(existing)) if existing == id => {
                arr[i] = Json::object({
                  "id": id.to_json(),
                  "name": extra_json_str(body, "name").to_json(),
                  "base_url": extra_json_str(body, "base_url").to_json(),
                  "model": extra_json_str(body, "model").to_json(),
                  "api_key": extra_json_str(body, "api_key").to_json(),
                })
                found = true
              }
              _ => ()
            }
          _ => ()
        }
      }
      if !found {
        return @core.HttpResponse::not_found().json_value(
          Json::object({ "error": "model not found".to_json() }),
        )
      }
      match save_array(p, arr) {
        Ok(_) =>
          @core.HttpResponse::ok().json_value(
            Json::object({ "ok": true.to_json() }),
          )
        Err(e) => err_msg(e)
      }
    }
    None => err_no_config()
  }
}

///|
/// DELETE /api/models/:id.
pub fn handle_models_delete(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let id = path_id(event)
  if id.is_empty() {
    return @core.HttpResponse::bad_request().json_value(
      Json::object({ "error": "id path parameter required".to_json() }),
    )
  }
  match extra_path("models.json") {
    Some(p) => {
      let arr = load_array(p)
      let filtered = arr.filter(fn(e) {
        match e {
          Object(o) =>
            match o.get("id") {
              Some(String(existing)) => existing != id
              _ => true
            }
          _ => true
        }
      })
      match save_array(p, filtered) {
        Ok(_) =>
          @core.HttpResponse::ok().json_value(
            Json::object({ "ok": true.to_json() }),
          )
        Err(e) => err_msg(e)
      }
    }
    None => err_no_config()
  }
}

// ── Benchmark session model ─────────────────────────────

///|
/// GET /api/benchmark/sessions/:id/model.
pub fn handle_benchmark_model_get(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let session_id = path_id(event)
  if session_id.is_empty() {
    return @core.HttpResponse::bad_request().json_value(
      Json::object({ "error": "session id required".to_json() }),
    )
  }
  match extra_path("benchmark_models.json") {
    Some(p) => {
      let arr = load_array(p)
      for e in arr {
        match e {
          Object(o) =>
            match o.get("session_id") {
              Some(String(sid)) if sid == session_id =>
                return @core.HttpResponse::ok().json_value(e)
              _ => ()
            }
          _ => ()
        }
      }
      @core.HttpResponse::ok().json_value(
        Json::object({
          "session_id": session_id.to_json(),
          "model": "".to_json(),
        }),
      )
    }
    None => err_no_config()
  }
}

///|
/// POST /api/benchmark/sessions/:id/model {model}.
pub fn handle_benchmark_model_post(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let session_id = path_id(event)
  if session_id.is_empty() {
    return @core.HttpResponse::bad_request().json_value(
      Json::object({ "error": "session id required".to_json() }),
    )
  }
  let body : Json = event.req.body() catch { _ => return bad_json() }
  let model = extra_json_str(body, "model")
  if model.is_empty() {
    return @core.HttpResponse::bad_request().json_value(
      Json::object({ "error": "model required".to_json() }),
    )
  }
  match extra_path("benchmark_models.json") {
    Some(p) => {
      let arr = load_array(p)
      let mut found = false
      for i = 0; i < arr.length(); i = i + 1 {
        match arr[i] {
          Object(o) =>
            match o.get("session_id") {
              Some(String(sid)) if sid == session_id => {
                arr[i] = Json::object({
                  "session_id": session_id.to_json(),
                  "model": model.to_json(),
                  "updated_at": now_ms().to_json(),
                })
                found = true
              }
              _ => ()
            }
          _ => ()
        }
      }
      if !found {
        arr.push(
          Json::object({
            "session_id": session_id.to_json(),
            "model": model.to_json(),
            "updated_at": now_ms().to_json(),
          }),
        )
      }
      match save_array(p, arr) {
        Ok(_) =>
          @core.HttpResponse::ok().json_value(
            Json::object({ "ok": true.to_json(), "model": model.to_json() }),
          )
        Err(e) => err_msg(e)
      }
    }
    None => err_no_config()
  }
}

// ── Session-scoped Time Machine points ──────────────────

///|
/// GET /api/sessions/:id/time-machine -> list points.
pub fn handle_session_time_machine_get(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let session_id = path_id(event)
  if session_id.is_empty() {
    return @core.HttpResponse::bad_request().json_value(
      Json::object({ "error": "session id required".to_json() }),
    )
  }
  match extra_path("time_machine_" + session_id + ".json") {
    Some(p) =>
      @core.HttpResponse::ok().json_value(
        Json::object({
          "session_id": session_id.to_json(),
          "points": Json::array(load_array(p)),
        }),
      )
    None => err_no_config()
  }
}

///|
/// POST /api/sessions/:id/time-machine {description?} -> add a point.
pub fn handle_session_time_machine_post(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let session_id = path_id(event)
  if session_id.is_empty() {
    return @core.HttpResponse::bad_request().json_value(
      Json::object({ "error": "session id required".to_json() }),
    )
  }
  let body : Json = event.req.body() catch { _ => Json::object({}) }
  let description = extra_json_str(body, "description")
  match extra_path("time_machine_" + session_id + ".json") {
    Some(p) => {
      let arr = load_array(p)
      let id = extra_id()
      let entry = Json::object({
        "id": id.to_json(),
        "description": description.to_json(),
        "created_at": now_ms().to_json(),
      })
      arr.push(entry)
      match save_array(p, arr) {
        Ok(_) =>
          @core.HttpResponse::ok().json_value(
            Json::object({
              "ok": true.to_json(),
              "id": id.to_json(),
              "points": Json::array(arr),
            }),
          )
        Err(e) => err_msg(e)
      }
    }
    None => err_no_config()
  }
}
