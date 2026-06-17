///| 飞书/Lark adapter implementation.

///|
/// FeishuAdapter handles communication with Feishu/Lark Bot API.
pub(all) struct FeishuAdapter {
  bot_id : String
  bot_secret : String
  webhook_url : String?
  mut is_running : Bool
  mut message_callback : ((ChannelEvent) -> Unit)?
}

///|
/// Create a new FeishuAdapter from channel configuration.
pub fn FeishuAdapter::new(
  config : ChannelConfig,
) -> Result[FeishuAdapter, ChannelError] {
  let bot_id = match config.settings.get("bot_id") {
    Some(v) => v
    None => return Err(ChannelError("Missing setting: bot_id"))
  }
  let bot_secret = match config.settings.get("bot_secret") {
    Some(v) => v
    None => return Err(ChannelError("Missing setting: bot_secret"))
  }
  let webhook_url = config.settings.get("webhook_url")
  Ok({
    bot_id,
    bot_secret,
    webhook_url,
    is_running: false,
    message_callback: None,
  })
}

///|
pub impl Adapter for FeishuAdapter with fn platform_id(_self) -> Platform {
  Platform::Feishu
}

///|
pub impl Adapter for FeishuAdapter with fn supports_message_updates(_self) -> Bool {
  true
}

///|
pub impl Adapter for FeishuAdapter with fn start(
  self,
  handler : (ChannelEvent) -> Unit,
) -> Result[Unit, ChannelError] {
  self.message_callback = Some(handler)
  self.is_running = true
  // TODO: Start webhook listener or long-polling via FFI
  Ok(())
}

///|
pub impl Adapter for FeishuAdapter with fn stop(self) -> Result[
  Unit,
  ChannelError,
] {
  self.is_running = false
  self.message_callback = None
  Ok(())
}

///|
pub impl Adapter for FeishuAdapter with fn send_text(
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
  // TODO: POST /open-apis/im/v1/messages via HTTP FFI
  { message_id: "feishu_msg_placeholder", success: true, error: None }
}

///|
pub impl Adapter for FeishuAdapter with fn update_message(
  self,
  _chat_id : String,
  _message_id : String,
  _new_text : String,
) -> Result[Unit, ChannelError] {
  if !self.is_running {
    return Err(ChannelError("Adapter not running"))
  }
  // TODO: PATCH /open-apis/im/v1/messages/:message_id via HTTP FFI
  Ok(())
}

///|
pub impl Adapter for FeishuAdapter with fn validate_config(self) -> Array[
  String,
] {
  let errors : Array[String] = []
  if self.bot_id.is_empty() {
    errors.push("bot_id is required")
  }
  if self.bot_secret.is_empty() {
    errors.push("bot_secret is required")
  }
  errors
}

///|
/// Parse incoming Feishu webhook event JSON to ChannelEvent.
pub fn FeishuAdapter::parse_event(
  json : Json,
) -> Result[ChannelEvent, ChannelError] {
  // Extract fields from Feishu event callback format
  let event = match json {
    Object(obj) =>
      match obj.get("event") {
        Some(Object(ev)) => ev
        _ => return Err(ChannelError("Missing 'event' field in payload"))
      }
    _ => return Err(ChannelError("Invalid JSON payload"))
  }
  let message = match event.get("message") {
    Some(Object(msg)) => msg
    _ => return Err(ChannelError("Missing 'message' field in event"))
  }
  let chat_id = match message.get("chat_id") {
    Some(String(s)) => s
    _ => ""
  }
  let message_id = match message.get("message_id") {
    Some(String(s)) => s
    _ => ""
  }
  let text = match message.get("content") {
    Some(String(s)) => s
    _ => ""
  }
  let sender_id = match event.get("sender") {
    Some(Object(sender)) =>
      match sender.get("sender_id") {
        Some(Object(sid)) =>
          match sid.get("user_id") {
            Some(String(s)) => s
            _ => ""
          }
        _ => ""
      }
    _ => ""
  }
  let sender_name = match event.get("sender") {
    Some(Object(sender)) =>
      match sender.get("sender_id") {
        Some(Object(sid)) =>
          match sid.get("name") {
            Some(String(s)) => s
            _ => "unknown"
          }
        _ => "unknown"
      }
    _ => "unknown"
  }
  Ok({
    event_type: EventType::Message,
    platform: Platform::Feishu,
    chat_id,
    message_id,
    sender_id,
    sender_name,
    text,
    attachments: [],
    timestamp: 0,
    reply_to: None,
  })
}

///|
/// Build Feishu message payload JSON.
pub fn build_feishu_message(text : String, reply_to : String?) -> Json {
  let content : Map[String, Json] = {}
  content.set("text", text.to_json())
  let msg : Map[String, Json] = {}
  msg.set("msg_type", "text".to_json())
  msg.set("content", Json::object(content))
  match reply_to {
    Some(id) => msg.set("reply_in_thread", id.to_json())
    None => ()
  }
  Json::object(msg)
}
