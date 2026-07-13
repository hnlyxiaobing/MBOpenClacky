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
    let j : Json = event.req.body() catch { _ => Json::object({}) }
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
fn handle_mcp_register_server_bridge(
  server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let req = event_to_request(event, [])
  response_to_core(handle_mcp_register_server(server_ref.val.mcp_registry, req))
}

///|
fn handle_mcp_remove_server_bridge(
  server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let req = event_to_request(event, extract_id_param(event))
  response_to_core(handle_mcp_remove_server(server_ref.val.mcp_registry, req))
}

///|
fn handle_mcp_list_tools_bridge(
  server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let req = event_to_request(event, [])
  response_to_core(handle_mcp_list_tools(server_ref.val.mcp_registry, req))
}

///|
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

///|
fn handle_backups_list_bridge(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let req = event_to_request(event, [])
  response_to_core(handle_backups_list(req))
}

///|
fn handle_backups_create_bridge(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let req = event_to_request(event, [])
  response_to_core(handle_backups_create(req))
}

///|
fn handle_backups_restore_bridge(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let req = event_to_request(event, extract_id_param(event))
  response_to_core(handle_backups_restore(req))
}

///|
fn handle_backups_delete_bridge(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let req = event_to_request(event, extract_id_param(event))
  response_to_core(handle_backups_delete(req))
}

// ── Billing Bridges ───────────────────────────────────────────────

///|
fn handle_billing_status_bridge(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let req = event_to_request(event, [])
  response_to_core(handle_billing_status(req))
}

///|
fn handle_billing_activate_bridge(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let req = event_to_request(event, [])
  response_to_core(handle_billing_activate(req))
}

///|
fn handle_billing_usage_bridge(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let req = event_to_request(event, [])
  response_to_core(handle_billing_usage(req))
}

///|
fn handle_billing_export_bridge(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let req = event_to_request(event, [])
  response_to_core(handle_billing_export(req))
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

///|
fn handle_meetings_list_bridge(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let url = event.req.url
  let params : Array[(String, String)] = []
  match find_query_param(url, "status") {
    Some(v) => params.push(("status", v))
    None => ()
  }
  let req = event_to_request(event, params)
  response_to_core(handle_meetings_list(req))
}

///|
fn handle_meetings_create_bridge(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let req = event_to_request(event, [])
  response_to_core(handle_meetings_create(req))
}

///|
fn handle_meetings_get_bridge(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let req = event_to_request(event, extract_id_param(event))
  response_to_core(handle_meetings_get(req))
}

///|
fn handle_meetings_update_bridge(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let req = event_to_request(event, extract_id_param(event))
  response_to_core(handle_meetings_update(req))
}

///|
fn handle_meetings_delete_bridge(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let req = event_to_request(event, extract_id_param(event))
  response_to_core(handle_meetings_delete(req))
}

///|
fn handle_meetings_summarize_bridge(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let req = event_to_request(event, extract_id_param(event))
  response_to_core(handle_meetings_summarize(req))
}
