///| Discord Bot adapter implementation.

///|
/// DiscordAdapter handles communication via Discord Bot API.
/// Uses Gateway WebSocket for receiving and REST API for sending.
pub(all) struct DiscordAdapter {
  bot_token : String
  application_id : String?
  mut is_running : Bool
  mut message_callback : ((ChannelEvent) -> Unit)?
}

///|
/// Create a new DiscordAdapter from channel configuration.
pub fn DiscordAdapter::new(
  config : ChannelConfig,
) -> Result[DiscordAdapter, ChannelError] {
  let bot_token = match config.settings.get("bot_token") {
    Some(v) => v
    None => return Err(ChannelError("Missing setting: bot_token"))
  }
  let application_id = config.settings.get("application_id")
  Ok({ bot_token, application_id, is_running: false, message_callback: None })
}

///|
pub impl Adapter for DiscordAdapter with fn platform_id(_self) -> Platform {
  Platform::Discord
}

///|
pub impl Adapter for DiscordAdapter with fn supports_message_updates(_self) -> Bool {
  true // Discord supports PATCH /channels/{id}/messages/{id}
}

///|
pub impl Adapter for DiscordAdapter with fn start(
  self,
  handler : (ChannelEvent) -> Unit,
) -> Result[Unit, ChannelError] {
  self.message_callback = Some(handler)
  self.is_running = true
  // TODO: Connect to Gateway WebSocket via FFI
  Ok(())
}

///|
pub impl Adapter for DiscordAdapter with fn stop(self) -> Result[
  Unit,
  ChannelError,
] {
  self.is_running = false
  self.message_callback = None
  Ok(())
}

///|
pub impl Adapter for DiscordAdapter with fn send_text(
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
  // TODO: POST /channels/{channel_id}/messages via HTTP FFI
  { message_id: "discord_msg_placeholder", success: true, error: None }
}

///|
pub impl Adapter for DiscordAdapter with fn update_message(
  self,
  _chat_id : String,
  _message_id : String,
  _new_text : String,
) -> Result[Unit, ChannelError] {
  if !self.is_running {
    return Err(ChannelError("Adapter not running"))
  }
  // TODO: PATCH /channels/{channel_id}/messages/{message_id} via HTTP FFI
  Ok(())
}

///|
pub impl Adapter for DiscordAdapter with fn validate_config(self) -> Array[
  String,
] {
  let errors : Array[String] = []
  if self.bot_token.is_empty() {
    errors.push("bot_token is required")
  }
  errors
}

///|
/// Parse Discord Gateway MESSAGE_CREATE event to ChannelEvent.
pub fn DiscordAdapter::parse_event(
  json : Json,
) -> Result[ChannelEvent, ChannelError] {
  let data = match json {
    Object(obj) =>
      match obj.get("d") {
        Some(Object(d)) => d
        _ => return Err(ChannelError("Missing 'd' field in gateway event"))
      }
    _ => return Err(ChannelError("Invalid JSON payload"))
  }
  let chat_id = match data.get("channel_id") {
    Some(String(s)) => s
    _ => ""
  }
  let message_id = match data.get("id") {
    Some(String(s)) => s
    _ => ""
  }
  let text = match data.get("content") {
    Some(String(s)) => s
    _ => ""
  }
  let sender_id = match data.get("author") {
    Some(Object(author)) =>
      match author.get("id") {
        Some(String(s)) => s
        _ => ""
      }
    _ => ""
  }
  let sender_name = match data.get("author") {
    Some(Object(author)) =>
      match author.get("username") {
        Some(String(s)) => s
        _ => "unknown"
      }
    _ => "unknown"
  }
  Ok({
    event_type: EventType::Message,
    platform: Platform::Discord,
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
/// Build Discord message payload JSON.
pub fn build_discord_message(text : String, reply_to : String?) -> Json {
  let msg : Map[String, Json] = {}
  msg.set("content", text.to_json())
  match reply_to {
    Some(id) => {
      let ref_obj : Map[String, Json] = {}
      ref_obj.set("message_id", id.to_json())
      msg.set("message_reference", Json::object(ref_obj))
    }
    None => ()
  }
  Json::object(msg)
}
