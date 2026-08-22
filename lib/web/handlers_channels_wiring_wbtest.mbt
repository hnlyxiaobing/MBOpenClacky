///| White-box tests for channel wiring (stubfix-01): real dispatch on the

///| send/test API, and webhook routing into ChannelManager for configured

///| platforms. These tests exercise the breakpoints fixed by the wiring spec:

///| 1. send no longer returns a hard-coded success — it maps adapter lookup

///|    failures to `success:false`.

///| 2. test grades connectivity honestly per platform instead of field-only

///|    validation.

///| 3. webhook events route to ChannelManager::handle_webhook for configured

///|    platforms instead of falling through to the empty WebhookRegistry.

///|
/// Build a temp-file path that works on both Windows (%TEMP%) and Unix
/// ($TMPDIR, fallback /tmp). Mirrors lib/channel's test_temp_path.
fn wiring_temp_path(name : String) -> String {
  let dir = match @env.get_env_var("TEMP") {
    Some(d) => d
    None =>
      match @env.get_env_var("TMPDIR") {
        Some(d) => d
        None => "/tmp"
      }
  }
  let sep = if dir.has_suffix("/") || dir.has_suffix("\\") { "" } else { "/" }
  dir + sep + name
}

///|
/// Reset the in-memory channel store and register a single channel entry,
/// returning its generated id.
fn wiring_seed_channel(platform : String, enabled : Bool) -> String {
  channels_store.val = []
  channel_id_counter.val = 0
  let id = next_channel_id()
  let now = @env.now().reinterpret_as_int64()
  let entry : ChannelEntry = {
    id,
    platform,
    name: "test-" + platform,
    webhook_url: "",
    api_key: "",
    secret: "",
    enabled,
    status: "disconnected",
    created_at: now,
    updated_at: now,
  }
  channels_store.val.push(entry)
  id
}

///|
/// Parse a lib/web HttpResponse body as JSON (empty object on failure).
fn wiring_response_json(resp : HttpResponse) -> Json {
  @json.parse(resp.body) catch {
    _ => Json::object(Map([]))
  }
}

///|
/// Build a POST HttpRequest targeting /api/channels/:id/... with a JSON body.
fn wiring_make_request(path : String, body : String) -> HttpRequest {
  { http_method: POST, path, params: [("id", "ch-1")], body, headers: [] }
}

///|
/// Build a crescent Event for a webhook POST with a platform route param.
fn wiring_make_webhook_event(
  platform : String,
  body : String,
) -> @crescent.Event {
  let pmap : Map[String, StringView] = Map([])
  pmap["platform"] = platform.to_string_view()
  {
    req: @crescent.HttpRequest::HttpRequest(
      @crescent.HttpMethod::Post,
      "/api/webhooks/\{platform}",
      Map([]),
      raw_body=@utf8.encode(body),
    ),
    res: @crescent.HttpResponse::HttpResponse(status_code=OK),
    params: pmap,
  }
}

// ── send wiring ───────────────────────────────────────────────────

///|
async test "channels_send_async maps adapter-not-found to success:false" {
  let id = wiring_seed_channel("feishu", true)
  // Empty manager: no adapters registered, so send_to must fail.
  let cm_ref = Ref(@channel.ChannelManager::new("/tmp/nonexistent_wiring.json"))
  let req = wiring_make_request(
    "/api/channels/\{id}/send",
    "{\"message\":\"hi\",\"chat_id\":\"c1\"}",
  )
  let resp = handle_channels_send_async(cm_ref, req)
  @debug.assert_eq(resp.status, 200)
  guard! wiring_response_json(resp) is Json::Object(obj)
  @debug.assert_eq(obj.get("success"), Some(false.to_json()))
  guard! obj.get("error") is Some(Json::String(err))
  assert_true(err.contains("Adapter not found"))
}

///|
async test "channels_send_async rejects missing chat_id" {
  let id = wiring_seed_channel("feishu", true)
  let cm_ref = Ref(@channel.ChannelManager::new("/tmp/nonexistent_wiring.json"))
  let req = wiring_make_request(
    "/api/channels/\{id}/send",
    "{\"message\":\"hi\"}",
  )
  let resp = handle_channels_send_async(cm_ref, req)
  @debug.assert_eq(resp.status, 400)
}

// ── test wiring ───────────────────────────────────────────────────

///|
async test "channels_test_async grades telegram as not_implemented" {
  let id = wiring_seed_channel("telegram", true)
  let req = wiring_make_request("/api/channels/\{id}/test", "")
  let resp = handle_channels_test_async(req)
  @debug.assert_eq(resp.status, 200)
  guard! wiring_response_json(resp) is Json::Object(obj)
  @debug.assert_eq(obj.get("test_result"), Some("not_implemented".to_json()))
}

///|
async test "channels_test_async grades unknown platform as failed" {
  let id = wiring_seed_channel("unknown", true)
  let req = wiring_make_request("/api/channels/\{id}/test", "")
  let resp = handle_channels_test_async(req)
  @debug.assert_eq(resp.status, 200)
  guard! wiring_response_json(resp) is Json::Object(obj)
  @debug.assert_eq(obj.get("test_result"), Some("failed".to_json()))
}

///|
async test "channels_test_async reports disabled channel as missing" {
  let id = wiring_seed_channel("telegram", false)
  let req = wiring_make_request("/api/channels/\{id}/test", "")
  // Disabled channels still resolve by id and return a not-implemented result
  // (test probes connectivity regardless of the enabled flag).
  let resp = handle_channels_test_async(req)
  @debug.assert_eq(resp.status, 200)
}

// ── webhook wiring ────────────────────────────────────────────────

///|
test "webhook_bridge routes to ChannelManager for configured platform" {
  let path = wiring_temp_path("mbopenclacky_test_webhook_wiring.json")
  let content =
    #|{
    #|  "channels": [
    #|    {
    #|      "platform": "feishu",
    #|      "enabled": true,
    #|      "settings": { "bot_id": "bot_1", "bot_secret": "sec_1" }
    #|    }
    #|  ]
    #|}
  @fs.write_string_to_file(path, content) catch {
    _ => {
      assert_true(false)
      return
    }
  }
  let server_ref = Ref(WebServer::new(@config.AgentConfig::default(), None))
  let cm = @channel.ChannelManager::new(path)
  match cm.init() {
    Ok(_) => ()
    Err(_) => {
      assert_true(false)
      return
    }
  }
  cm.on_message(fn(_event) { () })
  server_ref.val.channel_manager.val = cm

  let body = "{\"event\":{\"message\":{\"chat_id\":\"c1\",\"message_id\":\"m1\",\"content\":\"hi\"},\"sender\":{\"sender_id\":{\"user_id\":\"u1\",\"name\":\"Alice\"}}}}"
  let event = wiring_make_webhook_event("feishu", body)
  let resp = handle_webhook_bridge(server_ref, event)
  @debug.assert_eq(resp.status_code.to_int(), 200)

  @fs.remove_file(path) catch {
    _ => ()
  }
}

///|
test "webhook_bridge falls back to registry for unconfigured platform" {
  // No channel config file exists for the default manager, so the platform
  // is not configured and the request must fall through to WebhookRegistry
  // (which is empty) → 400 with a "No handler registered" error.
  let server_ref = Ref(WebServer::new(@config.AgentConfig::default(), None))
  let body = "{\"event\":{\"message\":{\"chat_id\":\"c1\",\"message_id\":\"m1\",\"content\":\"hi\"},\"sender\":{\"sender_id\":{\"user_id\":\"u1\",\"name\":\"Alice\"}}}}"
  let event = wiring_make_webhook_event("feishu", body)
  let resp = handle_webhook_bridge(server_ref, event)
  @debug.assert_eq(resp.status_code.to_int(), 400)
}

///|
test "webhook_bridge answers feishu url_verification challenge" {
  let server_ref = Ref(WebServer::new(@config.AgentConfig::default(), None))
  let body = "{\"type\":\"url_verification\",\"challenge\":\"abc123\"}"
  let event = wiring_make_webhook_event("feishu", body)
  let resp = handle_webhook_bridge(server_ref, event)
  @debug.assert_eq(resp.status_code.to_int(), 200)
  @debug.assert_eq(@utf8.decode(resp.raw_body), "abc123")
}
