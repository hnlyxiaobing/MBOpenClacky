///| 企业微信 (WeCom/WeChat Work) adapter implementation.

///|
/// WeComAdapter handles communication with WeCom Bot API.
pub(all) struct WeComAdapter {
  corp_id : String
  agent_id : String
  secret : String
  token : String?
  encoding_aes_key : String?
  mut is_running : Bool
  mut message_callback : ((ChannelEvent) -> Unit)?
}

///|
/// Create a new WeComAdapter from channel configuration.
pub fn WeComAdapter::new(
  config : ChannelConfig,
) -> Result[WeComAdapter, ChannelError] {
  let corp_id = match config.settings.get("corp_id") {
    Some(v) => v
    None => return Err(ChannelError("Missing setting: corp_id"))
  }
  let agent_id = match config.settings.get("agent_id") {
    Some(v) => v
    None => return Err(ChannelError("Missing setting: agent_id"))
  }
  let secret = match config.settings.get("secret") {
    Some(v) => v
    None => return Err(ChannelError("Missing setting: secret"))
  }
  let token = config.settings.get("token")
  let encoding_aes_key = config.settings.get("encoding_aes_key")
  Ok({
    corp_id,
    agent_id,
    secret,
    token,
    encoding_aes_key,
    is_running: false,
    message_callback: None,
  })
}

///|
pub impl Adapter for WeComAdapter with fn platform_id(_self) -> Platform {
  Platform::WeCom
}

///|
pub impl Adapter for WeComAdapter with fn supports_message_updates(_self) -> Bool {
  true
}

///|
pub impl Adapter for WeComAdapter with fn start(
  self,
  handler : (ChannelEvent) -> Unit,
) -> Result[Unit, ChannelError] {
  self.message_callback = Some(handler)
  self.is_running = true
  // TODO: Start callback URL verification and message receiving via FFI
  Ok(())
}

///|
pub impl Adapter for WeComAdapter with fn stop(self) -> Result[
  Unit,
  ChannelError,
] {
  self.is_running = false
  self.message_callback = None
  Ok(())
}

///|
pub impl Adapter for WeComAdapter with fn send_text(
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
  // TODO: POST /cgi-bin/message/send via HTTP FFI
  { message_id: "wecom_msg_placeholder", success: true, error: None }
}

///|
pub impl Adapter for WeComAdapter with fn update_message(
  self,
  _chat_id : String,
  _message_id : String,
  _new_text : String,
) -> Result[Unit, ChannelError] {
  if !self.is_running {
    return Err(ChannelError("Adapter not running"))
  }
  // TODO: POST /cgi-bin/message/update via HTTP FFI
  Ok(())
}

///|
pub impl Adapter for WeComAdapter with fn validate_config(self) -> Array[String] {
  let errors : Array[String] = []
  if self.corp_id.is_empty() {
    errors.push("corp_id is required")
  }
  if self.agent_id.is_empty() {
    errors.push("agent_id is required")
  }
  if self.secret.is_empty() {
    errors.push("secret is required")
  }
  errors
}

///|
/// Parse incoming WeCom callback event XML/JSON to ChannelEvent.
pub fn WeComAdapter::parse_event(
  json : Json,
) -> Result[ChannelEvent, ChannelError] {
  // WeCom typically uses XML callbacks; here we handle a JSON representation
  let msg = match json {
    Object(obj) => obj
    _ => return Err(ChannelError("Invalid JSON payload"))
  }
  let chat_id = match msg.get("ChatId") {
    Some(String(s)) => s
    _ => ""
  }
  let message_id = match msg.get("MsgId") {
    Some(String(s)) => s
    _ => ""
  }
  let text = match msg.get("Content") {
    Some(String(s)) => s
    _ => ""
  }
  let sender_id = match msg.get("FromUserName") {
    Some(String(s)) => s
    _ => ""
  }
  Ok({
    event_type: EventType::Message,
    platform: Platform::WeCom,
    chat_id,
    message_id,
    sender_id,
    sender_name: sender_id,
    text,
    attachments: [],
    timestamp: 0,
    reply_to: None,
  })
}

///|
/// Build WeCom message payload JSON.
pub fn build_wecom_message(
  text : String,
  _touser : String,
  _agent_id : String,
) -> Json {
  let text_obj : Map[String, Json] = {}
  text_obj.set("content", text.to_json())
  let msg : Map[String, Json] = {}
  msg.set("msgtype", "text".to_json())
  msg.set("text", Json::object(text_obj))
  Json::object(msg)
}
