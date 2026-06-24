///| Tests for the channel package: types, adapters, registry, manager, and platform APIs.

// ── Platform & EventType Tests ──────────────────────────────────────────────

///|
test "platform_enum_variants" {
  let platforms = [
    Platform::Feishu,
    Platform::WeCom,
    Platform::Weixin,
    Platform::Telegram,
    Platform::Discord,
    Platform::DingTalk,
  ]
  assert_eq(platforms.length(), 6)
  assert_eq(Platform::Feishu.to_string_value(), "feishu")
  assert_eq(Platform::WeCom.to_string_value(), "wecom")
  assert_eq(Platform::Weixin.to_string_value(), "weixin")
  assert_eq(Platform::Telegram.to_string_value(), "telegram")
  assert_eq(Platform::Discord.to_string_value(), "discord")
  assert_eq(Platform::DingTalk.to_string_value(), "dingtalk")
}

///|
test "event_type_variants" {
  let types = [
    EventType::Message,
    EventType::Command,
    EventType::Join,
    EventType::Leave,
  ]
  assert_eq(types.length(), 4)
  assert_true(EventType::Message == EventType::Message)
  assert_true(EventType::Command != EventType::Message)
}

// ── ChannelEvent Tests ──────────────────────────────────────────────────────

///|
test "channel_event_creation" {
  let event : ChannelEvent = {
    event_type: EventType::Message,
    platform: Platform::Feishu,
    chat_id: "chat_001",
    message_id: "msg_001",
    sender_id: "user_001",
    sender_name: "Alice",
    text: "Hello world",
    attachments: [],
    timestamp: 1700000000,
    reply_to: None,
    chat_type: ChatType::Direct,
    raw: None,
    observe_only: false,
  }
  assert_eq(event.chat_id, "chat_001")
  assert_eq(event.sender_name, "Alice")
  assert_eq(event.text, "Hello world")
  assert_true(event.platform == Platform::Feishu)
  assert_eq(event.timestamp, 1700000000)
}

// ── SendResult Tests ────────────────────────────────────────────────────────

///|
test "send_result_success" {
  let result : SendResult = {
    message_id: "msg_123",
    success: true,
    error: None,
  }
  assert_true(result.success)
  assert_eq(result.message_id, "msg_123")
  assert_true(result.error is None)
}

///|
test "send_result_error" {
  let result : SendResult = {
    message_id: "",
    success: false,
    error: Some("Network timeout"),
  }
  assert_false(result.success)
  assert_true(result.error == Some("Network timeout"))
}

// ── AdapterRegistry Tests ───────────────────────────────────────────────────

///|
test "adapter_registry_new" {
  let registry = AdapterRegistry::new()
  assert_eq(registry.size(), 0)
}

///|
test "adapter_registry_register" {
  let registry = AdapterRegistry::new()
  let config : ChannelConfig = {
    platform: Platform::Feishu,
    enabled: true,
    settings: { "bot_id": "test_id", "bot_secret": "test_secret" },
  }
  let adapter = FeishuAdapter::new(config)
  match adapter {
    Ok(a) => {
      registry.register("feishu", AnyAdapter::Feishu(a))
      assert_eq(registry.size(), 1)
    }
    Err(_) => assert_true(false)
  }
}

///|
test "adapter_registry_find" {
  let registry = AdapterRegistry::new()
  let config : ChannelConfig = {
    platform: Platform::Telegram,
    enabled: true,
    settings: { "bot_token": "123:ABC" },
  }
  let adapter = TelegramAdapter::new(config)
  match adapter {
    Ok(a) => {
      registry.register("telegram", AnyAdapter::Telegram(a))
      assert_true(registry.find("telegram") is Some(_))
      assert_true(registry.find("unknown") is None)
    }
    Err(_) => assert_true(false)
  }
}

///|
test "adapter_registry_list_names" {
  let registry = AdapterRegistry::new()
  let config1 : ChannelConfig = {
    platform: Platform::Feishu,
    enabled: true,
    settings: { "bot_id": "id1", "bot_secret": "secret1" },
  }
  let config2 : ChannelConfig = {
    platform: Platform::Telegram,
    enabled: true,
    settings: { "bot_token": "token1" },
  }
  match (FeishuAdapter::new(config1), TelegramAdapter::new(config2)) {
    (Ok(a1), Ok(a2)) => {
      registry.register("feishu", AnyAdapter::Feishu(a1))
      registry.register("telegram", AnyAdapter::Telegram(a2))
      let names = registry.list_names()
      assert_eq(names.length(), 2)
    }
    _ => assert_true(false)
  }
}

///|
test "adapter_registry_has" {
  let registry = AdapterRegistry::new()
  let config : ChannelConfig = {
    platform: Platform::Discord,
    enabled: true,
    settings: { "bot_token": "disc_token" },
  }
  match DiscordAdapter::new(config) {
    Ok(a) => {
      registry.register("discord", AnyAdapter::Discord(a))
      assert_true(registry.has("discord"))
      assert_false(registry.has("telegram"))
    }
    Err(_) => assert_true(false)
  }
}

// ── ChannelManager Tests ────────────────────────────────────────────────────

///|
test "channel_manager_new" {
  let mgr = ChannelManager::new("/tmp/channels.yml")
  assert_eq(mgr.config_path, "/tmp/channels.yml")
  assert_eq(mgr.active_channels.length(), 0)
  assert_eq(mgr.configs.length(), 0)
}

///|
test "channel_manager_status_empty" {
  let mgr = ChannelManager::new("/tmp/channels.yml")
  let status = mgr.status()
  assert_eq(status.length(), 0)
}

// ── FeishuAdapter Tests ─────────────────────────────────────────────────────

///|
test "feishu_adapter_new" {
  let config : ChannelConfig = {
    platform: Platform::Feishu,
    enabled: true,
    settings: { "bot_id": "my_bot", "bot_secret": "my_secret" },
  }
  match FeishuAdapter::new(config) {
    Ok(a) => {
      assert_eq(a.bot_id, "my_bot")
      assert_eq(a.bot_secret, "my_secret")
      assert_false(a.is_running)
    }
    Err(_) => assert_true(false)
  }
}

///|
test "feishu_validate_config_valid" {
  let config : ChannelConfig = {
    platform: Platform::Feishu,
    enabled: true,
    settings: { "bot_id": "valid_id", "bot_secret": "valid_secret" },
  }
  match FeishuAdapter::new(config) {
    Ok(a) => {
      let errors = a.validate_config()
      assert_eq(errors.length(), 0)
    }
    Err(_) => assert_true(false)
  }
}

///|
test "feishu_validate_config_missing_fields" {
  let config : ChannelConfig = {
    platform: Platform::Feishu,
    enabled: true,
    settings: { "bot_id": "", "bot_secret": "" },
  }
  match FeishuAdapter::new(config) {
    Ok(a) => {
      let errors = a.validate_config()
      assert_eq(errors.length(), 2)
    }
    Err(_) => assert_true(false)
  }
}

///|
test "feishu_supports_updates" {
  let config : ChannelConfig = {
    platform: Platform::Feishu,
    enabled: true,
    settings: { "bot_id": "id", "bot_secret": "secret" },
  }
  match FeishuAdapter::new(config) {
    Ok(a) => assert_true(a.supports_message_updates())
    Err(_) => assert_true(false)
  }
}

// ── WeComAdapter Tests ──────────────────────────────────────────────────────

///|
test "wecom_adapter_new" {
  let config : ChannelConfig = {
    platform: Platform::WeCom,
    enabled: true,
    settings: { "corp_id": "corp1", "agent_id": "agent1", "secret": "sec1" },
  }
  match WeComAdapter::new(config) {
    Ok(a) => {
      assert_eq(a.corp_id, "corp1")
      assert_eq(a.agent_id, "agent1")
      assert_eq(a.secret, "sec1")
      assert_false(a.is_running)
    }
    Err(_) => assert_true(false)
  }
}

// ── TelegramAdapter Tests ───────────────────────────────────────────────────

///|
test "telegram_adapter_new" {
  let config : ChannelConfig = {
    platform: Platform::Telegram,
    enabled: true,
    settings: { "bot_token": "123456:ABC-DEF" },
  }
  match TelegramAdapter::new(config) {
    Ok(a) => {
      assert_eq(a.bot_token, "123456:ABC-DEF")
      assert_false(a.is_running)
      assert_eq(a.last_update_id, 0)
    }
    Err(_) => assert_true(false)
  }
}

// ── DiscordAdapter Tests ────────────────────────────────────────────────────

///|
test "discord_adapter_new" {
  let config : ChannelConfig = {
    platform: Platform::Discord,
    enabled: true,
    settings: { "bot_token": "disc_token_123", "application_id": "app_id_1" },
  }
  match DiscordAdapter::new(config) {
    Ok(a) => {
      assert_eq(a.bot_token, "disc_token_123")
      assert_true(a.application_id == Some("app_id_1"))
      assert_false(a.is_running)
    }
    Err(_) => assert_true(false)
  }
}

// ── DingTalkAdapter Tests ───────────────────────────────────────────────────

///|
test "dingtalk_adapter_new" {
  let config : ChannelConfig = {
    platform: Platform::DingTalk,
    enabled: true,
    settings: { "access_token": "dt_token_abc" },
  }
  match DingTalkAdapter::new(config) {
    Ok(a) => {
      assert_eq(a.access_token, "dt_token_abc")
      assert_false(a.is_running)
      assert_false(a.supports_message_updates())
    }
    Err(_) => assert_true(false)
  }
}

// ── WeixinAdapter Tests ─────────────────────────────────────────────────────

///|
test "weixin_adapter_new" {
  let config : ChannelConfig = {
    platform: Platform::Weixin,
    enabled: true,
    settings: { "app_id": "wx_app", "app_secret": "wx_sec", "token": "wx_tok" },
  }
  match WeixinAdapter::new(config) {
    Ok(a) => {
      assert_eq(a.app_id, "wx_app")
      assert_eq(a.app_secret, "wx_sec")
      assert_eq(a.token, "wx_tok")
      assert_false(a.is_running)
      assert_false(a.supports_message_updates())
    }
    Err(_) => assert_true(false)
  }
}

// ── ChannelConfig Tests ─────────────────────────────────────────────────────

///|
test "channel_config_creation" {
  let config : ChannelConfig = {
    platform: Platform::Telegram,
    enabled: true,
    settings: { "bot_token": "token_value" },
  }
  assert_true(config.platform == Platform::Telegram)
  assert_true(config.enabled)
  assert_true(config.settings.get("bot_token") == Some("token_value"))
}

// ── Attachment Tests ────────────────────────────────────────────────────────

///|
test "attachment_types" {
  let att : Attachment = {
    attachment_type: AttachmentType::Image,
    url: "https://example.com/img.png",
    filename: Some("img.png"),
    size_bytes: Some(1024),
  }
  assert_true(att.attachment_type == AttachmentType::Image)
  assert_eq(att.url, "https://example.com/img.png")
  assert_true(att.filename == Some("img.png"))
  assert_true(att.size_bytes == Some(1024))
}

// ── Build Message Tests ─────────────────────────────────────────────────────

///|
test "build_feishu_message" {
  let msg = build_feishu_message("Hello Feishu", None)
  match msg {
    Object(obj) => {
      assert_true(obj.get("msg_type") == Some("text".to_json()))
      match obj.get("content") {
        Some(Object(content)) =>
          assert_true(content.get("text") == Some("Hello Feishu".to_json()))
        _ => assert_true(false)
      }
    }
    _ => assert_true(false)
  }
}

// ── ChannelError Tests ──────────────────────────────────────────────────────

///|
test "channel_error_display" {
  let config : ChannelConfig = {
    platform: Platform::Feishu,
    enabled: true,
    settings: {},
  }
  let result = FeishuAdapter::new(config)
  match result {
    Ok(_) => assert_true(false)
    Err(ChannelError(msg)) => assert_true(msg.contains("bot_id"))
  }
}

// ── Webhook & Dedup Tests ──────────────────────────────────────────────────

///|
test "channel_manager_handle_webhook_unknown_platform" {
  let mgr = ChannelManager::new("/tmp/channels.yml")
  mgr.on_message(fn(_event) { () })
  let body = @json.parse("{}") catch { _ => Json::object({}) }
  let result = mgr.handle_webhook("unknown", body)
  match result {
    Ok(_) => assert_true(false)
    Err(ChannelError(msg)) => assert_true(msg.contains("Unknown platform"))
  }
}

///|
test "channel_manager_handle_webhook_no_handler" {
  let mgr = ChannelManager::new("/tmp/channels.yml")
  let feishu_event = "{\"event\":{\"message\":{\"chat_id\":\"c1\",\"message_id\":\"m1\",\"content\":\"hi\"},\"sender\":{\"sender_id\":{\"user_id\":\"u1\",\"name\":\"Alice\"}}}}"
  let json = @json.parse(feishu_event) catch { _ => Json::object({}) }
  let result = mgr.handle_webhook("feishu", json)
  match result {
    Ok(_) => assert_true(false)
    Err(ChannelError(msg)) => assert_true(msg.contains("handler"))
  }
}

///|
test "channel_manager_dedup" {
  let mgr = ChannelManager::new("/tmp/channels.yml")
  let mut received = 0
  mgr.on_message(fn(_event) { received = received + 1 })
  let event_json = "{\"event\":{\"message\":{\"chat_id\":\"c1\",\"message_id\":\"m1\",\"content\":\"hi\"},\"sender\":{\"sender_id\":{\"user_id\":\"u1\",\"name\":\"Alice\"}}}}"
  let json = @json.parse(event_json) catch { _ => Json::object({}) }
  let _ = mgr.handle_webhook("feishu", json)
  // Second call with same digest should be deduped
  let _ = mgr.handle_webhook("feishu", json)
  assert_eq(received, 1)
}

///|
test "feishu_challenge_verification" {
  let challenge_json = "{\"type\":\"url_verification\",\"challenge\":\"test_challenge_string\"}"
  let json = @json.parse(challenge_json) catch { _ => Json::object({}) }
  match handle_feishu_challenge(json) {
    Some(c) => assert_eq(c, "test_challenge_string")
    None => assert_true(false)
  }
}

///|
test "feishu_challenge_non_verification" {
  let event_json = "{\"type\":\"event_callback\",\"event\":{}}"
  let json = @json.parse(event_json) catch { _ => Json::object({}) }
  match handle_feishu_challenge(json) {
    Some(_) => assert_true(false)
    None => assert_true(true) // Should return None for non-verification events
  }
}

///|
test "channel_manager_register_adapter" {
  let mgr = ChannelManager::new("/tmp/channels.yml")
  let config : ChannelConfig = {
    platform: Platform::Telegram,
    enabled: true,
    settings: { "bot_token": "test_token" },
  }
  match TelegramAdapter::new(config) {
    Ok(a) => {
      mgr.register_adapter("telegram", AnyAdapter::Telegram(a))
      assert_true(mgr.registry.has("telegram"))
    }
    Err(_) => assert_true(false)
  }
}

// ════════════════════════════════════════════════════════════════════════════
// NEW TESTS: HTTP Helper, Telegram, Discord, Feishu, WeCom, DingTalk, Weixin
// ════════════════════════════════════════════════════════════════════════════

// ── HTTP Helper: TokenCache ─────────────────────────────────────────────────

///|
test "token_cache_new_is_invalid" {
  let tc = TokenCache::new(5000)
  assert_false(tc.is_valid())
  assert_eq(tc.token, "")
}

///|
test "token_cache_set_and_valid" {
  let tc = TokenCache::new(5000)
  tc.set("mytoken", 7200000)
  assert_true(tc.is_valid())
  assert_eq(tc.token, "mytoken")
  assert_eq(tc.expires_at, 7200000)
}

///|
test "token_cache_clear" {
  let tc = TokenCache::new(5000)
  tc.set("tok", 100)
  assert_true(tc.is_valid())
  tc.clear()
  assert_false(tc.is_valid())
  assert_eq(tc.token, "")
  assert_eq(tc.expires_at, 0)
}

///|
test "token_cache_get_or_refresh_empty" {
  let tc = TokenCache::new(5000)
  let result = tc.get_or_refresh("new_tok", 3600)
  assert_eq(result, "new_tok")
  assert_eq(tc.token, "new_tok")
}

///|
test "token_cache_get_or_refresh_cached" {
  let tc = TokenCache::new(5000)
  tc.set("cached_tok", 9999)
  let result = tc.get_or_refresh("ignored", 100)
  assert_eq(result, "cached_tok")
}

// ── HTTP Helper: HttpHeaders ────────────────────────────────────────────────

///|
test "http_headers_new_empty" {
  let h = HttpHeaders::new()
  let arr = h.to_array()
  assert_eq(arr.length(), 0)
}

///|
test "http_headers_set" {
  let h = HttpHeaders::new().set("X-Custom", "value1")
  let arr = h.to_array()
  assert_eq(arr.length(), 1)
  assert_true(
    arr.any(fn(pair) {
      let (k, _v) = pair
      k == "X-Custom"
    }),
  )
}

///|
test "http_headers_bearer" {
  let h = HttpHeaders::new().bearer("mytoken")
  let arr = h.to_array()
  assert_true(
    arr.any(fn(pair) {
      let (k, v) = pair
      k == "Authorization" && v == "Bearer mytoken"
    }),
  )
}

///|
test "http_headers_bot_token" {
  let h = HttpHeaders::new().bot_token("bottoken")
  let arr = h.to_array()
  assert_true(
    arr.any(fn(pair) {
      let (k, v) = pair
      k == "Authorization" && v == "Bot bottoken"
    }),
  )
}

///|
test "http_headers_content_type" {
  let h = HttpHeaders::new().content_type("application/json")
  let arr = h.to_array()
  assert_true(
    arr.any(fn(pair) {
      let (k, v) = pair
      k == "Content-Type" && v == "application/json"
    }),
  )
}

///|
test "http_headers_chain" {
  let h = HttpHeaders::new()
    .bearer("tok")
    .content_type("application/json")
    .set("Accept", "*/*")
  let arr = h.to_array()
  assert_eq(arr.length(), 3)
}

// ── HTTP Helper: build_json_body / parse_json_response ──────────────────────

///|
test "build_json_body_produces_json" {
  let payload : Map[String, Json] = {}
  payload.set("key", "value".to_json())
  let body = build_json_body(payload)
  assert_true(body.contains("key"))
  assert_true(body.contains("value"))
}

///|
test "parse_json_response_success" {
  let result = parse_json_response("{\"ok\":true}")
  assert_true(result is Ok(_))
}

///|
test "parse_json_response_invalid" {
  let result = parse_json_response("not-json-at-all")
  assert_true(result is Err(_))
}

// ── HTTP Helper: extract_api_error ──────────────────────────────────────────

///|
test "extract_api_error_error_field" {
  let json = @json.parse("{\"error\":\"bad token\"}") catch {
    _ => Json::object({})
  }
  assert_eq(extract_api_error(json), "bad token")
}

///|
test "extract_api_error_message_field" {
  let json = @json.parse("{\"message\":\"rate limited\"}") catch {
    _ => Json::object({})
  }
  assert_eq(extract_api_error(json), "rate limited")
}

///|
test "extract_api_error_msg_field_feishu" {
  let json = @json.parse("{\"msg\":\"invalid app_id\"}") catch {
    _ => Json::object({})
  }
  assert_eq(extract_api_error(json), "invalid app_id")
}

///|
test "extract_api_error_errmsg_field_wecom" {
  let json = @json.parse("{\"errmsg\":\"access denied\"}") catch {
    _ => Json::object({})
  }
  assert_eq(extract_api_error(json), "access denied")
}

///|
test "extract_api_error_nested" {
  let json = @json.parse("{\"error\":{\"message\":\"nested error\"}}") catch {
    _ => Json::object({})
  }
  assert_eq(extract_api_error(json), "nested error")
}

///|
test "extract_api_error_unknown" {
  let json = @json.parse("{\"code\":500}") catch { _ => Json::object({}) }
  assert_eq(extract_api_error(json), "Unknown API error")
}

// ── HTTP Helper: status helpers ─────────────────────────────────────────────

///|
test "is_success_status_2xx" {
  assert_true(is_success_status(200))
  assert_true(is_success_status(201))
  assert_true(is_success_status(299))
  assert_false(is_success_status(300))
  assert_false(is_success_status(400))
  assert_false(is_success_status(500))
}

///|
test "should_retry_status_codes" {
  assert_true(should_retry_status(429))
  assert_true(should_retry_status(500))
  assert_true(should_retry_status(502))
  assert_true(should_retry_status(503))
  assert_false(should_retry_status(400))
  assert_false(should_retry_status(401))
  assert_false(should_retry_status(404))
}

///|
test "http_status_error_known_codes" {
  let e401 = http_status_error(401, "{}")
  match e401 {
    ChannelError(msg) => assert_true(msg.contains("Unauthorized"))
  }
  let e429 = http_status_error(429, "{}")
  match e429 {
    ChannelError(msg) => assert_true(msg.contains("Rate Limited"))
  }
}

///|
test "http_status_error_unknown_code" {
  let e = http_status_error(418, "I'm a teapot")
  match e {
    ChannelError(msg) => assert_true(msg.contains("418"))
  }
}

// ── HTTP Helper: RetryConfig ────────────────────────────────────────────────

///|
test "retry_config_default" {
  let rc = RetryConfig::default()
  assert_eq(rc.max_retries, 3)
  assert_eq(rc.base_delay_ms, 1000)
}

///|
test "retry_config_delay_exponential" {
  let rc = RetryConfig::default()
  assert_eq(rc.delay_for_attempt(0), 1000)
  assert_eq(rc.delay_for_attempt(1), 2000)
  assert_eq(rc.delay_for_attempt(2), 4000)
}

// ── HTTP Helper: webhook_url ────────────────────────────────────────────────

///|
test "webhook_url_build" {
  assert_eq(
    webhook_url("https://example.com", "telegram"),
    "https://example.com/api/webhooks/telegram",
  )
  assert_eq(
    webhook_url("https://example.com/", "discord"),
    "https://example.com/api/webhooks/discord",
  )
}

// ── Telegram: ApiClient & URL building ──────────────────────────────────────

///|
test "telegram_api_client_new" {
  let client = TelegramApiClient::new("BOT_TOK")
  assert_eq(client.bot_token, "BOT_TOK")
  assert_eq(client.base_url, "https://api.telegram.org")
}

///|
test "telegram_api_url" {
  let client = TelegramApiClient::new("TOK123")
  assert_eq(client.api_url("getMe"), "https://api.telegram.org/botTOK123/getMe")
  assert_eq(
    client.get_updates_url(),
    "https://api.telegram.org/botTOK123/getUpdates",
  )
  assert_eq(
    client.send_message_url(),
    "https://api.telegram.org/botTOK123/sendMessage",
  )
  assert_eq(
    client.edit_message_url(),
    "https://api.telegram.org/botTOK123/editMessageText",
  )
}

// ── Telegram: parse_updates_response ────────────────────────────────────────

///|
test "telegram_parse_updates_ok" {
  let json = @json.parse(
    "{\"ok\":true,\"result\":[{\"update_id\":1},{\"update_id\":2}]}",
  ) catch {
    _ => Json::object({})
  }
  match TelegramApiClient::parse_updates_response(json) {
    Ok(arr) => assert_eq(arr.length(), 2)
    Err(_) => assert_true(false)
  }
}

///|
test "telegram_parse_updates_error" {
  let json = @json.parse("{\"ok\":false,\"description\":\"Unauthorized\"}") catch {
    _ => Json::object({})
  }
  match TelegramApiClient::parse_updates_response(json) {
    Ok(_) => assert_true(false)
    Err(ChannelError(msg)) => assert_true(msg.contains("Unauthorized"))
  }
}

// ── Telegram: build requests ────────────────────────────────────────────────

///|
test "build_telegram_send_request_basic" {
  let payload = build_telegram_send_request("chat1", "hello", None, None)
  match payload {
    Object(obj) => {
      assert_eq(obj.get("chat_id"), Some("chat1".to_json()))
      assert_eq(obj.get("text"), Some("hello".to_json()))
      assert_true(obj.get("reply_to_message_id") is None)
    }
    _ => assert_true(false)
  }
}

///|
test "build_telegram_send_request_with_reply" {
  let payload = build_telegram_send_request(
    "c1",
    "reply text",
    Some("msg99"),
    Some("Markdown"),
  )
  match payload {
    Object(obj) => {
      assert_eq(obj.get("reply_to_message_id"), Some("msg99".to_json()))
      assert_eq(obj.get("parse_mode"), Some("Markdown".to_json()))
    }
    _ => assert_true(false)
  }
}

///|
test "build_telegram_edit_request" {
  let payload = build_telegram_edit_request("c1", "msg42", "new text")
  match payload {
    Object(obj) => {
      assert_eq(obj.get("message_id"), Some("msg42".to_json()))
      assert_eq(obj.get("text"), Some("new text".to_json()))
      assert_eq(obj.get("parse_mode"), Some("Markdown".to_json()))
    }
    _ => assert_true(false)
  }
}

// ── Telegram: split_telegram_message ────────────────────────────────────────

///|
test "split_telegram_short_no_split" {
  let chunks = split_telegram_message("short text")
  assert_eq(chunks.length(), 1)
  assert_eq(chunks[0], "short text")
}

///|
test "split_telegram_exact_boundary" {
  // Exactly 4096 chars: no split
  let exact = "a".repeat(4096)
  let chunks = split_telegram_message(exact)
  assert_eq(chunks.length(), 1)
}

///|
test "split_telegram_long_split" {
  // 5000 chars should split
  let long_msg = "x".repeat(5000)
  let chunks = split_telegram_message(long_msg)
  assert_true(chunks.length() >= 2)
}

// ── Telegram: detect_chat_type ──────────────────────────────────────────────

///|
test "detect_chat_type_private" {
  let msg : Map[String, Json] = {
    "chat": Json::object({ "type": "private".to_json() }),
  }
  assert_true(detect_chat_type(msg) == ChatType::Direct)
}

///|
test "detect_chat_type_group" {
  let msg : Map[String, Json] = {
    "chat": Json::object({ "type": "group".to_json() }),
  }
  assert_true(detect_chat_type(msg) == ChatType::Group)
}

///|
test "detect_chat_type_no_chat" {
  let msg : Map[String, Json] = {}
  assert_true(detect_chat_type(msg) == ChatType::Direct)
}

// ── Telegram: is_bot_mention ────────────────────────────────────────────────

///|
test "is_bot_mention_command" {
  assert_true(is_bot_mention("/start", None))
  assert_true(is_bot_mention("/help@mybot", Some("mybot")))
}

///|
test "is_bot_mention_at_username" {
  assert_true(is_bot_mention("hello @mybot", Some("mybot")))
  assert_false(is_bot_mention("hello world", Some("mybot")))
  assert_false(is_bot_mention("hello", None))
}

// ── Telegram: build_telegram_file_url ───────────────────────────────────────

///|
test "build_telegram_file_url" {
  let url = build_telegram_file_url("TOK", "photos/abc.jpg")
  assert_eq(url, "https://api.telegram.org/file/botTOK/photos/abc.jpg")
}

// ── Telegram: parse_event ───────────────────────────────────────────────────

///|
test "telegram_parse_event_text_message" {
  let update_json = @json.parse(
    "{\"update_id\":100,\"message\":{\"message_id\":42,\"chat\":{\"id\":123,\"type\":\"private\"},\"from\":{\"id\":5,\"first_name\":\"Bob\"},\"text\":\"hi\",\"date\":1700000000}}",
  ) catch {
    _ => Json::object({})
  }
  match TelegramAdapter::parse_event(update_json) {
    Ok(evt) => {
      assert_eq(evt.chat_id, "123")
      assert_eq(evt.message_id, "42")
      assert_eq(evt.sender_name, "Bob")
      assert_eq(evt.text, "hi")
      assert_true(evt.chat_type == ChatType::Direct)
      assert_true(evt.platform == Platform::Telegram)
    }
    Err(_) => assert_true(false)
  }
}

///|
test "telegram_parse_event_missing_message" {
  let json = @json.parse("{\"update_id\":1}") catch { _ => Json::object({}) }
  assert_true(TelegramAdapter::parse_event(json) is Err(_))
}

// ── Discord: DiscordApiClient ───────────────────────────────────────────────

///|
test "discord_api_client_new" {
  let client = DiscordApiClient::new("DISC_TOK")
  assert_eq(client.bot_token, "DISC_TOK")
  assert_eq(client.base_url, "https://discord.com/api/v10")
}

///|
test "discord_api_url_build" {
  let client = DiscordApiClient::new("TOK")
  assert_eq(
    client.api_url("channels/123/messages"),
    "https://discord.com/api/v10/channels/123/messages",
  )
}

///|
test "discord_api_url_strip_slashes" {
  let client = DiscordApiClient::with_base_url("TOK", "https://example.com/")
  assert_eq(client.api_url("/users/@me"), "https://example.com/users/@me")
}

// ── Discord: payload builders ───────────────────────────────────────────────

///|
test "build_discord_send_payload_basic" {
  let payload = build_discord_send_payload("hello discord", None)
  match payload {
    Object(obj) => {
      assert_eq(obj.get("content"), Some("hello discord".to_json()))
      assert_true(obj.get("message_reference") is None)
    }
    _ => assert_true(false)
  }
}

///|
test "build_discord_send_payload_reply" {
  let payload = build_discord_send_payload("reply", Some("msg123"))
  match payload {
    Object(obj) =>
      match obj.get("message_reference") {
        Some(Object(ref_obj)) =>
          assert_eq(ref_obj.get("message_id"), Some("msg123".to_json()))
        _ => assert_true(false)
      }
    _ => assert_true(false)
  }
}

///|
test "build_discord_edit_payload" {
  let payload = build_discord_edit_payload("edited text")
  match payload {
    Object(obj) => assert_eq(obj.get("content"), Some("edited text".to_json()))
    _ => assert_true(false)
  }
}

// ── Discord Gateway: opcodes ────────────────────────────────────────────────

///|
test "gateway_opcode_roundtrip" {
  let ops = [
    GatewayOpcode::Dispatch,
    GatewayOpcode::Heartbeat,
    GatewayOpcode::Identify,
    GatewayOpcode::Resume,
    GatewayOpcode::Hello,
    GatewayOpcode::HeartbeatAck,
  ]
  for op in ops {
    let i = op.to_int()
    match gateway_opcode_from_int(i) {
      Some(roundtripped) => assert_true(roundtripped == op)
      None => assert_true(false)
    }
  }
}

///|
test "gateway_opcode_from_int_unknown" {
  assert_true(gateway_opcode_from_int(99) is None)
}

// ── Discord Gateway: state lifecycle ────────────────────────────────────────

///|
test "gateway_state_new" {
  let state = GatewayState::new("TOK")
  assert_false(state.is_connected)
  assert_false(state.is_ready)
  assert_eq(state.reconnect_attempts, 0)
  assert_true(state.session_id is None)
}

///|
test "gateway_state_hello_and_ready" {
  let state = GatewayState::new("TOK")
  state.handle_hello(45000)
  assert_true(state.is_connected)
  assert_eq(state.heartbeat_interval, 45000)
  state.handle_ready("sess_abc", Some("wss://resume.gg"))
  assert_true(state.is_ready)
  assert_eq(state.session_id, Some("sess_abc"))
  assert_eq(state.resume_gateway_url, Some("wss://resume.gg"))
}

///|
test "gateway_should_resume" {
  let state = GatewayState::new("TOK")
  assert_false(should_resume(state))
  state.handle_ready("s1", None)
  state.update_seq(5)
  assert_true(should_resume(state))
}

///|
test "gateway_get_gateway_url" {
  let state = GatewayState::new("TOK")
  assert_eq(get_gateway_url(state), DISCORD_GATEWAY_URL)
  state.resume_gateway_url = Some("wss://custom.gg")
  assert_eq(get_gateway_url(state), "wss://custom.gg")
}

// ── Discord Gateway: fatal close / reconnect ────────────────────────────────

///|
test "is_fatal_close_codes" {
  assert_true(is_fatal_close(4004))
  assert_true(is_fatal_close(4014))
  assert_false(is_fatal_close(4000))
  assert_false(is_fatal_close(1001))
}

///|
test "reconnect_delay_exponential_cap" {
  assert_eq(reconnect_delay_ms(0), 5000)
  assert_eq(reconnect_delay_ms(1), 10000)
  assert_eq(reconnect_delay_ms(2), 20000)
  // Cap at 60s
  assert_eq(reconnect_delay_ms(10), 60000)
}

///|
test "should_reconnect_non_fatal" {
  let state = GatewayState::new("TOK")
  assert_true(should_reconnect(state, 1001))
  assert_false(should_reconnect(state, 4004))
}

// ── Discord Gateway: payload builders ───────────────────────────────────────

///|
test "build_identify_payload_structure" {
  let payload = build_identify_payload("BOT_TOK", DEFAULT_INTENTS)
  match payload {
    Object(obj) => {
      assert_eq(obj.get("op"), Some((2).to_json()))
      match obj.get("d") {
        Some(Object(d)) => {
          assert_eq(d.get("token"), Some("BOT_TOK".to_json()))
          assert_eq(d.get("intents"), Some(DEFAULT_INTENTS.to_json()))
        }
        _ => assert_true(false)
      }
    }
    _ => assert_true(false)
  }
}

///|
test "build_heartbeat_payload_with_seq" {
  let payload = build_heartbeat_payload(Some(42))
  match payload {
    Object(obj) => {
      assert_eq(obj.get("op"), Some((1).to_json()))
      assert_eq(obj.get("d"), Some((42).to_json()))
    }
    _ => assert_true(false)
  }
}

///|
test "build_heartbeat_payload_null" {
  let payload = build_heartbeat_payload(None)
  match payload {
    Object(obj) => {
      assert_eq(obj.get("op"), Some((1).to_json()))
      assert_true(obj.get("d") == Some(Json::null()))
    }
    _ => assert_true(false)
  }
}

///|
test "build_resume_payload" {
  let payload = build_resume_payload("TOK", "sess123", 99)
  match payload {
    Object(obj) => {
      assert_eq(obj.get("op"), Some((6).to_json()))
      match obj.get("d") {
        Some(Object(d)) => {
          assert_eq(d.get("session_id"), Some("sess123".to_json()))
          assert_eq(d.get("seq"), Some((99).to_json()))
        }
        _ => assert_true(false)
      }
    }
    _ => assert_true(false)
  }
}

// ── Discord Gateway: parse events ───────────────────────────────────────────

///|
test "parse_gateway_event_hello" {
  let json = @json.parse("{\"op\":10,\"d\":{\"heartbeat_interval\":41250}}") catch {
    _ => Json::object({})
  }
  match parse_gateway_event(json) {
    Ok((op, _d)) => assert_eq(op, 10)
    Err(_) => assert_true(false)
  }
}

///|
test "parse_gateway_event_missing_op" {
  let json = @json.parse("{\"d\":{}}") catch { _ => Json::object({}) }
  assert_true(parse_gateway_event(json) is Err(_))
}

///|
test "parse_hello_payload" {
  let data = @json.parse("{\"heartbeat_interval\":41250}") catch {
    _ => Json::object({})
  }
  match parse_hello_payload(data) {
    Ok(interval) => assert_eq(interval, 41250)
    Err(_) => assert_true(false)
  }
}

///|
test "parse_ready_payload" {
  let data = @json.parse(
    "{\"session_id\":\"abc\",\"resume_gateway_url\":\"wss://r.gg\"}",
  ) catch {
    _ => Json::object({})
  }
  match parse_ready_payload(data) {
    Ok((sid, url)) => {
      assert_eq(sid, "abc")
      assert_eq(url, Some("wss://r.gg"))
    }
    Err(_) => assert_true(false)
  }
}

///|
test "extract_seq_from_event" {
  let json = @json.parse("{\"s\":7,\"t\":\"MESSAGE_CREATE\"}") catch {
    _ => Json::object({})
  }
  assert_eq(extract_seq(json), Some(7))
}

///|
test "extract_event_name" {
  let json = @json.parse("{\"t\":\"MESSAGE_CREATE\",\"s\":5}") catch {
    _ => Json::object({})
  }
  assert_eq(extract_event_name(json), Some("MESSAGE_CREATE"))
}

///|
test "parse_invalid_session_resumable" {
  let t = @json.parse("true") catch { _ => Json::object({}) }
  let f = @json.parse("false") catch { _ => Json::object({}) }
  assert_true(parse_invalid_session(t))
  assert_false(parse_invalid_session(f))
}

// ── Feishu: FeishuApiClient ─────────────────────────────────────────────────

///|
test "feishu_api_client_new" {
  let client = FeishuApiClient::new("app1", "sec1")
  assert_eq(client.app_id, "app1")
  assert_eq(client.base_url, FEISHU_API_BASE)
}

///|
test "feishu_api_client_with_base_url" {
  let client = FeishuApiClient::with_base_url("a", "s", "https://custom.api")
  assert_eq(
    client.api_url("im/v1/messages"),
    "https://custom.api/im/v1/messages",
  )
}

///|
test "feishu_auth_url" {
  let client = FeishuApiClient::new("a", "s")
  assert_true(
    client.auth_url().contains("/auth/v3/tenant_access_token/internal"),
  )
}

///|
test "feishu_build_auth_body" {
  let client = FeishuApiClient::new("myapp", "mysecret")
  let body = client.build_auth_body()
  match body {
    Object(obj) => {
      assert_eq(obj.get("app_id"), Some("myapp".to_json()))
      assert_eq(obj.get("app_secret"), Some("mysecret".to_json()))
    }
    _ => assert_true(false)
  }
}

// ── Feishu: content builders ────────────────────────────────────────────────

///|
test "build_feishu_text_content_structure" {
  let content = build_feishu_text_content("Hello Feishu")
  match content {
    Object(obj) => {
      assert_eq(obj.get("msg_type"), Some("text".to_json()))
      assert_true(obj.get("content") is Some(_))
    }
    _ => assert_true(false)
  }
}

///|
test "build_feishu_card_content_structure" {
  let content = build_feishu_card_content("```python\nprint('hi')\n```")
  match content {
    Object(obj) => assert_eq(obj.get("msg_type"), Some("interactive".to_json()))
    _ => assert_true(false)
  }
}

///|
test "is_card_preferred_detection" {
  assert_true(is_card_preferred("some ```code``` here"))
  assert_true(is_card_preferred("table |---| col"))
  assert_false(is_card_preferred("plain text message"))
}

// ── Feishu: message parser ──────────────────────────────────────────────────

///|
test "parse_feishu_text_message" {
  let content_str = "{\"text\":\"Hello from Feishu\"}"
  let text = parse_feishu_text(content_str)
  assert_eq(text, "Hello from Feishu")
}

///|
test "parse_feishu_text_invalid_json" {
  let text = parse_feishu_text("not-json")
  assert_eq(text, "not-json")
}

///|
test "parse_feishu_message_text" {
  let msg : Map[String, Json] = {
    "message_type": "text".to_json(),
    "content": "{\"text\":\"hello feishu\"}".to_json(),
  }
  match parse_feishu_message(msg) {
    Ok(parsed) => {
      assert_eq(parsed.msg_type, "text")
      assert_eq(parsed.text, "hello feishu")
    }
    Err(_) => assert_true(false)
  }
}

///|
test "parse_feishu_message_image" {
  let msg : Map[String, Json] = {
    "message_type": "image".to_json(),
    "content": "{\"image_key\":\"img_abc\"}".to_json(),
  }
  match parse_feishu_message(msg) {
    Ok(parsed) => {
      assert_eq(parsed.msg_type, "image")
      assert_eq(parsed.attachments.length(), 1)
    }
    Err(_) => assert_true(false)
  }
}

// ── Feishu: resolve mentions ────────────────────────────────────────────────

///|
test "resolve_feishu_mentions" {
  let mentions : Array[Json] = [
    Json::object({ "key": "@_user_1".to_json(), "name": "Alice".to_json() }),
  ]
  let result = resolve_feishu_mentions("Hello @_user_1", mentions)
  assert_eq(result, "Hello @Alice")
}

// ── Feishu: extract doc URLs ────────────────────────────────────────────────

///|
test "extract_feishu_doc_urls_found" {
  let text = "See https://docs.feishu.cn/docx/abc123 for details"
  let urls = extract_feishu_doc_urls(text)
  assert_eq(urls.length(), 1)
  assert_true(urls[0].contains("feishu.cn"))
}

///|
test "extract_feishu_doc_urls_none" {
  let urls = extract_feishu_doc_urls("no urls here")
  assert_eq(urls.length(), 0)
}

// ── WeCom: WeComWsState ─────────────────────────────────────────────────────

///|
test "wecom_ws_state_new" {
  let state = WeComWsState::new("bot1", "sec1")
  assert_eq(state.bot_id, "bot1")
  assert_false(state.is_connected)
  assert_eq(state.req_counter, 0)
}

///|
test "wecom_ws_state_lifecycle" {
  let state = WeComWsState::new("b", "s")
  state.mark_connected()
  assert_true(state.is_connected)
  let id1 = state.next_req_id()
  let id2 = state.next_req_id()
  assert_eq(id1, "1")
  assert_eq(id2, "2")
  state.mark_disconnected()
  assert_false(state.is_connected)
}

// ── WeCom: frame builders ───────────────────────────────────────────────────

///|
test "build_subscribe_frame" {
  let frame = build_subscribe_frame("bot1", "secret1")
  match frame {
    Object(obj) => {
      assert_eq(obj.get("type"), Some("aibot_subscribe".to_json()))
      assert_eq(obj.get("bot_id"), Some("bot1".to_json()))
    }
    _ => assert_true(false)
  }
}

///|
test "build_send_msg_frame" {
  let frame = build_send_msg_frame("chat1", "hello", "text", "req1")
  match frame {
    Object(obj) => {
      assert_eq(obj.get("type"), Some("aibot_send_msg".to_json()))
      assert_eq(obj.get("chat_id"), Some("chat1".to_json()))
      assert_eq(obj.get("req_id"), Some("req1".to_json()))
    }
    _ => assert_true(false)
  }
}

///|
test "build_ping_frame" {
  let frame = build_ping_frame()
  match frame {
    Object(obj) => assert_eq(obj.get("type"), Some("ping".to_json()))
    _ => assert_true(false)
  }
}

///|
test "build_ack_frame" {
  let frame = build_ack_frame("req42")
  match frame {
    Object(obj) => {
      assert_eq(obj.get("type"), Some("ack".to_json()))
      assert_eq(obj.get("req_id"), Some("req42".to_json()))
    }
    _ => assert_true(false)
  }
}

// ── WeCom: parse_incoming_frame ─────────────────────────────────────────────

///|
test "parse_incoming_frame_subscribe" {
  let json = @json.parse("{\"type\":\"aibot_subscribe\",\"status\":\"ok\"}") catch {
    _ => Json::object({})
  }
  match parse_incoming_frame(json) {
    Ok((ft, _)) => assert_true(ft == WeComFrameType::Subscribe)
    Err(_) => assert_true(false)
  }
}

///|
test "parse_incoming_frame_unknown_type" {
  let json = @json.parse("{\"type\":\"unknown_type\"}") catch {
    _ => Json::object({})
  }
  assert_true(parse_incoming_frame(json) is Err(_))
}

///|
test "parse_incoming_frame_missing_type" {
  let json = @json.parse("{\"data\":1}") catch { _ => Json::object({}) }
  assert_true(parse_incoming_frame(json) is Err(_))
}

// ── WeCom: is_auth_error ────────────────────────────────────────────────────

///|
test "is_auth_error_type_field" {
  let json = @json.parse("{\"type\":\"auth_error\"}") catch {
    _ => Json::object({})
  }
  assert_true(is_auth_error(json))
}

///|
test "is_auth_error_errcode" {
  let json = @json.parse("{\"errcode\":40001}") catch { _ => Json::object({}) }
  assert_true(is_auth_error(json))
}

///|
test "is_auth_error_false" {
  let json = @json.parse("{\"type\":\"data\"}") catch { _ => Json::object({}) }
  assert_false(is_auth_error(json))
}

// ── WeCom: WeComUploadState ─────────────────────────────────────────────────

///|
test "wecom_upload_state_chunks" {
  // 1MB file with 512KB chunks = 2 chunks
  let us = WeComUploadState::new(1048576)
  assert_false(us.is_complete())
  let c1 = us.next_chunk()
  assert_eq(c1, 0)
  let c2 = us.next_chunk()
  assert_eq(c2, 1)
  assert_true(us.is_complete())
}

///|
test "calculate_chunk_count" {
  assert_eq(calculate_chunk_count(1000, 500), 2)
  assert_eq(calculate_chunk_count(1000, 1000), 1)
  assert_eq(calculate_chunk_count(1001, 1000), 2)
  assert_eq(calculate_chunk_count(0, 100), 0)
}

///|
test "needs_ack_and_is_response" {
  assert_true(needs_ack(WeComFrameType::SendMsg))
  assert_true(needs_ack(WeComFrameType::Data))
  assert_false(needs_ack(WeComFrameType::Ping))
  assert_true(is_response_frame(WeComFrameType::Ack))
  assert_true(is_response_frame(WeComFrameType::Pong))
  assert_false(is_response_frame(WeComFrameType::Subscribe))
}

// ── DingTalk: DingTalkApiClient ─────────────────────────────────────────────

///|
test "dingtalk_api_client_new" {
  let client = DingTalkApiClient::new("key1", "sec1")
  assert_eq(client.app_key, "key1")
  assert_eq(client.api_base, DINGTALK_API_BASE)
}

///|
test "dingtalk_access_token_url" {
  let client = DingTalkApiClient::new("k", "s")
  assert_true(client.access_token_url().contains("/v1.0/oauth2/accessToken"))
}

///|
test "dingtalk_build_access_token_request" {
  let client = DingTalkApiClient::new("mykey", "mysec")
  let body = client.build_access_token_request()
  match body {
    Object(obj) => {
      assert_eq(obj.get("appKey"), Some("mykey".to_json()))
      assert_eq(obj.get("appSecret"), Some("mysec".to_json()))
    }
    _ => assert_true(false)
  }
}

///|
test "dingtalk_build_oapi_token_request" {
  let client = DingTalkApiClient::new("k1", "s1")
  let url = client.build_oapi_token_request()
  assert_true(url.contains("appkey=k1"))
  assert_true(url.contains("appsecret=s1"))
}

// ── DingTalk: parse_token_response ──────────────────────────────────────────

///|
test "dingtalk_parse_token_new_api" {
  let json = @json.parse("{\"accessToken\":\"tok123\",\"expireIn\":7200}") catch {
    _ => Json::object({})
  }
  match DingTalkApiClient::parse_token_response(json) {
    Ok((tok, exp)) => {
      assert_eq(tok, "tok123")
      assert_eq(exp, 7200)
    }
    Err(_) => assert_true(false)
  }
}

///|
test "dingtalk_parse_token_oapi" {
  let json = @json.parse(
    "{\"access_token\":\"oapi_tok\",\"expires_in\":7200,\"errcode\":0}",
  ) catch {
    _ => Json::object({})
  }
  match DingTalkApiClient::parse_token_response(json) {
    Ok((tok, exp)) => {
      assert_eq(tok, "oapi_tok")
      assert_eq(exp, 7200)
    }
    Err(_) => assert_true(false)
  }
}

///|
test "dingtalk_parse_token_oapi_error" {
  let json = @json.parse(
    "{\"access_token\":\"\",\"errcode\":40001,\"errmsg\":\"bad appkey\"}",
  ) catch {
    _ => Json::object({})
  }
  match DingTalkApiClient::parse_token_response(json) {
    Ok(_) => assert_true(false)
    Err(ChannelError(msg)) => assert_true(msg.contains("bad appkey"))
  }
}

// ── DingTalk: webhook payload ───────────────────────────────────────────────

///|
test "dingtalk_webhook_payload_text" {
  let payload = DingTalkApiClient::build_webhook_payload("hello", "text")
  match payload {
    Object(obj) => assert_eq(obj.get("msgtype"), Some("text".to_json()))
    _ => assert_true(false)
  }
}

///|
test "dingtalk_webhook_payload_markdown" {
  let payload = DingTalkApiClient::build_webhook_payload("**bold**", "markdown")
  match payload {
    Object(obj) => assert_eq(obj.get("msgtype"), Some("markdown".to_json()))
    _ => assert_true(false)
  }
}

// ── DingTalk: stream frames ─────────────────────────────────────────────────

///|
test "dingtalk_parse_stream_frame" {
  let json = @json.parse("{\"type\":\"CALLBACK\",\"data\":{\"text\":\"hi\"}}") catch {
    _ => Json::object({})
  }
  match parse_stream_frame(json) {
    Ok((t, _d)) => assert_eq(t, "CALLBACK")
    Err(_) => assert_true(false)
  }
}

///|
test "dingtalk_build_stream_ack" {
  let ack = build_stream_ack("msg999")
  match ack {
    Object(obj) => {
      assert_eq(obj.get("code"), Some((200).to_json()))
      assert_eq(obj.get("messageId"), Some("msg999".to_json()))
    }
    _ => assert_true(false)
  }
}

///|
test "dingtalk_build_stream_pong" {
  let pong = build_stream_pong()
  match pong {
    Object(obj) => assert_eq(obj.get("type"), Some("pong".to_json()))
    _ => assert_true(false)
  }
}

///|
test "dingtalk_is_webhook_valid" {
  assert_false(is_webhook_valid("", 0))
  assert_true(is_webhook_valid("https://hook.dingtalk.com/abc", 0))
  assert_true(is_webhook_valid("https://hook.dingtalk.com/abc", 9999999))
}

// ── Weixin: WeixinApiClient ─────────────────────────────────────────────────

///|
test "weixin_api_client_new" {
  let client = WeixinApiClient::new("wx_tok", "wx_uin")
  assert_eq(client.token, "wx_tok")
  assert_eq(client.uin, "wx_uin")
  assert_eq(client.base_url, WEIXIN_API_BASE)
}

///|
test "weixin_auth_headers" {
  let client = WeixinApiClient::new("tok", "uin123")
  let headers = client.auth_headers()
  let arr = headers.to_array()
  assert_true(
    arr.any(fn(pair) {
      let (k, v) = pair
      k == "Authorization" && v.contains("tok")
    }),
  )
  assert_true(
    arr.any(fn(pair) {
      let (k, v) = pair
      k == "X-WECHAT-UIN" && v == "uin123"
    }),
  )
}

///|
test "weixin_get_updates_url" {
  let client = WeixinApiClient::new("t", "u")
  let url = client.get_updates_url(None)
  assert_true(url.contains("getupdates"))
}

///|
test "weixin_build_get_updates_request" {
  let client = WeixinApiClient::new("t", "u")
  let req = client.build_get_updates_request(None)
  match req {
    Object(obj) => assert_eq(obj.get("timeout"), Some((40).to_json()))
    _ => assert_true(false)
  }
}

///|
test "weixin_parse_get_updates_response_ok" {
  let client = WeixinApiClient::new("t", "u")
  let json = @json.parse(
    "{\"ret\":0,\"item_list\":[{\"msg\":\"hi\"}],\"buf\":\"next_cursor\"}",
  ) catch {
    _ => Json::object({})
  }
  match client.parse_get_updates_response(json) {
    Ok((msgs, buf)) => {
      assert_eq(msgs.length(), 1)
      assert_eq(buf, Some("next_cursor"))
    }
    Err(_) => assert_true(false)
  }
}

///|
test "weixin_parse_get_updates_response_error" {
  let client = WeixinApiClient::new("t", "u")
  let json = @json.parse("{\"ret\":-1,\"errmsg\":\"auth failed\"}") catch {
    _ => Json::object({})
  }
  assert_true(client.parse_get_updates_response(json) is Err(_))
}

///|
test "weixin_build_send_text_request" {
  let client = WeixinApiClient::new("t", "u")
  let req = client.build_send_text_request("user1", "hello", "ctx_tok")
  match req {
    Object(obj) => {
      assert_eq(obj.get("to_user_name"), Some("user1".to_json()))
      assert_eq(obj.get("msg_type"), Some((1).to_json()))
    }
    _ => assert_true(false)
  }
}

///|
test "weixin_build_typing_request" {
  let client = WeixinApiClient::new("t", "u")
  let req = client.build_typing_request("user1", 1)
  match req {
    Object(obj) => {
      assert_eq(obj.get("to_user_name"), Some("user1".to_json()))
      assert_eq(obj.get("typing_status"), Some((1).to_json()))
    }
    _ => assert_true(false)
  }
}

// ── Weixin: WeixinSendQueue ─────────────────────────────────────────────────

///|
test "weixin_send_queue_empty" {
  let q = WeixinSendQueue::new()
  assert_false(q.should_flush())
  assert_eq(q.pending_count(), 0)
  assert_true(q.dequeue() is None)
}

///|
test "weixin_send_queue_enqueue_dequeue" {
  let q = WeixinSendQueue::new()
  let msg : WeixinPendingMsg = {
    chat_id: "c1",
    text: "hello",
    context_token: "tok",
    retry_count: 0,
  }
  q.enqueue(msg)
  assert_true(q.should_flush())
  assert_eq(q.pending_count(), 1)
  match q.dequeue() {
    Some(m) => assert_eq(m.text, "hello")
    None => assert_true(false)
  }
  assert_eq(q.pending_count(), 0)
}

///|
test "weixin_send_queue_retry_delay" {
  let q = WeixinSendQueue::new()
  assert_eq(q.calculate_retry_delay(0), 1000)
  assert_eq(q.calculate_retry_delay(1), 2000)
  assert_eq(q.calculate_retry_delay(5), 4000)
}

// ── Weixin: sanitize_for_weixin ─────────────────────────────────────────────

///|
test "sanitize_for_weixin_strips_bold" {
  let result = sanitize_for_weixin("This is **bold** text")
  assert_eq(result, "This is bold text")
}

///|
test "sanitize_for_weixin_strips_code" {
  let result = sanitize_for_weixin("Use `print()` here")
  assert_eq(result, "Use print() here")
}

///|
test "sanitize_for_weixin_strips_link" {
  let result = sanitize_for_weixin("Click [here](https://example.com) now")
  assert_eq(result, "Click here now")
}

// ── Weixin: split_weixin_message ────────────────────────────────────────────

///|
test "split_weixin_short_no_split" {
  let chunks = split_weixin_message("short", 2000)
  assert_eq(chunks.length(), 1)
}

///|
test "split_weixin_long_splits" {
  let long = "line\n".repeat(500)
  let chunks = split_weixin_message(long, 200)
  assert_true(chunks.length() > 1)
}

// ── Weixin: is_rate_limited ─────────────────────────────────────────────────

///|
test "is_rate_limited_codes" {
  assert_true(is_rate_limited(-2))
  assert_false(is_rate_limited(0))
  assert_false(is_rate_limited(-1))
}
