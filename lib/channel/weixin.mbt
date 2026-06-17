///| 微信公众号 (Weixin Official Account) adapter implementation.

///|
/// WeixinAdapter handles communication with WeChat Official Account Platform.
pub(all) struct WeixinAdapter {
  app_id : String
  app_secret : String
  token : String
  encoding_aes_key : String?
  mut is_running : Bool
  mut message_callback : ((ChannelEvent) -> Unit)?
}

///|
/// Create a new WeixinAdapter from channel configuration.
pub fn WeixinAdapter::new(
  config : ChannelConfig,
) -> Result[WeixinAdapter, ChannelError] {
  let app_id = match config.settings.get("app_id") {
    Some(v) => v
    None => return Err(ChannelError("Missing setting: app_id"))
  }
  let app_secret = match config.settings.get("app_secret") {
    Some(v) => v
    None => return Err(ChannelError("Missing setting: app_secret"))
  }
  let token = match config.settings.get("token") {
    Some(v) => v
    None => return Err(ChannelError("Missing setting: token"))
  }
  let encoding_aes_key = config.settings.get("encoding_aes_key")
  Ok({
    app_id,
    app_secret,
    token,
    encoding_aes_key,
    is_running: false,
    message_callback: None,
  })
}

///|
pub impl Adapter for WeixinAdapter with fn platform_id(_self) -> Platform {
  Platform::Weixin
}

///|
pub impl Adapter for WeixinAdapter with fn supports_message_updates(_self) -> Bool {
  false // WeChat Official Account does not support message editing
}

///|
pub impl Adapter for WeixinAdapter with fn start(
  self,
  handler : (ChannelEvent) -> Unit,
) -> Result[Unit, ChannelError] {
  self.message_callback = Some(handler)
  self.is_running = true
  // TODO: Start message callback server and token verification via FFI
  Ok(())
}

///|
pub impl Adapter for WeixinAdapter with fn stop(self) -> Result[
  Unit,
  ChannelError,
] {
  self.is_running = false
  self.message_callback = None
  Ok(())
}

///|
pub impl Adapter for WeixinAdapter with fn send_text(
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
  // TODO: POST /cgi-bin/message/custom/send via HTTP FFI
  { message_id: "weixin_msg_placeholder", success: true, error: None }
}

///|
pub impl Adapter for WeixinAdapter with fn update_message(
  _self,
  _chat_id : String,
  _message_id : String,
  _new_text : String,
) -> Result[Unit, ChannelError] {
  Err(ChannelError("Weixin Official Account does not support message updates"))
}

///|
pub impl Adapter for WeixinAdapter with fn validate_config(self) -> Array[
  String,
] {
  let errors : Array[String] = []
  if self.app_id.is_empty() {
    errors.push("app_id is required")
  }
  if self.app_secret.is_empty() {
    errors.push("app_secret is required")
  }
  if self.token.is_empty() {
    errors.push("token is required")
  }
  errors
}

///|
/// Parse incoming Weixin XML message (as JSON representation) to ChannelEvent.
pub fn WeixinAdapter::parse_event(
  json : Json,
) -> Result[ChannelEvent, ChannelError] {
  // WeChat uses XML, but we parse a JSON representation of the XML
  let msg = match json {
    Object(obj) => obj
    _ => return Err(ChannelError("Invalid JSON payload"))
  }
  let chat_id = match msg.get("ToUserName") {
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
  let event_type = match msg.get("MsgType") {
    Some(String(s)) =>
      if s == "event" {
        EventType::Join
      } else {
        EventType::Message
      }
    _ => EventType::Message
  }
  Ok({
    event_type,
    platform: Platform::Weixin,
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
/// Build Weixin reply message payload.
pub fn build_weixin_message(
  to_user : String,
  from_user : String,
  text : String,
) -> Json {
  let msg : Map[String, Json] = {}
  msg.set("ToUserName", to_user.to_json())
  msg.set("FromUserName", from_user.to_json())
  msg.set("MsgType", "text".to_json())
  msg.set("Content", text.to_json())
  Json::object(msg)
}
