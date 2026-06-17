///| Tests for the channel package: types, adapters, registry, and manager.

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
