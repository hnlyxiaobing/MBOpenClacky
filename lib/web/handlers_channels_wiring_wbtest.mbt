///| White-box tests for channel wiring (stubfix-01 + channel single-source-of-
/// truth): real dispatch on the send/test API, config persistence through the
/// API, credential masking, and webhook routing into ChannelManager.
/// These tests exercise the breakpoints fixed by the wiring spec:
/// 1. send no longer returns a hard-coded success - it maps adapter lookup
///    failures to `success:false`.
/// 2. test grades connectivity honestly per platform instead of field-only
///    validation, using the platform's stored settings.
/// 3. webhook events route to ChannelManager::handle_webhook for configured
///    platforms instead of falling through to the empty WebhookRegistry.
/// 4. the panel's state is the manager's config file - so a change made
///    through the API is persisted and visible on reload.

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
/// Write a channel config file and return a manager over it with configs
/// loaded (production loads via ChannelManager::init; handlers rely on that).
fn wiring_manager_from(
  name : String,
  content : String,
) -> Ref[@channel.ChannelManager] {
  let path = wiring_temp_path(name)
  @fs.write_string_to_file(path, content) catch {
    _ => ()
  }
  let cm = @channel.ChannelManager::new(path)
  ignore(cm.load_config())
  Ref(cm)
}

///|
/// Manager over a fresh temp config holding one platform entry.
fn wiring_seed_manager(
  platform : String,
  enabled : Bool,
  settings_json : String,
) -> Ref[@channel.ChannelManager] {
  wiring_manager_from(
    "mbopenclacky_test_channels_cfg.json",
    "{\"channels\":[{\"platform\":\"\{platform}\",\"enabled\":\{enabled},\"settings\":\{settings_json}}]}",
  )
}

///|
/// Manager over a config path that does not exist (no channels configured).
fn wiring_empty_manager() -> Ref[@channel.ChannelManager] {
  let path = wiring_temp_path("mbopenclacky_test_channels_absent.json")
  @fs.remove_file(path) catch {
    _ => ()
  }
  let cm = @channel.ChannelManager::new(path)
  ignore(cm.load_config())
  Ref(cm)
}

///|
/// Parse a lib/web HttpResponse body as JSON (empty object on failure).
fn wiring_response_json(resp : HttpResponse) -> Json {
  @json.parse(resp.body) catch {
    _ => Json::object(Map([]))
  }
}

///|
/// Find the entry for a platform inside a `{channels:[...]}` response body.
fn wiring_find_channel(
  resp : HttpResponse,
  platform : String,
) -> Map[String, Json]? {
  guard! wiring_response_json(resp) is Json::Object(top)
  guard! top.get("channels") is Some(Json::Array(items))
  for item in items {
    guard! item is Json::Object(o)
    if o.get("platform") == Some(platform.to_json()) {
      return Some(o)
    }
  }
  None
}

///|
/// Build a POST HttpRequest targeting /api/channels/:id/... with a JSON body.
fn wiring_make_request(
  path : String,
  platform : String,
  body : String,
) -> HttpRequest {
  { http_method: POST, path, params: [("id", platform)], body, headers: [], }
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
  let cm_ref = wiring_seed_manager(
    "feishu", true, "{\"bot_id\":\"b\",\"bot_secret\":\"s\"}",
  )
  // Registry is empty: the platform is configured but no adapter was started.
  let req = wiring_make_request(
    "/api/channels/feishu/send", "feishu", "{\"message\":\"hi\",\"chat_id\":\"c1\"}",
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
  let cm_ref = wiring_seed_manager("feishu", true, "{\"bot_id\":\"b\"}")
  let req = wiring_make_request(
    "/api/channels/feishu/send", "feishu", "{\"message\":\"hi\"}",
  )
  let resp = handle_channels_send_async(cm_ref, req)
  @debug.assert_eq(resp.status, 400)
}

///|
async test "channels_send_async rejects an unconfigured platform" {
  let cm_ref = wiring_empty_manager()
  let req = wiring_make_request(
    "/api/channels/telegram/send", "telegram", "{\"message\":\"hi\",\"chat_id\":\"c1\"}",
  )
  let resp = handle_channels_send_async(cm_ref, req)
  @debug.assert_eq(resp.status, 404)
}

// ── test (connectivity probe) wiring ──────────────────────────────

///|
/// Every platform is probed for real using its stored settings, so a channel
/// configured without credentials must come back as a diagnostic failure --
/// never as "not_implemented" and never as a silent success.
async fn assert_probe_fails_without_credentials(platform : String) -> Unit {
  let cm_ref = wiring_seed_manager(platform, true, "{}")
  let req = wiring_make_request("/api/channels/\{platform}/test", platform, "")
  let resp = handle_channels_test_async(cm_ref, req)
  @debug.assert_eq(resp.status, 200)
  guard! wiring_response_json(resp) is Json::Object(obj)
  @debug.assert_eq(obj.get("test_result"), Some("failed".to_json()))
  guard! obj.get("error") is Some(Json::String(err))
  assert_true(err.contains("Missing"))
}

///|
async test "channels_test_async probes telegram and reports missing credentials" {
  assert_probe_fails_without_credentials("telegram")
}

///|
async test "channels_test_async probes wecom and reports missing credentials" {
  assert_probe_fails_without_credentials("wecom")
}

///|
async test "channels_test_async probes weixin and reports missing credentials" {
  assert_probe_fails_without_credentials("weixin")
}

///|
async test "channels_test_async probes dingtalk and reports missing credentials" {
  assert_probe_fails_without_credentials("dingtalk")
}

///|
async test "channels_test_async probes discord and reports missing credentials" {
  assert_probe_fails_without_credentials("discord")
}

///|
async test "channels_test_async probes feishu and reports missing credentials" {
  assert_probe_fails_without_credentials("feishu")
}

///|
async test "channels_test_async rejects an unknown platform" {
  let cm_ref = wiring_empty_manager()
  let req = wiring_make_request("/api/channels/slack/test", "slack", "")
  let resp = handle_channels_test_async(cm_ref, req)
  @debug.assert_eq(resp.status, 400)
}

///|
async test "channels_test_async reports unconfigured platforms as failed" {
  let cm_ref = wiring_empty_manager()
  let req = wiring_make_request("/api/channels/telegram/test", "telegram", "")
  let resp = handle_channels_test_async(cm_ref, req)
  @debug.assert_eq(resp.status, 200)
  guard! wiring_response_json(resp) is Json::Object(obj)
  @debug.assert_eq(obj.get("test_result"), Some("failed".to_json()))
  guard! obj.get("error") is Some(Json::String(err))
  assert_true(err.contains("not configured"))
}

///|
async test "channels_test_async still resolves a disabled channel" {
  let cm_ref = wiring_seed_manager("telegram", false, "{}")
  let req = wiring_make_request("/api/channels/telegram/test", "telegram", "")
  // The probe runs regardless of the enabled flag; the platform must still
  // resolve (200) rather than looking like a missing channel.
  let resp = handle_channels_test_async(cm_ref, req)
  @debug.assert_eq(resp.status, 200)
}

// ── list projection + persistence ─────────────────────────────────

///|
test "channels_list projects the manager's config, not a web-side store" {
  let cm_ref = wiring_seed_manager(
    "telegram", true, "{\"bot_token\":\"tok\",\"allowed_users\":\"\"}",
  )
  let resp = handle_channels_list(cm_ref)
  @debug.assert_eq(resp.status, 200)
  guard! wiring_find_channel(resp, "telegram") is Some(tg)
  @debug.assert_eq(tg.get("has_config"), Some(true.to_json()))
  @debug.assert_eq(tg.get("enabled"), Some(true.to_json()))
  @debug.assert_eq(tg.get("has_token"), Some(true.to_json()))
  // Unconfigured platforms stay honest.
  guard! wiring_find_channel(resp, "wecom") is Some(wc)
  @debug.assert_eq(wc.get("has_config"), Some(false.to_json()))
  @debug.assert_eq(wc.get("has_token"), Some(false.to_json()))
}

///|
test "channels_list never serializes credential values" {
  let cm_ref = wiring_seed_manager(
    "weixin", true, "{\"token\":\"secret-token\",\"uin\":\"secret-uin\",\"base_url\":\"https://ilink\"}",
  )
  let resp = handle_channels_list(cm_ref)
  let body = resp.body
  assert_false(body.contains("secret-token"))
  assert_false(body.contains("secret-uin"))
  assert_false(body.contains("\"token\":"))
  assert_false(body.contains("\"uin\":"))
  guard! wiring_find_channel(resp, "weixin") is Some(wx)
  @debug.assert_eq(wx.get("has_token"), Some(true.to_json()))
  @debug.assert_eq(wx.get("has_uin"), Some(true.to_json()))
  // non-secret settings pass through
  @debug.assert_eq(wx.get("base_url"), Some("https://ilink".to_json()))
}

///|
test "channels_list exposes platform parity fields when unconfigured" {
  let cm_ref = wiring_empty_manager()
  let resp = handle_channels_list(cm_ref)
  @debug.assert_eq(resp.status, 200)
  guard! wiring_find_channel(resp, "feishu") is Some(fs)
  assert_true(fs.get("app_id") is Some(_))
  assert_true(fs.get("domain") is Some(_))
  assert_true(fs.get("allowed_users") is Some(_))
  guard! wiring_find_channel(resp, "weixin") is Some(wx)
  assert_true(wx.get("base_url") is Some(_))
  assert_true(wx.get("token_updated_at") is Some(_))
}

///|
test "channels_toggle_enabled persists to the config file" {
  let cm_ref = wiring_seed_manager("telegram", true, "{\"bot_token\":\"tok\"}")
  let req = wiring_make_request(
    "/api/channels/telegram/enabled", "telegram", "{\"enabled\":false}",
  )
  let resp = handle_channels_update(cm_ref, req)
  @debug.assert_eq(resp.status, 200)
  // reload from disk: the change must survive
  let reloaded = @channel.ChannelManager::new(cm_ref.val.config_path)
  match reloaded.load_config() {
    Ok(_) => ()
    Err(_) => assert_true(false)
  }
  match reloaded.find_platform("telegram") {
    Some(cfg) => {
      assert_false(cfg.enabled)
      @debug.assert_eq(cfg.settings.get("bot_token"), Some("tok"))
    }
    None => assert_true(false)
  }
}

///|
test "channels_toggle_enabled reports runtime state honestly" {
  let cm_ref = wiring_seed_manager("telegram", true, "{\"bot_token\":\"tok\"}")
  let req = wiring_make_request(
    "/api/channels/telegram/enabled", "telegram", "{\"enabled\":false}",
  )
  let resp = handle_channels_update(cm_ref, req)
  // No message handler in this test, so the runtime cannot be re-applied; the
  // response must say so instead of claiming success.
  guard! wiring_response_json(resp) is Json::Object(obj)
  guard! obj.get("runtime") is Some(Json::String(note))
  assert_true(note.contains("runtime apply failed"))
}

///|
test "channels_create persists full platform settings" {
  let cm_ref = wiring_empty_manager()
  let body = "{\"platform\":\"weixin\",\"settings\":{\"token\":\"tok\",\"uin\":\"1234\",\"base_url\":\"https://ilink\"}}"
  let req = wiring_make_request("/api/channels", "weixin", body)
  let resp = handle_channels_create(cm_ref, req)
  @debug.assert_eq(resp.status, 201)
  let reloaded = @channel.ChannelManager::new(cm_ref.val.config_path)
  match reloaded.load_config() {
    Ok(_) => ()
    Err(_) => assert_true(false)
  }
  match reloaded.find_platform("weixin") {
    Some(cfg) => {
      assert_true(cfg.enabled)
      @debug.assert_eq(cfg.settings.get("uin"), Some("1234"))
      @debug.assert_eq(cfg.settings.get("base_url"), Some("https://ilink"))
    }
    None => assert_true(false)
  }
}

///|
test "channels_create rejects an invalid platform" {
  let cm_ref = wiring_empty_manager()
  let req = wiring_make_request(
    "/api/channels", "slack", "{\"platform\":\"slack\"}",
  )
  let resp = handle_channels_create(cm_ref, req)
  @debug.assert_eq(resp.status, 400)
}

///|
test "channels_delete removes the platform from the config file" {
  let cm_ref = wiring_seed_manager("telegram", true, "{\"bot_token\":\"tok\"}")
  let req = wiring_make_request("/api/channels/telegram", "telegram", "")
  let resp = handle_channels_delete(cm_ref, req)
  @debug.assert_eq(resp.status, 204)
  let reloaded = @channel.ChannelManager::new(cm_ref.val.config_path)
  match reloaded.load_config() {
    Ok(_) => ()
    Err(_) => assert_true(false)
  }
  assert_true(reloaded.find_platform("telegram") is None)
}

///|
test "channels_update on an unknown platform is a 404" {
  let cm_ref = wiring_empty_manager()
  let req = wiring_make_request(
    "/api/channels/telegram/enabled", "telegram", "{\"enabled\":true}",
  )
  let resp = handle_channels_update(cm_ref, req)
  @debug.assert_eq(resp.status, 404)
}

///|
test "channels_status is projected from the manager" {
  let cm_ref = wiring_seed_manager(
    "telegram", true, "{\"bot_token\":\"SECRET-TOK-VALUE\"}",
  )
  let req = wiring_make_request("/api/channels/telegram/status", "telegram", "")
  let resp = handle_channels_status(cm_ref, req)
  @debug.assert_eq(resp.status, 200)
  guard! wiring_response_json(resp) is Json::Object(obj)
  @debug.assert_eq(obj.get("platform"), Some("telegram".to_json()))
  @debug.assert_eq(obj.get("has_config"), Some(true.to_json()))
  @debug.assert_eq(obj.get("has_token"), Some(true.to_json()))
  assert_false(resp.body.contains("SECRET-TOK-VALUE"))
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
