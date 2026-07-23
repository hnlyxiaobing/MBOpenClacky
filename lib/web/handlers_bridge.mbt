///| Bridge functions that adapt REST API handlers to the crescent framework.
///  Converts crescent Event to HttpRequest and HttpResponse back to @core.HttpResponse.

// ── Bridge Helpers ────────────────────────────────────────────────

///|
/// Convert a crescent Event to our HttpRequest type.
fn event_to_request(
  event : @crescent.Event,
  params : Array[(String, String)],
) -> HttpRequest {
  let body : String = {
    let j : Json = event.req.body() catch { _ => Json::object(Map([])) }
    j.stringify()
  }
  {
    http_method: GET, // method is determined by route registration
    path: event.req.path(),
    params,
    body,
    headers: [],
  }
}

///|
/// Convert our HttpResponse to crescent @core.HttpResponse.
fn response_to_core(resp : HttpResponse) -> @core.HttpResponse {
  let core_resp = match resp.status {
    201 => @core.HttpResponse::created()
    204 => @core.HttpResponse::no_content()
    400 => @core.HttpResponse::bad_request()
    404 => @core.HttpResponse::not_found()
    _ => @core.HttpResponse::ok()
  }
  core_resp.header("Content-Type", resp.content_type).body(resp.body)
}

///|
/// Extract params from crescent event for a single :id param.
fn extract_id_param(event : @crescent.Event) -> Array[(String, String)] {
  match event.param("id") {
    Some(v) => [("id", v.to_owned())]
    None => []
  }
}

///|
/// Extract params from crescent event for a single :name param.
fn extract_name_param(event : @crescent.Event) -> Array[(String, String)] {
  match event.param("name") {
    Some(v) => [("name", v.to_owned())]
    None => []
  }
}

///|
/// Extract a query parameter value from a URL string.
/// Parses `?key=value` or `&key=value` segments.
fn find_query_param(url : String, key : String) -> String? {
  let target = "\{key}="
  match url.find(target) {
    Some(idx) => {
      let start = idx + target.length()
      let chars = url.to_array()
      let buf = StringBuilder::new()
      let mut i = start
      while i < chars.length() {
        let c = chars[i]
        if c == '&' {
          break
        }
        buf.write_char(c)
        i = i + 1
      }
      let val = buf.to_string()
      if val.is_empty() {
        None
      } else {
        Some(val)
      }
    }
    None => None
  }
}

// ── MCP Bridges ───────────────────────────────────────────────────

///|
fn handle_mcp_list_servers_bridge(
  server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let req = event_to_request(event, [])
  response_to_core(handle_mcp_list_servers(server_ref.val.mcp_registry, req))
}

///|
fn handle_mcp_add_server_bridge(
  server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let req = event_to_request(event, [])
  response_to_core(handle_mcp_add_server(server_ref.val.mcp_registry, req))
}

///|
fn handle_mcp_probe_server_bridge(
  server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let req = event_to_request(event, extract_name_param(event))
  response_to_core(handle_mcp_probe_server(server_ref.val.mcp_registry, req))
}

///|
fn handle_mcp_toggle_server_bridge(
  server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let req = event_to_request(event, extract_name_param(event))
  response_to_core(handle_mcp_toggle_server(server_ref.val.mcp_registry, req))
}

///|
fn handle_mcp_update_server_bridge(
  server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let req = event_to_request(event, extract_name_param(event))
  response_to_core(handle_mcp_update_server(server_ref.val.mcp_registry, req))
}

///|
fn handle_mcp_remove_server_bridge(
  server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let req = event_to_request(event, extract_name_param(event))
  response_to_core(handle_mcp_remove_server(server_ref.val.mcp_registry, req))
}

///|
fn handle_mcp_list_server_tools_bridge(
  server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let req = event_to_request(event, extract_name_param(event))
  response_to_core(
    handle_mcp_list_server_tools(server_ref.val.mcp_registry, req),
  )
}

///|
fn handle_mcp_call_server_tool_bridge(
  server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let req = event_to_request(event, extract_name_param(event))
  response_to_core(
    handle_mcp_call_server_tool(server_ref.val.mcp_registry, req),
  )
}

///|
/// (legacy) GET /api/mcp/tools — List all MCP tools across all servers.
fn handle_mcp_list_tools_bridge(
  server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let req = event_to_request(event, [])
  response_to_core(handle_mcp_list_tools(server_ref.val.mcp_registry, req))
}

///|
/// (legacy) POST /api/mcp/tools/:name/execute — Execute an MCP tool by name.
fn handle_mcp_execute_tool_bridge(
  server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let req = event_to_request(event, extract_name_param(event))
  response_to_core(handle_mcp_execute_tool(server_ref.val.mcp_registry, req))
}

// ── Channel Bridges ───────────────────────────────────────────────

///|
fn handle_channels_list_bridge(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let req = event_to_request(event, [])
  response_to_core(handle_channels_list(req))
}

///|
fn handle_channels_create_bridge(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let req = event_to_request(event, [])
  response_to_core(handle_channels_create(req))
}

///|
fn handle_channels_update_bridge(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let req = event_to_request(event, extract_id_param(event))
  response_to_core(handle_channels_update(req))
}

///|
fn handle_channels_delete_bridge(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let req = event_to_request(event, extract_id_param(event))
  response_to_core(handle_channels_delete(req))
}

///|
fn handle_channels_test_bridge(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let req = event_to_request(event, extract_id_param(event))
  response_to_core(handle_channels_test(req))
}

///|
fn handle_channels_status_bridge(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let req = event_to_request(event, extract_id_param(event))
  response_to_core(handle_channels_status(req))
}

// ── Webhook Bridge ─────────────────────────────────────────────────

///|
/// POST /api/webhooks/:platform — Receive incoming IM webhook events.
/// Routes the payload to the registered WebhookRegistry handler for the platform.
/// Also handles Feishu URL-verification challenge.
fn handle_webhook_bridge(
  server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let platform = match event.param("platform") {
    Some(p) => p.to_owned()
    None =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": "Missing parameter: platform".to_json() }),
      )
  }
  let body : Json = event.req.body() catch {
    _ =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": "Invalid JSON body".to_json() }),
      )
  }
  // Feishu URL-verification challenge: return the challenge string directly
  if platform == "feishu" {
    match @channel.handle_feishu_challenge(body) {
      Some(challenge) =>
        return @core.HttpResponse::ok()
          .header("Content-Type", "text/plain")
          .body(challenge)
      None => ()
    }
  }
  match server_ref.val.webhook_registry.handle(platform, body) {
    Ok(_) =>
      @core.HttpResponse::ok().json_value(
        Json::object({ "status": "ok".to_json() }),
      )
    Err(e) =>
      @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": e.to_json() }),
      )
  }
}

// ── Schedule Bridges ──────────────────────────────────────────────

///|
fn handle_schedules_list_bridge(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let req = event_to_request(event, [])
  response_to_core(handle_schedules_list(req))
}

///|
fn handle_schedules_create_bridge(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let req = event_to_request(event, [])
  response_to_core(handle_schedules_create(req))
}

///|
fn handle_schedules_update_bridge(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let req = event_to_request(event, extract_id_param(event))
  response_to_core(handle_schedules_update(req))
}

///|
fn handle_schedules_delete_bridge(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let req = event_to_request(event, extract_id_param(event))
  response_to_core(handle_schedules_delete(req))
}

///|
fn handle_schedules_trigger_bridge(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let req = event_to_request(event, extract_id_param(event))
  response_to_core(handle_schedules_trigger(req))
}

///|
fn handle_schedules_history_bridge(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let req = event_to_request(event, extract_id_param(event))
  response_to_core(handle_schedules_history(req))
}

// ── Backup Bridges ────────────────────────────────────────────────
// NOTE: /api/backups group bridge routes removed (web-parity-05); the
// /api/backup singular alias routes below call the same pub handlers.

// ── Billing Bridges ───────────────────────────────────────────────
// NOTE: /api/billing/{status,usage,export} bridge routes removed
// (web-parity-05); activate and the parity-04 contract endpoints remain.

///|
fn handle_billing_activate_bridge(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let req = event_to_request(event, [])
  response_to_core(handle_billing_activate(req))
}

// ── Skills Bridges ────────────────────────────────────────────────

///|
fn handle_skills_list_bridge(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let req = event_to_request(event, [])
  response_to_core(handle_skills_list(req))
}

///|
fn handle_skills_create_bridge(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let req = event_to_request(event, [])
  response_to_core(handle_skills_create(req))
}

///|
fn handle_skills_update_bridge(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let req = event_to_request(event, extract_name_param(event))
  response_to_core(handle_skills_update(req))
}

///|
fn handle_skills_delete_bridge(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let req = event_to_request(event, extract_name_param(event))
  response_to_core(handle_skills_delete(req))
}

///|
fn handle_skills_evolve_bridge(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let req = event_to_request(event, extract_name_param(event))
  response_to_core(handle_skills_evolve(req))
}

///|
fn handle_skills_get_content_bridge(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let req = event_to_request(event, extract_name_param(event))
  response_to_core(handle_skills_get_content(req))
}

///|
fn handle_skills_put_content_bridge(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let req = event_to_request(event, extract_name_param(event))
  response_to_core(handle_skills_put_content(req))
}

///|
fn handle_skills_toggle_bridge(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let req = event_to_request(event, extract_name_param(event))
  response_to_core(handle_skills_toggle(req))
}

///|
fn handle_skills_install_bridge(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let req = event_to_request(event, [])
  response_to_core(handle_skills_install(req))
}

///|
fn handle_store_skills_bridge(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let req = event_to_request(event, [])
  response_to_core(handle_store_skills(req))
}

///|
fn handle_creator_skills_bridge(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let req = event_to_request(event, [])
  response_to_core(handle_creator_skills(req))
}

///|
fn handle_skills_evolution_history_bridge(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let req = event_to_request(event, [])
  response_to_core(handle_skills_evolution_history(req))
}

// ── Trash Bridges ─────────────────────────────────────────────────

///|
fn handle_trash_list_bridge(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  // Extract query parameter ?type= for filtering
  let url = event.req.url
  let params : Array[(String, String)] = []
  match find_query_param(url, "type") {
    Some(v) => params.push(("type", v))
    None => ()
  }
  let req = event_to_request(event, params)
  response_to_core(handle_trash_list(req))
}

///|
fn handle_trash_restore_bridge(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let req = event_to_request(event, extract_id_param(event))
  response_to_core(handle_trash_restore(req))
}

///|
fn handle_trash_restore_batch_bridge(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let req = event_to_request(event, [])
  response_to_core(handle_trash_restore_batch(req))
}

///|
fn handle_trash_delete_bridge(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let req = event_to_request(event, extract_id_param(event))
  response_to_core(handle_trash_delete(req))
}

///|
fn handle_trash_empty_bridge(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let req = event_to_request(event, [])
  response_to_core(handle_trash_empty(req))
}

///|
fn handle_trash_stats_bridge(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let req = event_to_request(event, [])
  response_to_core(handle_trash_stats(req))
}

// ── Meeting Bridges ───────────────────────────────────────────────
// NOTE: /api/meetings* bridge routes removed (web-parity-05).

// ── Billing New Bridges (web-parity-04) ────────────────────────

///|
fn handle_billing_summary_bridge(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let req = event_to_request(event, [])
  response_to_core(handle_billing_summary(req))
}

///|
fn handle_billing_daily_bridge(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let req = event_to_request(event, [])
  response_to_core(handle_billing_daily(req))
}

///|
fn handle_billing_records_bridge(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let req = event_to_request(event, [])
  response_to_core(handle_billing_records(req))
}

///|
fn handle_billing_sessions_bridge(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let req = event_to_request(event, [])
  response_to_core(handle_billing_sessions(req))
}

///|
fn handle_billing_clear_bridge(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let req = event_to_request(event, [])
  response_to_core(handle_billing_clear(req))
}

// ── Backup Alias Bridges (web-parity-04) ────────────────────────

///|
/// GET /api/backup/status — alias for backup list.
fn handle_backup_status_bridge(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let req = event_to_request(event, [])
  response_to_core(handle_backups_list(req))
}

///|
/// POST /api/backup/run — alias for backup create.
fn handle_backup_run_bridge(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let req = event_to_request(event, [])
  response_to_core(handle_backups_create(req))
}

///|
/// POST /api/backup/restore/:id — alias for backup restore.
fn handle_backup_restore_bridge(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let req = event_to_request(event, extract_id_param(event))
  response_to_core(handle_backups_restore(req))
}

///|
/// POST /api/backup/open-folder — open backup folder in system file manager.
fn handle_backup_open_folder_bridge(
  _server_ref : Ref[WebServer],
  _event : @crescent.Event,
) -> @core.HttpResponse {
  // Opening the system file manager requires OS integration that is not
  // available in headless mode — report honestly instead of faking success.
  @core.HttpResponse::HttpResponse(status_code=@core.StatusCode::NotImplemented).json_value(
    Json::object({
      "ok": false.to_json(),
      "error": "unimplemented".to_json(),
      "message": "backup open-folder not available in headless mode".to_json(),
    }),
  )
}

///|
/// GET /api/backup/download/:id — download a backup archive.
fn handle_backup_download_bridge(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let req = event_to_request(event, extract_id_param(event))
  // Reuse restore logic to verify backup exists, then return a download link
  response_to_core(handle_backup_download(req))
}

///|
/// GET /api/backup/config — get backup configuration.
fn handle_backup_config_bridge(
  _server_ref : Ref[WebServer],
  _event : @crescent.Event,
) -> @core.HttpResponse {
  // Initialize backup_dir from defaults on first access
  if backup_config.val.backup_dir == "" {
    backup_config.val.backup_dir = backups_dir()
  }
  response_to_core(
    HttpResponse::ok(
      Json::object({
        "backup_dir": backup_config.val.backup_dir.to_json(),
        "auto_backup": backup_config.val.auto_backup.to_json(),
        "max_backups": backup_config.val.max_backups.to_json(),
      }).stringify(),
    ),
  )
}

///|
/// POST /api/backup/restore - restore backup via body {id}.
/// Compatibility alias (spec-08): frontend sends id in body.
fn handle_backup_restore_body_bridge(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let req = event_to_request(event, [])
  let body_json : Json = @json.parse(req.body) catch {
    _ => return response_to_core(HttpResponse::bad_request("Invalid JSON body"))
  }
  let id = match body_json {
    Object(obj) =>
      match obj.get("id") {
        Some(String(s)) => s
        _ => ""
      }
    _ => ""
  }
  if id == "" {
    return response_to_core(
      HttpResponse::bad_request("Missing 'id' in request body"),
    )
  }
  let req_with_id : HttpRequest = { ..req, params: [("id", id)] }
  response_to_core(handle_backups_restore(req_with_id))
}

///|
/// GET /api/backup/download?id=... - download via query param.
/// Compatibility alias (spec-08): frontend sends id as query param.
fn handle_backup_download_query_bridge(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let url = event.req.url
  let id = match find_query_param(url, "id") {
    Some(v) => v
    None =>
      return response_to_core(
        HttpResponse::bad_request("Missing 'id' query parameter"),
      )
  }
  let req = event_to_request(event, [("id", id)])
  response_to_core(handle_backup_download(req))
}

///|
/// PATCH /api/backup/config - update backup configuration.
/// Compatibility alias (spec-08): frontend uses PATCH to update config.
fn handle_backup_config_update_bridge(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let req = event_to_request(event, [])
  response_to_core(handle_backup_config_update(req))
}

// ── Store Bridges (spec-09) ──────────────────────────────────────

///|
/// GET /api/store/extensions - list marketplace extensions.
fn handle_store_list_bridge(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let url = event.req.url
  // Extract query params for q and sort
  let q = match find_query_param(url, "q") {
    Some(v) => v
    None => ""
  }
  let params = if q == "" { [] } else { [("q", q)] }
  let req = event_to_request(event, params)
  response_to_core(handle_store_list(req))
}

///|
/// GET /api/store/extensions/installed - list installed extensions.
fn handle_store_installed_bridge(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let req = event_to_request(event, [])
  response_to_core(handle_store_installed(req))
}

///|
/// GET /api/store/extension?id= - extension detail.
fn handle_store_detail_bridge(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let url = event.req.url
  let id = match find_query_param(url, "id") {
    Some(v) => v
    None => ""
  }
  let req = event_to_request(event, [("id", id)])
  response_to_core(handle_store_detail(req))
}

///|
/// POST /api/store/extension/install - install extension.
fn handle_store_install_bridge(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let req = event_to_request(event, [])
  response_to_core(handle_store_install(req))
}

///|
/// POST /api/store/extension/enable - enable extension.
fn handle_store_enable_bridge(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let req = event_to_request(event, [])
  response_to_core(handle_store_enable(req))
}

///|
/// POST /api/store/extension/disable - disable extension.
fn handle_store_disable_bridge(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let req = event_to_request(event, [])
  response_to_core(handle_store_disable(req))
}

///|
/// DELETE /api/store/extension - uninstall extension.
fn handle_store_uninstall_bridge(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let req = event_to_request(event, [])
  response_to_core(handle_store_uninstall(req))
}

// ── Media New Bridges (web-parity-04) ────────────────────────────

///|
/// GET /api/media/video/status — video generation job status.
fn handle_media_video_status_bridge(
  _server_ref : Ref[WebServer],
  _event : @crescent.Event,
) -> @core.HttpResponse {
  // Video generation itself is not implemented (POST /api/media/video
  // returns 501), so there is no job queue to report status for —
  // answer 501 rather than a hardcoded "idle".
  @core.HttpResponse::HttpResponse(status_code=@core.StatusCode::NotImplemented).json_value(
    Json::object({
      "ok": false.to_json(),
      "error": "unimplemented".to_json(),
      "message": "Video generation not yet implemented".to_json(),
    }),
  )
}

///|
/// GET /api/media/types — supported media types.
fn handle_media_types_bridge(
  _server_ref : Ref[WebServer],
  _event : @crescent.Event,
) -> @core.HttpResponse {
  @core.HttpResponse::ok().json_value(
    Json::object({
      "image": Json::array(["png".to_json(), "jpg".to_json(), "webp".to_json()]),
      "video": Json::array(["mp4".to_json(), "webm".to_json()]),
      "audio": Json::array(["mp3".to_json(), "wav".to_json(), "ogg".to_json()]),
    }),
  )
}

// ── File Action Bridge (web-parity-04) ────────────────────────────

///|
/// POST /api/file-action — open/reveal/download a local file.
fn handle_file_action_bridge(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let body : Json = event.req.body() catch {
    _ =>
      return @core.HttpResponse::bad_request().json_value(
        Json::object({ "error": "Invalid JSON body".to_json() }),
      )
  }
  let action = match body {
    { "action": String(a), .. } => a
    _ => ""
  }
  let path = match body {
    { "path": String(p), .. } => p
    _ => ""
  }
  if action.is_empty() || path.is_empty() {
    return @core.HttpResponse::bad_request().json_value(
      Json::object({ "error": "action and path required".to_json() }),
    )
  }
  // Actual file open/reveal requires OS integration that is not available
  // in headless mode — report honestly instead of faking success.
  @core.HttpResponse::HttpResponse(status_code=@core.StatusCode::NotImplemented).json_value(
    Json::object({
      "ok": false.to_json(),
      "error": "unimplemented".to_json(),
      "message": ("file-action '" + action + "' not available in headless mode").to_json(),
    }),
  )
}

// ── Trash Sessions Bridge (web-parity-04) ────────────────────────

///|
/// GET /api/trash/sessions — list trashed sessions.
fn handle_trash_sessions_list_bridge(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  // Reuse trash list with type=sessions filter
  let req = event_to_request(event, [("type", "sessions")])
  response_to_core(handle_trash_list(req))
}

///|
/// POST /api/trash/sessions/:id/restore — restore a trashed session.
fn handle_trash_sessions_restore_bridge(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let req = event_to_request(event, extract_id_param(event))
  response_to_core(handle_trash_restore(req))
}

///|
/// POST /api/trash/sessions/restore - restore session via body {session_id}.
/// Compatibility alias (spec-08): frontend sends session_id in body.
fn handle_trash_sessions_restore_body_bridge(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let req = event_to_request(event, [])
  let body_json : Json = @json.parse(req.body) catch {
    _ => return response_to_core(HttpResponse::bad_request("Invalid JSON body"))
  }
  let session_id = match body_json {
    Object(obj) =>
      match obj.get("session_id") {
        Some(String(s)) => s
        _ => ""
      }
    _ => ""
  }
  if session_id == "" {
    return response_to_core(
      HttpResponse::bad_request("Missing 'session_id' in request body"),
    )
  }
  let req_with_id : HttpRequest = { ..req, params: [("id", session_id)] }
  response_to_core(handle_trash_restore(req_with_id))
}

///|
/// DELETE /api/trash/sessions/:id — permanently delete a trashed session.
fn handle_trash_sessions_delete_bridge(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let req = event_to_request(event, extract_id_param(event))
  response_to_core(handle_trash_delete(req))
}

///|
/// Extract chat_id param from crescent event.
fn extract_chat_id_param(event : @crescent.Event) -> Array[(String, String)] {
  match event.param("chat_id") {
    Some(v) => [("chat_id", v.to_owned())]
    None => []
  }
}

///|
fn handle_channels_send_bridge(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let req = event_to_request(event, extract_id_param(event))
  response_to_core(handle_channels_send(req))
}

///|
fn handle_channels_group_history_bridge(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let req = event_to_request(event, extract_chat_id_param(event))
  response_to_core(handle_channels_group_history(req))
}

///|
fn handle_channels_users_bridge(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let req = event_to_request(event, extract_id_param(event))
  response_to_core(handle_channels_users(req))
}

///|
/// PATCH /api/channels/:id/enabled - Toggle channel enabled state.
/// The :id param accepts either a channel ID or a platform name.
fn handle_channels_toggle_enabled_bridge(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let req = event_to_request(event, extract_id_param(event))
  response_to_core(handle_channels_update(req))
}
