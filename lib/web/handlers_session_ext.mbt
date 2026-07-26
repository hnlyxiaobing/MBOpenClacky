///| Extended session REST API handlers.
/// Provides endpoints for session export, fork, rename, and message history.
/// These complement the core session CRUD in handlers.mbt.

///|
/// Load session data from disk, falling back to an in-memory active agent
/// when the on-disk file is missing. Mirrors the existence check in
/// `handle_ws_subscribe` (disk OR memory): a session whose initial
/// `save_session` silently failed (handle_create_session swallows the IO
/// error) or whose file was pruned by `enforce_session_cap` (deletes disk
/// but not active_agents) is still reachable here, so switching its
/// model/sub-model/reasoning effort does not fail with "Session not found".
/// Returns None only when the session exists neither on disk nor in memory.
fn load_session_or_active(
  server_ref : Ref[WebServer],
  id : String,
) -> @agent.SessionData? {
  match @agent.load_session(id) {
    Some(d) => Some(d)
    None =>
      match server_ref.val.active_agents.get(id) {
        Some(agent) => Some(agent.to_session_data())
        None => None
      }
  }
}

// ── Session Extension Handlers ────────────────────────────────────

///|
/// POST /api/sessions/:id/export — Export a session as a JSON document.
/// Returns the full SessionData including all messages and metadata.
fn handle_session_export(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let id = match event.param("id") {
    Some(p) => p.to_owned()
    None =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": "Missing parameter: id".to_json() }),
      )
  }
  match @agent.load_session(id) {
    Some(data) =>
      @core.HttpResponse::ok().json_value(
        Json::object({
          "session": data.to_json(),
          "exported_at": @agent.current_timestamp_iso().to_json(),
          "format_version": (1).to_json(),
        }),
      )
    None =>
      @core.HttpResponse::not_found().json_value(
        Json::object({ "error": "Session not found".to_json() }),
      )
  }
}

///|
/// POST /api/sessions/:id/export?format=zip — Export a session as a ZIP archive.
/// Returns the ZIP file as binary download.
fn handle_session_export_zip(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let id = match event.param("id") {
    Some(p) => p.to_owned()
    None =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": "Missing parameter: id".to_json() }),
      )
  }
  match @agent.export_session_zip(id) {
    Ok(zip_data) =>
      @core.HttpResponse::ok()
      .header("Content-Type", "application/zip")
      .header("Content-Disposition", "attachment; filename=" + id + ".zip")
      .body(zip_data)
    Err(msg) =>
      @core.HttpResponse::internal_server_error().json_value(
        Json::object({ "error": msg.to_json() }),
      )
  }
}

///|
/// POST /api/sessions/:id/fork — Create a fork (copy) of an existing session.
/// The forked session receives a new ID, reset statistics, and a forked_from reference.
fn handle_session_fork(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let id = match event.param("id") {
    Some(p) => p.to_owned()
    None =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": "Missing parameter: id".to_json() }),
      )
  }
  match @agent.fork_session(id) {
    Ok(forked) => {
      let forked_json = forked.to_json()
      // Fork returns metadata only; strip messages to avoid leaking the system prompt.
      match forked_json {
        Json::Object(obj) => ignore(obj.remove("messages"))
        _ => ()
      }
      @core.HttpResponse::created().json_value(
        Json::object({
          "forked_session": forked_json,
          "source_session_id": id.to_json(),
        }),
      )
    }
    Err(msg) =>
      @core.HttpResponse::not_found().json_value(
        Json::object({ "error": msg.to_json() }),
      )
  }
}

///|
/// PATCH /api/sessions/:id/rename — Rename a session.
/// crescent supports PATCH (route is registered with s.patch).
/// Expected body: {"name": "New Session Name"}
fn handle_session_rename(
  server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let id = match event.param("id") {
    Some(p) => p.to_owned()
    None =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": "Missing parameter: id".to_json() }),
      )
  }
  let j : Json = event.req.body() catch {
    _ =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": "Invalid JSON body".to_json() }),
      )
  }
  let new_name : String = match j {
    Object(obj) =>
      match obj.get("name") {
        Some(String(n)) => n
        _ =>
          return @core.HttpResponse::bad_request().json_value(
            Json::object({ "error": "Missing 'name' field".to_json() }),
          )
      }
    _ =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": "Invalid JSON body".to_json() }),
      )
  }
  match @agent.load_session(id) {
    Some(data) => {
      let old_name = data.name
      let updated = @agent.SessionData::{
        session_id: data.session_id,
        name: new_name,
        messages: data.messages,
        stats: data.stats,
        working_dir: data.working_dir,
        created_at: data.created_at,
        source: data.source,
        reasoning_effort: data.reasoning_effort,
        model_name: data.model_name,
        channel_info: data.channel_info,
        latest_latency_ms: data.latest_latency_ms,
        latest_ttft_ms: data.latest_ttft_ms,
        time_machine: data.time_machine,
        pending_error_rollback: data.pending_error_rollback,
        model_base_url: data.model_base_url,
        last_status: data.last_status,
        last_error: data.last_error,
        error_code: data.error_code,
        top_up_url: data.top_up_url,
        raw_message: data.raw_message,
        forked_from: data.forked_from,
        chunk_count: data.chunk_count,
        agent_profile: data.agent_profile,
        sub_model: data.sub_model,
      }
      // Sync the in-memory agent's name so a subsequent run does not
      // overwrite the renamed session file with the old name.
      if new_name != old_name {
        match server_ref.val.active_agents.get(id) {
          Some(agent) => agent.rename(new_name)
          None => ()
        }
      }
      @agent.save_session(updated) catch {
        _ =>
          return @core.HttpResponse::internal_server_error().json_value(
            Json::object({ "error": "Failed to save session".to_json() }),
          )
      }
      // Broadcast session_renamed via WS so the sidebar updates in real time.
      let hub = server_ref.val.hub
      hub.broadcast_session(
        id,
        @protocol.build_session_renamed_event(id, new_name),
      )
      @core.HttpResponse::ok().json_value(
        Json::object({ "ok": true.to_json(), "name": new_name.to_json() }),
      )
    }
    None =>
      @core.HttpResponse::not_found().json_value(
        Json::object({ "error": "Session not found".to_json() }),
      )
  }
}

///|
/// PATCH /api/sessions/:id/working_dir — Update a session's working directory.
/// Expected body: {"working_dir": "sub/dir"}.
/// Rejects path traversal ("..") and absolute paths outside the configured
/// working directory. Relative paths are always accepted.
fn handle_update_working_dir(
  server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let id = match event.param("id") {
    Some(p) => p.to_owned()
    None =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": "Missing parameter: id".to_json() }),
      )
  }
  let j : Json = event.req.body() catch {
    _ =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": "Invalid JSON body".to_json() }),
      )
  }
  let new_dir : String = match j {
    Object(obj) =>
      match obj.get("working_dir") {
        Some(String(d)) => d
        _ =>
          return @core.HttpResponse::bad_request().json_value(
            Json::object({ "error": "Missing 'working_dir' field".to_json() }),
          )
      }
    _ =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": "Invalid JSON body".to_json() }),
      )
  }
  // Path safety: reject traversal and empty paths (reuses files API validator).
  match validate_path(new_dir) {
    Err(msg) =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": msg.to_json() }),
      )
    Ok(_) => ()
  }
  // Reject absolute paths outside the configured working directory.
  if wd_is_absolute(new_dir) {
    match server_ref.val.config.default_working_dir {
      Some(cfg_dir) =>
        if !wd_is_within_dir(cfg_dir, new_dir) {
          return @core.HttpResponse::bad_request().json_value(
            Json::object({
              "error": "Absolute working_dir must be within the configured working directory".to_json(),
            }),
          )
        }
      None => ()
    }
  }
  match @agent.load_session(id) {
    Some(data) => {
      let updated = @agent.SessionData::{
        session_id: data.session_id,
        name: data.name,
        messages: data.messages,
        stats: data.stats,
        working_dir: new_dir,
        created_at: data.created_at,
        source: data.source,
        reasoning_effort: data.reasoning_effort,
        model_name: data.model_name,
        channel_info: data.channel_info,
        latest_latency_ms: data.latest_latency_ms,
        latest_ttft_ms: data.latest_ttft_ms,
        time_machine: data.time_machine,
        pending_error_rollback: data.pending_error_rollback,
        model_base_url: data.model_base_url,
        last_status: data.last_status,
        last_error: data.last_error,
        error_code: data.error_code,
        top_up_url: data.top_up_url,
        raw_message: data.raw_message,
        forked_from: data.forked_from,
        chunk_count: data.chunk_count,
        agent_profile: data.agent_profile,
        sub_model: data.sub_model,
      }
      @agent.save_session(updated) catch {
        _ =>
          return @core.HttpResponse::internal_server_error().json_value(
            Json::object({ "error": "Failed to save session".to_json() }),
          )
      }
      @core.HttpResponse::ok().json_value(
        Json::object({
          "session_id": id.to_json(),
          "working_dir": new_dir.to_json(),
        }),
      )
    }
    None =>
      @core.HttpResponse::not_found().json_value(
        Json::object({ "error": "Session not found".to_json() }),
      )
  }
}

///|
/// Heuristic check for whether a path is absolute.
/// Recognizes Unix absolute paths ("/...") and Windows drive paths ("C:\..." / "C:/...").
fn wd_is_absolute(p : String) -> Bool {
  if p.has_prefix("/") {
    return true
  }
  if p.length() >= 3 && p[1] == ':' && (p[2] == '\\' || p[2] == '/') {
    return true
  }
  false
}

///|
/// Check whether `target` equals or is nested under `dir`.
/// Both paths are treated as absolute; separators are normalized to "/".
fn wd_is_within_dir(dir : String, target : String) -> Bool {
  let d = wd_normalize_sep(dir)
  let t = wd_normalize_sep(target)
  if d.is_empty() || t.is_empty() {
    return false
  }
  if t == d {
    return true
  }
  let prefixed = if d.has_suffix("/") { d } else { d + "/" }
  t.has_prefix(prefixed)
}

///|
/// Normalize path separators ("\" -> "/") for cross-platform comparison.
fn wd_normalize_sep(p : String) -> String {
  let chars = p.to_array()
  for i = 0; i < chars.length(); i = i + 1 {
    if chars[i] == '\\' {
      chars[i] = '/'
    }
  }
  String::from_array(chars)
}

///|

///|
/// GET /api/sessions/:id/messages — Retrieve the message history for a session.
/// Supports `limit` (default 100) and `before` (timestamp cursor) query params.
/// Returns the WS-isomorphic contract shape {events, has_more}.
fn handle_session_messages(
  server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let id = match event.param("id") {
    Some(p) => p.to_owned()
    None =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": "Missing parameter: id".to_json() }),
      )
  }
  // Parse optional pagination params.
  let limit = match event.req.get_query("limit") {
    Some(s) => {
      let n = @string.parse_int(s) catch { _ => 0 }
      if n > 0 {
        n
      } else {
        100
      }
    }
    None => 100
  }
  let before = event.req.get_query("before")
  let messages = match @agent.load_session(id) {
    Some(data) => Some(data.messages)
    None =>
      // Fall back to the in-memory agent for sessions not yet persisted.
      match server_ref.val.active_agents.get(id) {
        Some(agent) => Some(agent.to_session_data().messages)
        None => None
      }
  }
  match messages {
    Some(msgs) => {
      let history = @protocol.build_messages_history(id, msgs, limit~, before~)
      @core.HttpResponse::ok().json_value(history)
    }
    None =>
      @core.HttpResponse::not_found().json_value(
        Json::object({ "error": "Session not found".to_json() }),
      )
  }
}

///|
/// POST /api/sessions/import — Import a session from a ZIP upload.
/// Expects multipart/form-data with a "file" field containing the ZIP.
fn handle_session_import(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  // Get the raw body as bytes
  let body = event.req.raw_body
  if body.length() == 0 {
    return @core.HttpResponse::bad_request().json_value(
      Json::object({ "error": "Empty request body".to_json() }),
    )
  }

  // Try to import the session from the ZIP data
  match @agent.import_session_zip(body) {
    Ok(session_data) =>
      @core.HttpResponse::created().json_value(
        Json::object({
          "session": session_data.to_json(),
          "message": "Session imported successfully".to_json(),
        }),
      )
    Err(msg) =>
      @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": msg.to_json() }),
      )
  }
}

///|
/// POST /api/sessions/import-all — Import multiple sessions from a ZIP upload.
/// Expects the ZIP to contain sessions in "sessions/<id>.json" format.
fn handle_sessions_import_all(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  // Get the raw body as bytes
  let body = event.req.raw_body
  if body.length() == 0 {
    return @core.HttpResponse::bad_request().json_value(
      Json::object({ "error": "Empty request body".to_json() }),
    )
  }

  // Try to import sessions from the ZIP data
  match @agent.import_sessions_zip(body) {
    Ok(count) =>
      @core.HttpResponse::ok().json_value(
        Json::object({
          "imported_count": count.to_json(),
          "message": "Sessions imported successfully".to_json(),
        }),
      )
    Err(msg) =>
      @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": msg.to_json() }),
      )
  }
}

///|
/// GET /api/sessions/export-all — Export all sessions as a ZIP archive.
/// Returns the ZIP file as binary download.
fn handle_sessions_export_all(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  ignore(event)
  match @agent.export_all_sessions_zip() {
    Ok(zip_data) =>
      @core.HttpResponse::ok()
      .header("Content-Type", "application/zip")
      .header("Content-Disposition", "attachment; filename=all_sessions.zip")
      .body(zip_data)
    Err(msg) =>
      @core.HttpResponse::internal_server_error().json_value(
        Json::object({ "error": msg.to_json() }),
      )
  }
}

// ── Web-Parity-02 Session Handlers ──────────────────────────────

///|
/// GET /api/sessions/:id/export — Export session as ZIP binary download.
/// Aligned with the original frontend contract (GET, Content-Disposition: attachment).
fn handle_session_export_zip_get(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let id = match event.param("id") {
    Some(p) => p.to_owned()
    None =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": "Missing parameter: id".to_json() }),
      )
  }
  match @agent.export_session_zip(id) {
    Ok(zip_data) =>
      @core.HttpResponse::ok()
      .header("Content-Type", "application/zip")
      .header("Content-Disposition", "attachment; filename=" + id + ".zip")
      .body(zip_data)
    Err(msg) =>
      @core.HttpResponse::internal_server_error().json_value(
        Json::object({ "error": msg.to_json() }),
      )
  }
}

///|
/// PATCH /api/sessions/:id — Update session name and/or pinned status.
/// Body: {"name": "...", "pinned": true/false} (either field optional).
/// Broadcasts session_updated event via the hub.
fn handle_session_patch(
  server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let id = match event.param("id") {
    Some(p) => p.to_owned()
    None =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": "Missing parameter: id".to_json() }),
      )
  }
  let j : Json = event.req.body() catch {
    _ =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": "Invalid JSON body".to_json() }),
      )
  }
  match @agent.load_session(id) {
    Some(data) => {
      let obj = match j {
        Object(o) => o
        _ =>
          return @core.HttpResponse::bad_request().json_value(
            Json::object({ "error": "Invalid JSON body".to_json() }),
          )
      }
      let mut changed = false
      // Apply name change.
      let new_name = match obj.get("name") {
        Some(String(n)) => {
          changed = true
          n
        }
        _ => data.name
      }
      // Apply pinned change (stored separately, not in SessionData).
      let pinned_val : Json = match obj.get("pinned") {
        Some(v) => {
          changed = true
          // Persist the pinned flag to the file-backed map.
          let pinned_bool = match v {
            True => Some(true)
            False => Some(false)
            _ => None
          }
          match pinned_bool {
            Some(b) => {
              let pinned_map = load_pinned_map()
              pinned_map[id] = b
              match save_pinned_map(pinned_map) {
                Ok(_) => ()
                Err(msg) =>
                  return @core.HttpResponse::internal_server_error().json_value(
                    Json::object({
                      "error": "Failed to persist pinned state".to_json(),
                      "detail": msg.to_json(),
                    }),
                  )
              }
            }
            None => ()
          }
          v
        }
        _ => Json::null()
      }
      let updated = @agent.SessionData::{
        session_id: data.session_id,
        name: new_name,
        messages: data.messages,
        stats: data.stats,
        working_dir: data.working_dir,
        created_at: data.created_at,
        source: data.source,
        reasoning_effort: data.reasoning_effort,
        model_name: data.model_name,
        channel_info: data.channel_info,
        latest_latency_ms: data.latest_latency_ms,
        latest_ttft_ms: data.latest_ttft_ms,
        time_machine: data.time_machine,
        pending_error_rollback: data.pending_error_rollback,
        model_base_url: data.model_base_url,
        last_status: data.last_status,
        last_error: data.last_error,
        error_code: data.error_code,
        top_up_url: data.top_up_url,
        raw_message: data.raw_message,
        forked_from: data.forked_from,
        chunk_count: data.chunk_count,
        agent_profile: data.agent_profile,
        sub_model: data.sub_model,
      }
      if changed {
        // Sync the in-memory agent's name so a subsequent run does not
        // overwrite the renamed session file with the old name.
        if new_name != data.name {
          match server_ref.val.active_agents.get(id) {
            Some(agent) => agent.rename(new_name)
            None => ()
          }
        }
        @agent.save_session(updated) catch {
          _ =>
            return @core.HttpResponse::internal_server_error().json_value(
              Json::object({ "error": "Failed to save session".to_json() }),
            )
        }
        // Broadcast session_updated via hub.
        let hub = server_ref.val.hub
        // Broadcast session_renamed via WS when the name changed.
        if new_name != data.name {
          hub.broadcast_session(
            id,
            @protocol.build_session_renamed_event(id, new_name),
          )
        }
        let model_field : Json = match updated.model_name {
          Some(m) => m.to_json()
          None => Json::null()
        }
        hub.broadcast_session_json(
          id,
          "session_updated",
          Json::object({
            "session_id": id.to_json(),
            "name": updated.name.to_json(),
            "model": model_field,
            "pinned": pinned_val,
          }),
        )
      }
      let effective_pinned = load_pinned_map().get(id).unwrap_or(false)
      let resp_obj : Map[String, Json] = Map([])
      resp_obj["ok"] = true.to_json()
      match obj.get("name") {
        Some(_) => resp_obj["name"] = updated.name.to_json()
        _ => ()
      }
      match obj.get("pinned") {
        Some(_) => resp_obj["pinned"] = effective_pinned.to_json()
        _ => ()
      }
      @core.HttpResponse::ok().json_value(Json::object(resp_obj))
    }
    None =>
      @core.HttpResponse::not_found().json_value(
        Json::object({ "error": "Session not found".to_json() }),
      )
  }
}

///|
/// GET /api/sessions/:id/skills — List skills available in the session context.
/// Returns the merged builtin+user skill list filtered to user-invocable
/// skills, each entry in the orig session-skills shape
/// ({ name, name_zh, description, description_zh, encrypted, source_type,
///    always_show }). Agent-profile based filtering from orig is not
/// replicated: session agent profiles are not resolved here.
fn handle_session_skills(
  server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let id = match event.param("id") {
    Some(p) => p.to_owned()
    None =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": "Missing parameter: id".to_json() }),
      )
  }
  let _ = server_ref
  @core.HttpResponse::ok().json_value(
    Json::object({
      "session_id": id.to_json(),
      "skills": Json::array(session_skills_json()),
    }),
  )
}

///|
/// GET /api/sessions/:id/files — List files in the session's working directory.
/// Returns directory entries for the session's working_dir.
fn handle_session_files(
  server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let id = match event.param("id") {
    Some(p) => p.to_owned()
    None =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": "Missing parameter: id".to_json() }),
      )
  }
  // Determine working directory for the session.
  let working_dir = match @agent.load_session(id) {
    Some(data) => data.working_dir
    None =>
      match server_ref.val.active_agents.get(id) {
        Some(agent) => agent.to_session_data().working_dir
        None =>
          return @core.HttpResponse::not_found().json_value(
            Json::object({ "error": "Session not found".to_json() }),
          )
      }
  }
  let dir = if working_dir.is_empty() { "." } else { working_dir }
  if !@fs.path_exists(dir) {
    return @core.HttpResponse::ok().json_value(
      Json::object({
        "session_id": id.to_json(),
        "path": dir.to_json(),
        "files": Json::array([]),
      }),
    )
  }
  let entries = @fs.read_dir(dir) catch {
    _ =>
      return @core.HttpResponse::ok().json_value(
        Json::object({
          "session_id": id.to_json(),
          "path": dir.to_json(),
          "files": Json::array([]),
        }),
      )
  }
  let items : Array[Json] = []
  for name in entries {
    let full = @path.Path::join(@path.Path(dir), @path.Path(name)).to_string()
    let is_dir = @fs.path_exists(full) && is_directory(full)
    items.push(
      Json::object({ "name": name.to_json(), "is_dir": is_dir.to_json() }),
    )
  }
  @core.HttpResponse::ok().json_value(
    Json::object({
      "session_id": id.to_json(),
      "path": dir.to_json(),
      "files": items.to_json(),
      "count": entries.length().to_json(),
    }),
  )
}

// ── Model / SubModel / ReasoningEffort PATCH endpoints (web-replication-05) ──

///|
/// PATCH /api/sessions/:id/model — Switch the session's primary model.
/// Body: {"model_id": "..."}
/// Looks up the model config by id/runtime_id, updates session data,
/// swaps the active agent's client if running, and broadcasts session_updated.
fn handle_session_model_patch(
  server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let id = match event.param("id") {
    Some(p) => p.to_owned()
    None =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": "Missing parameter: id".to_json() }),
      )
  }
  let j : Json = event.req.body() catch {
    _ =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": "Invalid JSON body".to_json() }),
      )
  }
  let model_id = match j {
    Object(o) =>
      match o.get("model_id") {
        Some(String(s)) => s
        _ =>
          return @core.HttpResponse::bad_request().json_value(
            Json::object({ "error": "Missing field: model_id".to_json() }),
          )
      }
    _ =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": "Invalid JSON body".to_json() }),
      )
  }
  // Look up model config by id or runtime_id.
  let cfg = server_ref.val.config
  let mut found : @config.ModelConfig? = None
  for m in cfg.models {
    if m.id == model_id || m.runtime_id == model_id {
      found = Some(m)
      break
    }
  }
  let mc = match found {
    Some(m) => m
    None =>
      return @core.HttpResponse::not_found().json_value(
        Json::object({ "error": "Model not found: \{model_id}".to_json() }),
      )
  }
  match load_session_or_active(server_ref, id) {
    Some(data) => {
      let updated = @agent.SessionData::{
        session_id: data.session_id,
        name: data.name,
        messages: data.messages,
        stats: data.stats,
        working_dir: data.working_dir,
        created_at: data.created_at,
        source: data.source,
        reasoning_effort: data.reasoning_effort,
        model_name: Some(mc.model),
        channel_info: data.channel_info,
        latest_latency_ms: data.latest_latency_ms,
        latest_ttft_ms: data.latest_ttft_ms,
        time_machine: data.time_machine,
        pending_error_rollback: data.pending_error_rollback,
        model_base_url: mc.base_url,
        last_status: data.last_status,
        last_error: data.last_error,
        error_code: data.error_code,
        top_up_url: data.top_up_url,
        raw_message: data.raw_message,
        forked_from: data.forked_from,
        chunk_count: data.chunk_count,
        agent_profile: data.agent_profile,
        sub_model: data.sub_model,
      }
      @agent.save_session(updated) catch {
        _ =>
          return @core.HttpResponse::internal_server_error().json_value(
            Json::object({ "error": "Failed to save session".to_json() }),
          )
      }
      // Swap active agent's client if present.
      match server_ref.val.active_agents.get(id) {
        Some(agent) => {
          let api_type = if mc.anthropic_format {
            @config.AnthropicMessages
          } else {
            @config.Providers::api_type_for(mc.base_url)
          }
          agent.client = @client.Client::new(
            mc.api_key,
            mc.base_url,
            mc.model,
            api_type,
          )
        }
        None => ()
      }
      // Broadcast session_updated.
      let hub = server_ref.val.hub
      hub.broadcast_session_json(
        id,
        "session_updated",
        Json::object({ "session_id": id.to_json(), "model": mc.model.to_json() }),
      )
      @core.HttpResponse::ok().json_value(
        Json::object({
          "session_id": id.to_json(),
          "model": mc.model.to_json(),
          "model_id": mc.id.to_json(),
        }),
      )
    }
    None =>
      @core.HttpResponse::not_found().json_value(
        Json::object({ "error": "Session not found".to_json() }),
      )
  }
}

///|
/// PATCH /api/sessions/:id/submodel — Set the session's sub-model.
/// Body: {"model_name": "..."}
fn handle_session_submodel_patch(
  server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let id = match event.param("id") {
    Some(p) => p.to_owned()
    None =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": "Missing parameter: id".to_json() }),
      )
  }
  let j : Json = event.req.body() catch {
    _ =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": "Invalid JSON body".to_json() }),
      )
  }
  let model_name : String? = match j {
    Object(o) =>
      match o.get("model_name") {
        Some(String(s)) => Some(s)
        Some(Null) => None
        _ =>
          return @core.HttpResponse::bad_request().json_value(
            Json::object({ "error": "Missing field: model_name".to_json() }),
          )
      }
    _ =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": "Invalid JSON body".to_json() }),
      )
  }
  match load_session_or_active(server_ref, id) {
    Some(data) => {
      let updated = @agent.SessionData::{
        session_id: data.session_id,
        name: data.name,
        messages: data.messages,
        stats: data.stats,
        working_dir: data.working_dir,
        created_at: data.created_at,
        source: data.source,
        reasoning_effort: data.reasoning_effort,
        model_name: data.model_name,
        channel_info: data.channel_info,
        latest_latency_ms: data.latest_latency_ms,
        latest_ttft_ms: data.latest_ttft_ms,
        time_machine: data.time_machine,
        pending_error_rollback: data.pending_error_rollback,
        model_base_url: data.model_base_url,
        last_status: data.last_status,
        last_error: data.last_error,
        error_code: data.error_code,
        top_up_url: data.top_up_url,
        raw_message: data.raw_message,
        forked_from: data.forked_from,
        chunk_count: data.chunk_count,
        agent_profile: data.agent_profile,
        sub_model: model_name,
      }
      @agent.save_session(updated) catch {
        _ =>
          return @core.HttpResponse::internal_server_error().json_value(
            Json::object({ "error": "Failed to save session".to_json() }),
          )
      }
      // Broadcast session_updated.
      let hub = server_ref.val.hub
      let sub_json : Json = match model_name {
        Some(s) => s.to_json()
        None => Json::null()
      }
      hub.broadcast_session_json(
        id,
        "session_updated",
        Json::object({ "session_id": id.to_json(), "sub_model": sub_json }),
      )
      @core.HttpResponse::ok().json_value(
        Json::object({ "session_id": id.to_json(), "sub_model": sub_json }),
      )
    }
    None =>
      @core.HttpResponse::not_found().json_value(
        Json::object({ "error": "Session not found".to_json() }),
      )
  }
}

///|
/// PATCH /api/sessions/:id/reasoning_effort — Set reasoning effort level.
/// Body: {"reasoning_effort": "low|medium|high|off"}
fn handle_session_reasoning_effort_patch(
  server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let id = match event.param("id") {
    Some(p) => p.to_owned()
    None =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": "Missing parameter: id".to_json() }),
      )
  }
  let j : Json = event.req.body() catch {
    _ =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": "Invalid JSON body".to_json() }),
      )
  }
  let effort : String? = match j {
    Object(o) =>
      match o.get("reasoning_effort") {
        Some(String(s)) => Some(s)
        Some(Null) => None
        _ =>
          return @core.HttpResponse::bad_request().json_value(
            Json::object({
              "error": "Missing field: reasoning_effort".to_json(),
            }),
          )
      }
    _ =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": "Invalid JSON body".to_json() }),
      )
  }
  match load_session_or_active(server_ref, id) {
    Some(data) => {
      // Normalize: "off"/"none"/"" → None
      let normalized : String? = match effort {
        Some(v) => {
          let lower = v.to_lower()
          if lower == "off" || lower == "none" || lower.is_empty() {
            None
          } else {
            Some(lower)
          }
        }
        None => None
      }
      let updated = @agent.SessionData::{
        session_id: data.session_id,
        name: data.name,
        messages: data.messages,
        stats: data.stats,
        working_dir: data.working_dir,
        created_at: data.created_at,
        source: data.source,
        reasoning_effort: normalized,
        model_name: data.model_name,
        channel_info: data.channel_info,
        latest_latency_ms: data.latest_latency_ms,
        latest_ttft_ms: data.latest_ttft_ms,
        time_machine: data.time_machine,
        pending_error_rollback: data.pending_error_rollback,
        model_base_url: data.model_base_url,
        last_status: data.last_status,
        last_error: data.last_error,
        error_code: data.error_code,
        top_up_url: data.top_up_url,
        raw_message: data.raw_message,
        forked_from: data.forked_from,
        chunk_count: data.chunk_count,
        agent_profile: data.agent_profile,
        sub_model: data.sub_model,
      }
      @agent.save_session(updated) catch {
        _ =>
          return @core.HttpResponse::internal_server_error().json_value(
            Json::object({ "error": "Failed to save session".to_json() }),
          )
      }
      // Update active agent's reasoning_effort if present.
      match server_ref.val.active_agents.get(id) {
        Some(agent) => agent.set_reasoning_effort(normalized)
        None => ()
      }
      // Broadcast session_updated.
      let hub = server_ref.val.hub
      let eff_json : Json = match normalized {
        Some(e) => e.to_json()
        None => Json::null()
      }
      hub.broadcast_session_json(
        id,
        "session_updated",
        Json::object({
          "session_id": id.to_json(),
          "reasoning_effort": eff_json,
        }),
      )
      @core.HttpResponse::ok().json_value(
        Json::object({
          "session_id": id.to_json(),
          "reasoning_effort": eff_json,
        }),
      )
    }
    None =>
      @core.HttpResponse::not_found().json_value(
        Json::object({ "error": "Session not found".to_json() }),
      )
  }
}
