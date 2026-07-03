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

// ── MCP Bridges ───────────────────────────────────────────────────

///|
fn handle_mcp_list_servers_bridge(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let req = event_to_request(event, [])
  response_to_core(handle_mcp_list_servers(req))
}

///|
fn handle_mcp_register_server_bridge(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let req = event_to_request(event, [])
  response_to_core(handle_mcp_register_server(req))
}

///|
fn handle_mcp_remove_server_bridge(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let req = event_to_request(event, extract_id_param(event))
  response_to_core(handle_mcp_remove_server(req))
}

///|
fn handle_mcp_list_tools_bridge(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let req = event_to_request(event, [])
  response_to_core(handle_mcp_list_tools(req))
}

///|
fn handle_mcp_execute_tool_bridge(
  _server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  let req = event_to_request(event, extract_name_param(event))
  response_to_core(handle_mcp_execute_tool(req))
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
  let req = event_to_request(event, [])
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

// ── Onboarding Bridges ────────────────────────────────────────────

///|
fn handle_onboard_device_start_bridge(
  server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  handle_onboard_device_start(server_ref, event)
}

///|
fn handle_onboard_device_poll_bridge(
  server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  handle_onboard_device_poll(server_ref, event)
}

///|
fn handle_onboard_complete_bridge(
  server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  handle_onboard_complete(server_ref, event)
}

///|
fn handle_onboard_skip_soul_bridge(
  server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  handle_onboard_skip_soul(server_ref, event)
}

// ── Local Image Proxy Bridge ──────────────────────────────────────

///|
fn handle_local_image_bridge(
  server_ref : Ref[WebServer],
  event : @crescent.Event,
) -> @core.HttpResponse {
  handle_local_image(server_ref, event)
}
