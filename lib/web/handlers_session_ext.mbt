///| Extended session REST API handlers.
/// Provides endpoints for session export, fork, rename, and message history.
/// These complement the core session CRUD in handlers.mbt.

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
          "exported_at": @agent.current_timestamp_ms().to_json(),
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
    Ok(forked) =>
      @core.HttpResponse::created().json_value(
        Json::object({
          "forked_session": forked.to_json(),
          "source_session_id": id.to_json(),
        }),
      )
    Err(msg) =>
      @core.HttpResponse::not_found().json_value(
        Json::object({ "error": msg.to_json() }),
      )
  }
}

///|
/// POST /api/sessions/:id/rename — Rename a session.
/// Uses POST method as crescent does not support PATCH.
/// Expected body: {"name": "New Session Name"}
fn handle_session_rename(
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
        forked_from: data.forked_from,
        chunk_count: data.chunk_count,
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
          "old_name": old_name.to_json(),
          "new_name": new_name.to_json(),
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

///|
/// GET /api/sessions/:id/messages — Retrieve the message history for a session.
/// Returns an array of messages without the full session envelope.
fn handle_session_messages(
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
    Some(data) => {
      let messages_json : Array[Json] = []
      for msg in data.messages {
        messages_json.push(msg.to_json())
      }
      @core.HttpResponse::ok().json_value(
        Json::object({
          "session_id": id.to_json(),
          "messages": messages_json.to_json(),
          "message_count": data.messages.length().to_json(),
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
