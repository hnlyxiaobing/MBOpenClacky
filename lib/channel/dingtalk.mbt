///| 钉钉 (DingTalk) robot adapter implementation.

///|
/// DingTalkAdapter handles communication with DingTalk Robot API.
pub(all) struct DingTalkAdapter {
  access_token : String
  secret : String?
  webhook_url : String?
  mut is_running : Bool
  mut message_callback : ((ChannelEvent) -> Unit)?
}

///|
/// Create a new DingTalkAdapter from channel configuration.
pub fn DingTalkAdapter::new(
  config : ChannelConfig,
) -> Result[DingTalkAdapter, ChannelError] {
  let access_token = match config.settings.get("access_token") {
    Some(v) => v
    None => return Err(ChannelError("Missing setting: access_token"))
  }
  let secret = config.settings.get("secret")
  let webhook_url = config.settings.get("webhook_url")
  Ok({
    access_token,
    secret,
    webhook_url,
    is_running: false,
    message_callback: None,
  })
}

///|
pub impl Adapter for DingTalkAdapter with fn platform_id(_self) -> Platform {
  Platform::DingTalk
}

///|
pub impl Adapter for DingTalkAdapter with fn supports_message_updates(_self) -> Bool {
  false // DingTalk does not support message editing
}

///|
pub impl Adapter for DingTalkAdapter with fn start(
  self,
  handler : (ChannelEvent) -> Unit,
) -> Result[Unit, ChannelError] {
  self.message_callback = Some(handler)
  self.is_running = true
  // TODO: Register outgoing robot callback via FFI
  Ok(())
}

///|
pub impl Adapter for DingTalkAdapter with fn stop(self) -> Result[
  Unit,
  ChannelError,
] {
  self.is_running = false
  self.message_callback = None
  Ok(())
}

///|
pub impl Adapter for DingTalkAdapter with fn send_text(
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
  // TODO: POST webhook with signed request via HTTP FFI
  { message_id: "dingtalk_msg_placeholder", success: true, error: None }
}

///|
pub impl Adapter for DingTalkAdapter with fn update_message(
  _self,
  _chat_id : String,
  _message_id : String,
  _new_text : String,
) -> Result[Unit, ChannelError] {
  Err(ChannelError("DingTalk does not support message updates"))
}

///|
pub impl Adapter for DingTalkAdapter with fn validate_config(self) -> Array[
  String,
] {
  let errors : Array[String] = []
  if self.access_token.is_empty() {
    errors.push("access_token is required")
  }
  errors
}

///|
/// Parse incoming DingTalk robot callback JSON to ChannelEvent.
pub fn DingTalkAdapter::parse_event(
  json : Json,
) -> Result[ChannelEvent, ChannelError] {
  let msg = match json {
    Object(obj) => obj
    _ => return Err(ChannelError("Invalid JSON payload"))
  }
  let chat_id = match msg.get("conversationId") {
    Some(String(s)) => s
    _ => ""
  }
  let message_id = match msg.get("msgId") {
    Some(String(s)) => s
    _ => ""
  }
  let text_obj = match msg.get("text") {
    Some(Object(t)) => t
    _ => return Err(ChannelError("Missing 'text' field"))
  }
  let text = match text_obj.get("content") {
    Some(String(s)) => s
    _ => ""
  }
  let sender_id = match msg.get("senderId") {
    Some(String(s)) => s
    _ => ""
  }
  let sender_name = match msg.get("senderNick") {
    Some(String(s)) => s
    _ => "unknown"
  }
  Ok({
    event_type: EventType::Message,
    platform: Platform::DingTalk,
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
/// Build DingTalk webhook message payload.
pub fn build_dingtalk_message(text : String) -> Json {
  let text_obj : Map[String, Json] = {}
  text_obj.set("content", text.to_json())
  let msg : Map[String, Json] = {}
  msg.set("msgtype", "text".to_json())
  msg.set("text", Json::object(text_obj))
  Json::object(msg)
}
