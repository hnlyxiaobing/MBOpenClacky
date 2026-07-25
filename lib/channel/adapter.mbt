///| The Adapter trait defines the interface for all IM platform adapters.

///|
/// Declared as pub(open) so external packages can implement new adapters.
pub(open) trait Adapter {
  ///| Get the platform identifier.
  fn platform_id(Self) -> Platform

  ///| Start receiving messages (registers callback).
  fn start(Self, (ChannelEvent) -> Unit) -> Result[Unit, ChannelError]

  ///| Stop the adapter.
  fn stop(Self) -> Result[Unit, ChannelError]

  ///| Send a text message to a chat.
  /// params: chat_id, text, reply_to
  async fn send_text(Self, String, String, String?) -> Result[
    SendResult,
    ChannelError,
  ]

  ///| Update an existing message (for streaming progress).
  /// params: chat_id, message_id, new_text
  async fn update_message(Self, String, String, String) -> Result[
    Unit,
    ChannelError,
  ]

  ///| Whether this platform supports message updates.
  fn supports_message_updates(Self) -> Bool

  ///| Validate platform-specific configuration.
  /// returns: array of error messages (empty = valid)
  fn validate_config(Self) -> Array[String]
}

///|
/// Concrete enum wrapping all adapter implementations for polymorphic storage.
/// Each variant holds a specific adapter struct. Implement Adapter trait for
/// AnyAdapter by dispatching to the inner variant.
pub(all) enum AnyAdapter {
  Feishu(FeishuAdapter)
  WeCom(WeComAdapter)
  Telegram(TelegramAdapter)
  Discord(DiscordAdapter)
  DingTalk(DingTalkAdapter)
  Weixin(WeixinAdapter)
}

///|
pub impl Adapter for AnyAdapter with fn platform_id(self) -> Platform {
  match self {
    Feishu(a) => a.platform_id()
    WeCom(a) => a.platform_id()
    Telegram(a) => a.platform_id()
    Discord(a) => a.platform_id()
    DingTalk(a) => a.platform_id()
    Weixin(a) => a.platform_id()
  }
}

///|
pub impl Adapter for AnyAdapter with fn start(
  self,
  handler : (ChannelEvent) -> Unit,
) -> Result[Unit, ChannelError] {
  match self {
    Feishu(a) => a.start(handler)
    WeCom(a) => a.start(handler)
    Telegram(a) => a.start(handler)
    Discord(a) => a.start(handler)
    DingTalk(a) => a.start(handler)
    Weixin(a) => a.start(handler)
  }
}

///|
pub impl Adapter for AnyAdapter with fn stop(self) -> Result[Unit, ChannelError] {
  match self {
    Feishu(a) => a.stop()
    WeCom(a) => a.stop()
    Telegram(a) => a.stop()
    Discord(a) => a.stop()
    DingTalk(a) => a.stop()
    Weixin(a) => a.stop()
  }
}

///|
pub impl Adapter for AnyAdapter with fn send_text(
  self,
  chat_id : String,
  text : String,
  reply_to : String?,
) -> Result[SendResult, ChannelError] {
  match self {
    Feishu(a) => a.send_text(chat_id, text, reply_to)
    WeCom(a) => a.send_text(chat_id, text, reply_to)
    Telegram(a) => a.send_text(chat_id, text, reply_to)
    Discord(a) => a.send_text(chat_id, text, reply_to)
    DingTalk(a) => a.send_text(chat_id, text, reply_to)
    Weixin(a) => a.send_text(chat_id, text, reply_to)
  }
}

///|
pub impl Adapter for AnyAdapter with fn update_message(
  self,
  chat_id : String,
  message_id : String,
  new_text : String,
) -> Result[Unit, ChannelError] {
  match self {
    Feishu(a) => a.update_message(chat_id, message_id, new_text)
    WeCom(a) => a.update_message(chat_id, message_id, new_text)
    Telegram(a) => a.update_message(chat_id, message_id, new_text)
    Discord(a) => a.update_message(chat_id, message_id, new_text)
    DingTalk(a) => a.update_message(chat_id, message_id, new_text)
    Weixin(a) => a.update_message(chat_id, message_id, new_text)
  }
}

///|
pub impl Adapter for AnyAdapter with fn supports_message_updates(self) -> Bool {
  match self {
    Feishu(a) => a.supports_message_updates()
    WeCom(a) => a.supports_message_updates()
    Telegram(a) => a.supports_message_updates()
    Discord(a) => a.supports_message_updates()
    DingTalk(a) => a.supports_message_updates()
    Weixin(a) => a.supports_message_updates()
  }
}

///|
pub impl Adapter for AnyAdapter with fn validate_config(self) -> Array[String] {
  match self {
    Feishu(a) => a.validate_config()
    WeCom(a) => a.validate_config()
    Telegram(a) => a.validate_config()
    Discord(a) => a.validate_config()
    DingTalk(a) => a.validate_config()
    Weixin(a) => a.validate_config()
  }
}
