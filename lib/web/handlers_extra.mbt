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
    e => return Err(@debug.to_string(e))
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
/// Read an optional String field from a JSON object (None when absent/invalid).
fn extra_json_str_opt(j : Json, key : String) -> String? {
  match j {
    Object(o) =>
      match o.get(key) {
        Some(String(s)) if !s.is_empty() => Some(s)
        _ => None
      }
    _ => None
  }
}

///|
/// Read a Bool field from a JSON object (false when absent/invalid).
fn extra_json_bool(j : Json, key : String) -> Bool {
  match j {
    Object(o) =>
      match o.get(key) {
        Some(True) => true
        Some(False) => false
        _ => false
      }
    _ => false
  }
}

///|
/// Check if a JSON object has a given key (regardless of value).
fn body_has_key(j : Json, key : String) -> Bool {
  match j {
    Object(o) => o.get(key) is Some(_)
    _ => false
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
/// Enrich a raw memory JSON object with derived fields (topic, description, preview, size).
fn enrich_memory_entry(raw : Json) -> Json {
  match raw {
    Object(o) => {
      let id = match o.get("id") {
        Some(String(s)) => s
        _ => ""
      }
      let content = match o.get("content") {
        Some(String(s)) => s
        _ => ""
      }
      // Topic: first tag or first line of content.
      let topic = match o.get("tags") {
        Some(Array(arr)) if arr.length() > 0 =>
          match arr[0] {
            String(s) => s
            _ => ""
          }
        _ =>
          if content.length() > 0 {
            let nl = content.find("\n")
            match nl {
              Some(n) => content[:n].to_owned()
              None => content
            }
          } else {
            ""
          }
      }
      // Preview: first 100 chars of content.
      let preview = if content.length() > 100 {
        content[:100].to_owned() + "..."
      } else {
        content
      }
      let size = content.length()
      let updated_at = match o.get("created_at") {
        Some(n) => n
        None => now_ms().to_json()
      }
      Json::object({
        "id": id.to_json(),
        "filename": (id + ".json").to_json(),
        "topic": topic.to_json(),
        "description": content.to_json(),
        "content": content.to_json(),
        "tags": match o.get("tags") {
          Some(t) => t
          None => Json::array(empty_arr())
        },
        "updated_at": updated_at,
        "created_at": match o.get("created_at") {
          Some(c) => c
          None => now_ms().to_json()
        },
        "size": size.to_json(),
        "preview": preview.to_json(),
      })
    }
    _ => raw
  }
}

///|
/// GET /api/memories -> list all memories (enriched with topic/description/preview).
pub fn handle_memories_get(
  _server_ref : Ref[WebServer],
  _event : @crescent.Event,
) -> @core.HttpResponse {
  match extra_path("memories.json") {
    Some(p) => {
      let raw_arr = load_array(p)
      let enriched : Array[Json] = []
      for e in raw_arr {
        enriched.push(enrich_memory_entry(e))
      }
      let dir = match @utils.config_dir() {
        Some(d) => d
        None => ""
      }
      @core.HttpResponse::ok().json_value(
        Json::object({
          "ok": true.to_json(),
          "dir": dir.to_json(),
          "memories": Json::array(enriched),
        }),
      )
    }
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
/// Normalize a memories :filename path param to a memory id
/// (accepts both "<id>" and "<id>.json").
fn memory_filename_to_id(filename : String) -> String {
  if filename.has_suffix(".json") {
    filename[:filename.length() - 5].to_owned()
  } else {
    filename
  }
}

///|
/// Load the memories array from disk; returns None when config dir missing.
fn load_memories_array() -> (String, Array[Json])? {
  match extra_path("memories.json") {
    Some(p) => Some((p, load_array(p)))
    None => None
  }
}

///|
/// GET /api/memories/:filename — fetch a single memory by filename.
pub fn handle_memory_file_get(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let id = match event.param("filename") {
    Some(p) => memory_filename_to_id(p.to_owned())
    None =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": "Missing parameter: filename".to_json() }),
      )
  }
  match load_memories_array() {
    Some((_, arr)) => {
      for e in arr {
        match e {
          Object(o) =>
            match o.get("id") {
              Some(String(existing)) if existing == id =>
                return @core.HttpResponse::ok().json_value(
                  Json::object({
                    "ok": true.to_json(),
                    "memory": enrich_memory_entry(e),
                  }),
                )
              _ => ()
            }
          _ => ()
        }
      }
      @core.HttpResponse::not_found().json_value(
        Json::object({ "error": "memory not found".to_json() }),
      )
    }
    None => err_no_config()
  }
}

///|
/// PUT /api/memories/:filename — update a single memory by filename.
/// Body: {content?, tags?}.
pub fn handle_memory_file_put(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let id = match event.param("filename") {
    Some(p) => memory_filename_to_id(p.to_owned())
    None =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": "Missing parameter: filename".to_json() }),
      )
  }
  let body : Json = event.req.body() catch { _ => return bad_json() }
  match load_memories_array() {
    Some((p, arr)) => {
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
/// DELETE /api/memories/:filename — delete a single memory by filename.
pub fn handle_memory_file_delete(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let id = match event.param("filename") {
    Some(p) => memory_filename_to_id(p.to_owned())
    None =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": "Missing parameter: filename".to_json() }),
      )
  }
  match load_memories_array() {
    Some((p, arr)) => {
      let mut found = false
      let filtered = arr.filter(fn(e) {
        match e {
          Object(o) =>
            match o.get("id") {
              Some(String(existing)) =>
                if existing == id {
                  found = true
                  false
                } else {
                  true
                }
              _ => true
            }
          _ => true
        }
      })
      if !found {
        return @core.HttpResponse::not_found().json_value(
          Json::object({ "error": "memory not found".to_json() }),
        )
      }
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
      @core.HttpResponse::ok().json_value(Json::object(Map([])))
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

// ── Session Benchmark (real LLM latency test) ──────────────────────

///|
/// POST /api/sessions/:id/benchmark.
/// Sends a minimal "Hi" prompt to every configured model and returns
/// per-model latency results so the frontend can display TTFT badges.
pub fn handle_session_benchmark(
  server_ref : Ref[WebServer],
  _event : @crescent.Event,
) -> @core.HttpResponse {
  let models = server_ref.val.config.models
  if models.is_empty() {
    return @core.HttpResponse::ok().json_value(
      Json::object({ "ok": true.to_json(), "results": Json::array([]) }),
    )
  }

  let results : Array[Json] = []

  for m in models {
    let model_id = m.id
    // Determine API type from config
    let api_type = if m.anthropic_format {
      @config.AnthropicMessages
    } else {
      @config.Providers::api_type_for(m.base_url)
    }
    let client = @client.Client::new(m.api_key, m.base_url, m.model, api_type)
    // Build a minimal request: single "Hi" message, no tools, 1 token
    let body_json = client.build_simple_request("Hi", m.model, 1)
    let url = client.request_url()
    let headers_map = client.request_headers()
    let headers_arr : Array[(String, String)] = []
    for k, v in headers_map {
      headers_arr.push((k, v))
    }
    let body_str = body_json.stringify()

    let t0 = @agent.current_time_ms()
    let http_result = @client.http_post(url, body_str, headers_arr, 30000)
    let t1 = @agent.current_time_ms()
    let elapsed = t1 - t0

    match http_result {
      Ok(http_resp) =>
        if http_resp.status_code >= 200 && http_resp.status_code < 300 {
          results.push(
            Json::object({
              "model_id": model_id.to_json(),
              "ok": true.to_json(),
              "ttft_ms": elapsed.to_json(),
            }),
          )
        } else {
          let err_msg = extract_err_snippet(http_resp.body)
          results.push(
            Json::object({
              "model_id": model_id.to_json(),
              "ok": false.to_json(),
              "ttft_ms": elapsed.to_json(),
              "error": err_msg.to_json(),
            }),
          )
        }
      Err(err) => {
        let err_msg = match err {
          @client.Timeout(_) => "timeout"
          @client.ConnectionFailed(_) => "connection failed"
          @client.ServerError(code, _) => "server error \{code}"
          @client.ClientError(code, _) => "client error \{code}"
          @client.AllHostsFailed(_) => "all hosts failed"
        }
        results.push(
          Json::object({
            "model_id": model_id.to_json(),
            "ok": false.to_json(),
            "ttft_ms": elapsed.to_json(),
            "error": err_msg.to_json(),
          }),
        )
      }
    }
  }

  @core.HttpResponse::ok().json_value(
    Json::object({ "ok": true.to_json(), "results": Json::array(results) }),
  )
}

///|
/// Extract a short error snippet from an API error response body.
fn extract_err_snippet(body : String) -> String {
  // Try to parse as JSON and extract "error" field
  let json = @json.parse(body) catch {
    _ => return body_snippet_local(body, 200)
  }
  match json {
    Object(o) =>
      match o.get("error") {
        Some(String(s)) => s
        Some(e) => @debug.to_string(e)
        None =>
          match o.get("message") {
            Some(String(s)) => s
            _ => body_snippet_local(body, 200)
          }
      }
    _ => body_snippet_local(body, 200)
  }
}

///|
fn body_snippet_local(body : String, max_chars : Int) -> String {
  let buf = StringBuilder::new()
  let mut count = 0
  let mut truncated = false
  for c in body {
    if count >= max_chars {
      truncated = true
      break
    }
    buf.write_char(c)
    count = count + 1
  }
  if truncated {
    buf.write_string("...")
  }
  buf.to_string()
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
  let body : Json = event.req.body() catch { _ => Json::object(Map([])) }
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

///|
/// GET /api/sessions/:id/time_machine/:task_id/diff — diff for a time machine point.
/// Returns a stub response; full task-snapshot diff requires deeper infra.
pub fn handle_session_time_machine_diff(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let session_id = path_id(event)
  if session_id.is_empty() {
    return @core.HttpResponse::bad_request().json_value(
      Json::object({ "error": "session id required".to_json() }),
    )
  }
  let task_id = match event.param("task_id") {
    Some(v) => v.to_owned()
    None => ""
  }
  @core.HttpResponse::ok().json_value(
    Json::object({
      "session_id": session_id.to_json(),
      "task_id": task_id.to_json(),
      "diff": "".to_json(),
      "available": false.to_json(),
    }),
  )
}

///|
/// POST /api/sessions/:id/time_machine/:task_id/restore_preview — restore preview stub.
pub fn handle_session_time_machine_restore_preview(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let session_id = path_id(event)
  if session_id.is_empty() {
    return @core.HttpResponse::bad_request().json_value(
      Json::object({ "error": "session id required".to_json() }),
    )
  }
  let task_id = match event.param("task_id") {
    Some(v) => v.to_owned()
    None => ""
  }
  @core.HttpResponse::ok().json_value(
    Json::object({
      "session_id": session_id.to_json(),
      "task_id": task_id.to_json(),
      "preview": "".to_json(),
      "available": false.to_json(),
    }),
  )
}

///|
/// POST /api/sessions/:id/time_machine/switch {task_id} -> switch to a task.
/// Looks up the task point in the session's time-machine JSON store.
/// Returns `{ok: true, message, task_id}` on success or
/// `{ok: false, error}` when the task is not found.
pub fn handle_session_time_machine_switch(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let session_id = path_id(event)
  if session_id.is_empty() {
    return @core.HttpResponse::bad_request().json_value(
      Json::object({ "error": "session id required".to_json() }),
    )
  }
  let body : Json = event.req.body() catch { _ => Json::object(Map([])) }
  let task_id = extra_json_str(body, "task_id")
  if task_id.is_empty() {
    return @core.HttpResponse::bad_request().json_value(
      Json::object({ "error": "task_id required".to_json() }),
    )
  }
  match extra_path("time_machine_" + session_id + ".json") {
    Some(p) => {
      let arr = load_array(p)
      let found = arr
        .iter()
        .find_first(fn(entry) {
          match entry {
            Object(o) =>
              match o.get("id") {
                Some(String(s)) => s == task_id
                _ => false
              }
            _ => false
          }
        })
      match found {
        Some(_) =>
          @core.HttpResponse::ok().json_value(
            Json::object({
              "ok": true.to_json(),
              "message": ("Switched to task " + task_id).to_json(),
              "task_id": task_id.to_json(),
            }),
          )
        None =>
          @core.HttpResponse::ok().json_value(
            Json::object({
              "ok": false.to_json(),
              "error": "Task not found".to_json(),
            }),
          )
      }
    }
    None => err_no_config()
  }
}

// ── Config/Models CRUD (web-parity-02) ──────────────────

///|
/// Persist the agent config to the default config file.
/// Returns Err with a message when the config path is unavailable or the
/// write fails — callers must surface this instead of silently succeeding
/// with an in-memory-only change.
fn persist_agent_config(config : @config.AgentConfig) -> Result[Unit, String] {
  match @utils.config_file() {
    Some(path) => {
      config.save(path) catch {
        e => return Err(@debug.to_string(e))
      }
      Ok(())
    }
    None => Err("Config file path unavailable")
  }
}

///|
/// 500 response for a failed config persistence.
fn err_config_persist(msg : String) -> @core.HttpResponse {
  @core.HttpResponse::internal_server_error().json_value(
    Json::object({
      "ok": false.to_json(),
      "error": "Failed to persist configuration".to_json(),
      "detail": msg.to_json(),
    }),
  )
}

///|
/// POST /api/config/models — Create a new model configuration.
/// Aligned with the original contract: body includes name, base_url, model,
/// api_key, anthropic_format, type.
pub fn handle_config_models_post(
  server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let body : Json = event.req.body() catch { _ => return bad_json() }
  // Required-field validation: model, base_url, api_key must all be non-empty.
  // Without this an empty/partial body would silently create a phantom empty
  // model row that breaks the config and clutters the settings UI.
  let model_str = extra_json_str(body, "model")
  let base_url_str = extra_json_str(body, "base_url")
  let api_key_str = extra_json_str(body, "api_key")
  if model_str.is_empty() || base_url_str.is_empty() || api_key_str.is_empty() {
    let missing : Array[String] = []
    if model_str.is_empty() {
      missing.push("model")
    }
    if base_url_str.is_empty() {
      missing.push("base_url")
    }
    if api_key_str.is_empty() {
      missing.push("api_key")
    }
    return @core.HttpResponse::bad_request().json_value(
      Json::object({
        "ok": false.to_json(),
        "error": ("Missing required field(s): " + missing.join(", ")).to_json(),
      }),
    )
  }
  let cfg = server_ref.val.config
  let new_id = extra_id()
  let mc = @config.ModelConfig::new(
    new_id, api_key_str, base_url_str, model_str,
  )
  // Honor frontend-supplied anthropic_format / type_ — without this,
  // adding a Claude model silently saves as an OpenAI one.
  mc.anthropic_format = extra_json_bool(body, "anthropic_format")
  mc.type_ = extra_json_str_opt(body, "type")
  cfg.models.push(mc)
  match persist_agent_config(cfg) {
    Ok(_) => ()
    Err(msg) => return err_config_persist(msg)
  }
  @core.HttpResponse::created().json_value(
    Json::object({
      "ok": true.to_json(),
      "model": mc.to_json(),
      "current_index": (cfg.models.length() - 1).to_json(),
    }),
  )
}

///|
/// PATCH /api/config/models/:id — Update an existing model configuration.
pub fn handle_config_models_patch(
  server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let id = path_id(event)
  if id.is_empty() {
    return @core.HttpResponse::bad_request().json_value(
      Json::object({ "error": "id required".to_json() }),
    )
  }
  let body : Json = event.req.body() catch { _ => return bad_json() }
  let cfg = server_ref.val.config
  let mut found = false
  for i = 0; i < cfg.models.length(); i = i + 1 {
    let m = cfg.models[i]
    if m.id == id {
      let base_url = if extra_json_str(body, "base_url").is_empty() {
        m.base_url
      } else {
        extra_json_str(body, "base_url")
      }
      let model = if extra_json_str(body, "model").is_empty() {
        m.model
      } else {
        extra_json_str(body, "model")
      }
      let api_key = if extra_json_str(body, "api_key").is_empty() {
        m.api_key
      } else {
        extra_json_str(body, "api_key")
      }
      // Build a new ModelConfig that honors the frontend-supplied
      // anthropic_format and type_, instead of hard-resetting them.
      // If the body omitted these fields, fall back to the existing
      // values so an unrelated PATCH can't silently drop them.
      let anthropic_format = if body_has_key(body, "anthropic_format") {
        extra_json_bool(body, "anthropic_format")
      } else {
        m.anthropic_format
      }
      let type_ = if body_has_key(body, "type") {
        extra_json_str_opt(body, "type")
      } else {
        m.type_
      }
      let updated = @config.ModelConfig::new(id, api_key, base_url, model)
      updated.anthropic_format = anthropic_format
      updated.type_ = type_
      cfg.models[i] = updated
      found = true
      break
    }
  }
  if !found {
    return @core.HttpResponse::not_found().json_value(
      Json::object({ "error": "model not found".to_json() }),
    )
  }
  match persist_agent_config(cfg) {
    Ok(_) => ()
    Err(msg) => return err_config_persist(msg)
  }
  @core.HttpResponse::ok().json_value(Json::object({ "ok": true.to_json() }))
}

///|
/// DELETE /api/config/models/:id — Remove a model configuration.
pub fn handle_config_models_delete(
  server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let id = path_id(event)
  if id.is_empty() {
    return @core.HttpResponse::bad_request().json_value(
      Json::object({ "error": "id required".to_json() }),
    )
  }
  let cfg = server_ref.val.config
  let before = cfg.models.length()
  let filtered : Array[@config.ModelConfig] = []
  for m in cfg.models {
    if m.id != id {
      filtered.push(m)
    }
  }
  if filtered.length() == before {
    return @core.HttpResponse::not_found().json_value(
      Json::object({ "error": "model not found".to_json() }),
    )
  }
  cfg.models = filtered
  // Update current_model_id if the deleted model was active.
  match cfg.current_model_id {
    Some(cid) if cid == id => cfg.current_model_id = None
    _ => ()
  }
  match persist_agent_config(cfg) {
    Ok(_) => ()
    Err(msg) => return err_config_persist(msg)
  }
  @core.HttpResponse::ok().json_value(Json::object({ "ok": true.to_json() }))
}

///|
/// POST /api/config/models/:id/default — Set a model as the default.
pub fn handle_config_models_set_default(
  server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let id = path_id(event)
  if id.is_empty() {
    return @core.HttpResponse::bad_request().json_value(
      Json::object({ "error": "id required".to_json() }),
    )
  }
  let cfg = server_ref.val.config
  let mut found = false
  for m in cfg.models {
    if m.id == id {
      found = true
      break
    }
  }
  if !found {
    return @core.HttpResponse::not_found().json_value(
      Json::object({ "error": "model not found".to_json() }),
    )
  }
  cfg.current_model_id = Some(id)
  match persist_agent_config(cfg) {
    Ok(_) => ()
    Err(msg) => return err_config_persist(msg)
  }
  @core.HttpResponse::ok().json_value(
    Json::object({ "ok": true.to_json(), "current_model_id": id.to_json() }),
  )
}

///|
/// GET /api/providers — List supported LLM providers.
/// Returns provider metadata for the frontend settings page.
pub fn handle_providers_list(
  _server_ref : Ref[WebServer],
  _event : @crescent.Event,
) -> @core.HttpResponse {
  // Serve the real preset registry — the frontend consumes default_model,
  // models, endpoint_variants, name_key and website_url for quick setup,
  // regional endpoint dropdowns and "get API key" links (upstream
  // api_list_providers shape).
  let providers : Array[Json] = []
  for preset in @config.Providers::all() {
    let obj : Map[String, Json] = Map([])
    obj["id"] = preset.id.to_json()
    obj["name"] = preset.name.to_json()
    match preset.name_key {
      Some(k) => obj["name_key"] = k.to_json()
      None => ()
    }
    obj["base_url"] = preset.base_url.to_json()
    obj["default_model"] = preset.default_model.to_json()
    obj["models"] = preset.models.to_json()
    if !preset.endpoint_variants.is_empty() {
      let variants : Array[Json] = []
      for v in preset.endpoint_variants {
        let vobj : Map[String, Json] = Map([])
        vobj["label"] = v.label.to_json()
        match v.label_key {
          Some(k) => vobj["label_key"] = k.to_json()
          None => ()
        }
        vobj["base_url"] = v.base_url.to_json()
        match v.region {
          Some(r) => vobj["region"] = r.to_json()
          None => ()
        }
        variants.push(Json::object(vobj))
      }
      obj["endpoint_variants"] = variants.to_json()
    }
    match preset.website_url {
      Some(u) => obj["website_url"] = u.to_json()
      None => ()
    }
    providers.push(Json::object(obj))
  }
  @core.HttpResponse::ok().json_value(
    Json::object({ "providers": providers.to_json() }),
  )
}

///|
/// POST /api/upload — Multipart file upload alias.
/// Accepts multipart/form-data with field "file".
/// Returns {ok, name, path}.
pub fn handle_upload_alias(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  // Reuse the existing files upload handler logic.
  handle_files_upload_impl(event)
}

///|
/// Shared implementation for file upload.
/// Parses the multipart/form-data body, extracts the first file part, and
/// saves it, returning {ok, name, path}.
fn handle_files_upload_impl(event : @crescent.Event) -> @core.HttpResponse {
  let body = event.req.raw_body
  if body.length() == 0 {
    return @core.HttpResponse::bad_request().json_value(
      Json::object({ "error": "Empty request body".to_json() }),
    )
  }
  let content_type = event.req.get_header("Content-Type").unwrap_or("")
  let (filename, content) = match parse_multipart_file(body, content_type) {
    Some(pair) => pair
    None =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({
          "error": "No file part found in multipart body".to_json(),
        }),
      )
  }
  // Sanitize: strip directory components and reject traversal sequences.
  let save_name = sanitize_upload_filename(filename)
  if save_name.is_empty() {
    return @core.HttpResponse::bad_request().json_value(
      Json::object({ "error": "Invalid file name".to_json() }),
    )
  }
  // Save to a temp location under the config dir.
  let upload_dir = match @utils.config_dir() {
    Some(dir) =>
      @path.Path::join(@path.Path(dir), @path.Path("uploads")).to_string()
    None => "uploads"
  }
  match @utils.ensure_dir(upload_dir) {
    _ => ()
  }
  let save_path = @path.Path::join(
    @path.Path(upload_dir),
    @path.Path(save_name),
  ).to_string()
  @fs.write_bytes_to_file(save_path, content) catch {
    e =>
      return @core.HttpResponse::internal_server_error().json_value(
        Json::object({ "error": @debug.to_string(e).to_json() }),
      )
  }
  @core.HttpResponse::ok().json_value(
    Json::object({
      "ok": true.to_json(),
      "name": save_name.to_json(),
      "path": save_path.to_json(),
    }),
  )
}

///|
/// Reduce an uploaded file name to a safe basename.
/// Strips any directory components and rejects traversal sequences.
fn sanitize_upload_filename(name : String) -> String {
  let mut base = name
  match base.rev_find("/") {
    Some(i) => base = base[i + 1:].to_owned()
    None => ()
  }
  match base.rev_find("\\") {
    Some(i) => base = base[i + 1:].to_owned()
    None => ()
  }
  if base.is_empty() || base.contains("..") {
    ""
  } else {
    base
  }
}

///|
/// Find the first occurrence of an ASCII `needle` in `hay` at or after `from`.
fn bytes_find(hay : Bytes, needle : String, from : Int) -> Int? {
  let n = needle.length()
  if n == 0 || from < 0 || hay.length() < from + n {
    return None
  }
  let mut i = from
  while i + n <= hay.length() {
    let mut matched = true
    for j = 0; j < n; j = j + 1 {
      if hay[i + j].to_int() != needle[j].to_int() {
        matched = false
        break
      }
    }
    if matched {
      return Some(i)
    }
    i = i + 1
  }
  None
}

///|
/// Parse a multipart/form-data body and return the first file part as
/// (filename, content). Returns None when the request is not multipart or
/// contains no file part.
fn parse_multipart_file(
  body : Bytes,
  content_type : String,
) -> (String, Bytes)? {
  let bmarker = "boundary="
  let bs = match content_type.find(bmarker) {
    Some(s) => s
    None => return None
  }
  let mut boundary = content_type[bs + bmarker.length():].to_owned()
  // Boundary ends at ';', whitespace, or end of header; strip quotes.
  let mut end = boundary.length()
  for i = 0; i < boundary.length(); i = i + 1 {
    let c = boundary[i]
    if c == ';' || c == ' ' || c == '\t' {
      end = i
      break
    }
  }
  boundary = boundary[:end].to_owned()
  if boundary.has_prefix("\"") &&
    boundary.has_suffix("\"") &&
    boundary.length() > 1 {
    boundary = boundary[1:boundary.length() - 1].to_owned()
  }
  if boundary.is_empty() {
    return None
  }
  let delimiter = "--" + boundary
  // First part starts after the first delimiter line.
  let p0 = match bytes_find(body, delimiter, 0) {
    Some(p) => p
    None => return None
  }
  let headers_start = p0 + delimiter.length() + 2 // skip "\r\n"
  let hdr_end = match bytes_find(body, "\r\n\r\n", headers_start) {
    Some(p) => p
    None => return None
  }
  // Extract filename from the part headers.
  let headers = @utf8.decode(body[headers_start:hdr_end].to_owned()) catch {
    _ => return None
  }
  let filename = extract_multipart_filename(headers)
  if filename.is_empty() {
    return None
  }
  let content_start = hdr_end + 4
  let closing = "\r\n" + delimiter
  let content_end = match bytes_find(body, closing, content_start) {
    Some(p) => p
    None => return None
  }
  if content_end < content_start {
    return None
  }
  let content = Bytes::makei(content_end - content_start, fn(i) {
    body[content_start + i]
  })
  Some((filename, content))
}

///|
/// Extract filename from Content-Type/Content-Disposition header.
fn extract_multipart_filename(content_type : String) -> String {
  // Simple extraction: look for filename="..." in the header.
  let marker = "filename=\""
  let start = content_type.find(marker)
  match start {
    Some(s) => {
      let after = s + marker.length()
      let end = content_type[after:].to_owned().find("\"")
      match end {
        Some(e) => content_type[after:after + e].to_owned()
        None => ""
      }
    }
    None => ""
  }
}

// ── Session pinned state (file-backed) ──────────────────

///|
/// Load the pinned state map for all sessions.
fn load_pinned_map() -> Map[String, Bool] {
  match extra_path("session_pinned.json") {
    Some(p) => {
      let content = @fs.read_file_to_string(p) catch { _ => return Map([]) }
      if content.is_empty() {
        return Map([])
      }
      let parsed = @json.parse(content) catch { _ => return Map([]) }
      match parsed {
        Object(o) => {
          let result : Map[String, Bool] = Map([])
          for k, v in o {
            match v {
              True => result[k] = true
              False => result[k] = false
              _ => ()
            }
          }
          result
        }
        _ => Map([])
      }
    }
    None => Map([])
  }
}

///|
/// Save the pinned state map.
fn save_pinned_map(m : Map[String, Bool]) -> Result[Unit, String] {
  let obj : Map[String, Json] = Map([])
  for k, v in m {
    obj[k] = v.to_json()
  }
  match extra_path("session_pinned.json") {
    Some(p) => {
      match @utils.config_dir() {
        Some(dir) => @utils.ensure_dir(dir)
        None => ()
      }
      @fs.write_string_to_file(p, Json::object(obj).stringify()) catch {
        e => return Err(@debug.to_string(e))
      }
      Ok(())
    }
    None => Err("Config directory unavailable")
  }
}

// ── Settings alias (/api/config/settings) ─────────────────

///|
/// GET /api/config/settings — advanced settings, flat shape.
/// Mirrors Ruby `api_get_settings`: `{ ok, enable_compression,
/// enable_prompt_caching, memory_update_enabled, proxy_url }`, read directly
/// from the live `@config.AgentConfig` (the four switches are real config
/// fields, not a storage-JSON side channel).
fn handle_config_settings_get(
  server_ref : Ref[WebServer],
  _event : @crescent.Event,
) -> @core.HttpResponse {
  let cfg = server_ref.val.config
  @core.HttpResponse::ok().json_value(
    Json::object({
      "ok": true.to_json(),
      "enable_compression": cfg.enable_compression.to_json(),
      "enable_prompt_caching": cfg.enable_prompt_caching.to_json(),
      "memory_update_enabled": cfg.memory_update_enabled.to_json(),
      "proxy_url": cfg.proxy_url.to_json(),
    }),
  )
}

///|
/// PATCH /api/config/settings — update advanced settings (partial update).
/// Mirrors Ruby `api_update_settings`: only the four known switches are
/// applied, the config is persisted, and the response is `{ ok: true }`.
fn handle_config_settings_patch(
  server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let body : Json = event.req.body() catch { _ => return bad_json() }
  let obj = match body {
    Object(o) => o
    _ =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": "settings object required".to_json() }),
      )
  }
  let cfg = server_ref.val.config
  fn bool_field(key : String) -> Bool? {
    match obj.get(key) {
      Some(True) => Some(true)
      Some(False) => Some(false)
      _ => None
    }
  }

  match bool_field("enable_compression") {
    Some(v) => cfg.enable_compression = v
    None => ()
  }
  match bool_field("enable_prompt_caching") {
    Some(v) => cfg.enable_prompt_caching = v
    None => ()
  }
  match bool_field("memory_update_enabled") {
    Some(v) => cfg.memory_update_enabled = v
    None => ()
  }
  match obj.get("proxy_url") {
    Some(String(s)) => cfg.proxy_url = s.trim().to_owned()
    _ => ()
  }
  match persist_agent_config(cfg) {
    Ok(_) =>
      @core.HttpResponse::ok().json_value(
        Json::object({ "ok": true.to_json() }),
      )
    Err(msg) => return err_config_persist(msg)
  }
}

// ── Telemetry (noop) ──────────────────────────────────

///|
/// POST /api/telemetry — accept and discard telemetry events (204 No Content).
fn handle_telemetry_noop(
  _server_ref : Ref[WebServer],
  _event : @crescent.Event,
) -> @core.HttpResponse {
  @core.HttpResponse::no_content()
}
