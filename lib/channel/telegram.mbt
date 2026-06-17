///| Telegram Bot API adapter implementation.

///|
/// TelegramAdapter handles communication via Telegram Bot API.
/// Uses long polling (getUpdates) for receiving messages.
pub(all) struct TelegramAdapter {
  bot_token : String
  mut is_running : Bool
  mut message_callback : ((ChannelEvent) -> Unit)?
  mut last_update_id : Int
}

///|
/// Create a new TelegramAdapter from channel configuration.
pub fn TelegramAdapter::new(
  config : ChannelConfig,
) -> Result[TelegramAdapter, ChannelError] {
  let bot_token = match config.settings.get("bot_token") {
    Some(v) => v
    None => return Err(ChannelError("Missing setting: bot_token"))
  }
  Ok({ bot_token, is_running: false, message_callback: None, last_update_id: 0 })
}

///|
pub impl Adapter for TelegramAdapter with fn platform_id(_self) -> Platform {
  Platform::Telegram
}

///|
pub impl Adapter for TelegramAdapter with fn supports_message_updates(_self) -> Bool {
  true // Telegram supports editMessageText
}

///|
pub impl Adapter for TelegramAdapter with fn start(
  self,
  handler : (ChannelEvent) -> Unit,
) -> Result[Unit, ChannelError] {
  self.message_callback = Some(handler)
  self.is_running = true
  // TODO: Start long-polling loop via getUpdates API
  Ok(())
}

///|
pub impl Adapter for TelegramAdapter with fn stop(self) -> Result[
  Unit,
  ChannelError,
] {
  self.is_running = false
  self.message_callback = None
  Ok(())
}

///|
pub impl Adapter for TelegramAdapter with fn send_text(
  self,
  _chat_id : String,
  _text : String,
  _reply_to : String?,
) -> SendResult {
  if !self.is_running {
    return {
      message_id: "",
      success: false,
      error: Some("Adapter not running"),
    }
  }
  // TODO: POST /bot{token}/sendMessage via HTTP FFI
  { message_id: "tg_msg_placeholder", success: true, error: None }
}

///|
pub impl Adapter for TelegramAdapter with fn update_message(
  self,
  _chat_id : String,
  _message_id : String,
  _new_text : String,
) -> Result[Unit, ChannelError] {
  if !self.is_running {
    return Err(ChannelError("Adapter not running"))
  }
  // TODO: POST /bot{token}/editMessageText via HTTP FFI
  Ok(())
}

///|
pub impl Adapter for TelegramAdapter with fn validate_config(self) -> Array[
  String,
] {
  let errors : Array[String] = []
  if self.bot_token.is_empty() {
    errors.push("bot_token is required")
  }
  errors
}

///|
/// Parse Telegram Update JSON to ChannelEvent.
pub fn TelegramAdapter::parse_event(
  json : Json,
) -> Result[ChannelEvent, ChannelError] {
  let update = match json {
    Object(obj) => obj
    _ => return Err(ChannelError("Invalid JSON payload"))
  }
  let message = match update.get("message") {
    Some(Object(msg)) => msg
    _ => return Err(ChannelError("Missing 'message' field"))
  }
  let chat_id = match message.get("chat") {
    Some(Object(chat)) =>
      match chat.get("id") {
        Some(Number(n, ..)) => n.to_int().to_string()
        _ => ""
      }
    _ => ""
  }
  let message_id = match message.get("message_id") {
    Some(Number(n, ..)) => n.to_int().to_string()
    _ => ""
  }
  let text = match message.get("text") {
    Some(String(s)) => s
    _ => ""
  }
  let sender_id = match message.get("from") {
    Some(Object(from)) =>
      match from.get("id") {
        Some(Number(n, ..)) => n.to_int().to_string()
        _ => ""
      }
    _ => ""
  }
  let sender_name = match message.get("from") {
    Some(Object(from)) =>
      match from.get("first_name") {
        Some(String(s)) => s
        _ => "unknown"
      }
    _ => "unknown"
  }
  let reply_to = match message.get("reply_to_message") {
    Some(Object(reply)) =>
      match reply.get("message_id") {
        Some(Number(n, ..)) => Some(n.to_int().to_string())
        _ => None
      }
    _ => None
  }
  Ok({
    event_type: EventType::Message,
    platform: Platform::Telegram,
    chat_id,
    message_id,
    sender_id,
    sender_name,
    text,
    attachments: [],
    timestamp: 0,
    reply_to,
  })
}

///|
/// Build Telegram sendMessage payload.
pub fn build_telegram_message(
  chat_id : String,
  text : String,
  reply_to : String?,
) -> Json {
  let msg : Map[String, Json] = {}
  msg.set("chat_id", chat_id.to_json())
  msg.set("text", text.to_json())
  match reply_to {
    Some(id) => msg.set("reply_to_message_id", id.to_json())
    None => ()
  }
  Json::object(msg)
}
