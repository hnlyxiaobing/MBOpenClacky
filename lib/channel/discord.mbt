///| Discord Bot adapter implementation.

///|
/// DiscordAdapter handles communication via Discord Bot API.
/// Uses Gateway WebSocket for receiving and REST API for sending.
pub(all) struct DiscordAdapter {
  bot_token : String
  application_id : String?
  api_client : DiscordApiClient
  mut gateway_state : GatewayState?
  mut bot_user_id : String?
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
  let api_client = DiscordApiClient::new(bot_token)
  Ok({
    bot_token,
    application_id,
    api_client,
    gateway_state: None,
    bot_user_id: None,
    is_running: false,
    message_callback: None,
  })
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

  // Step 1: Fetch bot user info via REST API
  let user_json = match self.api_client.get_current_user() {
    Ok(v) => v
    Err(_) => {
      let empty : Map[String, Json] = {}
      Json::object(empty)
    }
  }
  match user_json {
    Object(obj) =>
      match obj.get("id") {
        Some(String(id)) => self.bot_user_id = Some(id)
        _ => ()
      }
    _ => ()
  }

  // Step 2: Initialize Gateway state
  let state = GatewayState::new(self.bot_token)
  self.gateway_state = Some(state)

  // TODO: Connect to Gateway WebSocket via @websocket:
  //   let url = get_gateway_url(state)
  //   let ws = await @websocket.connect(url)
  //   Main loop:
  //     1. Receive Hello (op 10) -> extract heartbeat_interval
  //     2. Send Identify (op 2) or Resume (op 6) if should_resume(state)
  //     3. Start heartbeat timer: every heartbeat_interval ms, send op 1
  //     4. On Dispatch (op 0): extract event name, update seq, handle MESSAGE_CREATE
  //     5. On Reconnect (op 7): close and reconnect to resume_gateway_url
  //     6. On InvalidSession (op 9): if d=true, attempt resume; else re-identify
  //     7. On close: if !is_fatal_close(code), schedule reconnect with backoff
  //     8. On heartbeat miss (no ACK): force reconnect

  Ok(())
}

///|
pub impl Adapter for DiscordAdapter with fn stop(self) -> Result[
  Unit,
  ChannelError,
] {
  self.is_running = false
  self.message_callback = None
  match self.gateway_state {
    Some(state) => state.reset_connection()
    None => ()
  }
  Ok(())
}

///|
pub impl Adapter for DiscordAdapter with fn send_text(
  self,
  chat_id : String,
  text : String,
  reply_to : String?,
) -> Result[SendResult, ChannelError] {
  if !self.is_running {
    return Err(ChannelError("Adapter not running"))
  }
  let resp = match self.api_client.send_message(chat_id, text, reply_to) {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let msg_id = match resp {
    Object(obj) =>
      match obj.get("id") {
        Some(String(id)) => id
        _ => "unknown"
      }
    _ => "unknown"
  }
  Ok({ message_id: msg_id, success: true, error: None })
}

///|
pub impl Adapter for DiscordAdapter with fn update_message(
  self,
  chat_id : String,
  message_id : String,
  new_text : String,
) -> Result[Unit, ChannelError] {
  if !self.is_running {
    return Err(ChannelError("Adapter not running"))
  }
  match self.api_client.edit_message(chat_id, message_id, new_text) {
    Ok(_) => ()
    Err(e) => return Err(e)
  }
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
///
/// Enhanced parsing:
/// - Detects chat_type (Group if guild_id present, else Direct)
/// - Parses attachments (images/files)
/// - Filters bot messages (author.bot field)
/// - Preserves raw payload
/// - Extracts reply_to from message_reference
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
  // Filter bot messages
  let is_bot = match data.get("author") {
    Some(Object(author)) =>
      match author.get("bot") {
        Some(True) => true
        Some(False) => false
        _ => false
      }
    _ => false
  }
  if is_bot {
    return Err(ChannelError("Ignoring bot message"))
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
  // Detect chat_type: guild_id present => Group, otherwise Direct
  let chat_type = match data.get("guild_id") {
    Some(String(_)) => ChatType::Group
    _ => ChatType::Direct
  }
  // Parse attachments
  let attachments : Array[Attachment] = []
  match data.get("attachments") {
    Some(Array(arr)) => {
      let mut i = 0
      while i < arr.length() {
        match arr[i] {
          Object(att) => {
            let url = match att.get("url") {
              Some(String(s)) => s
              _ => ""
            }
            let filename = match att.get("filename") {
              Some(String(s)) => Some(s)
              _ => None
            }
            let size_bytes = match att.get("size") {
              Some(Number(n, ..)) => Some(n.to_int())
              _ => None
            }
            let content_type = match att.get("content_type") {
              Some(String(s)) => s
              _ => ""
            }
            let att_type = if content_type.has_prefix("image/") {
              AttachmentType::Image
            } else if content_type.has_prefix("audio/") {
              AttachmentType::Audio
            } else if content_type.has_prefix("video/") {
              AttachmentType::Video
            } else {
              AttachmentType::File
            }
            if !url.is_empty() {
              attachments.push({
                attachment_type: att_type,
                url,
                filename,
                size_bytes,
              })
            }
          }
          _ => ()
        }
        i = i + 1
      }
    }
    _ => ()
  }
  // Extract reply_to from message_reference
  let reply_to = match data.get("message_reference") {
    Some(Object(ref_obj)) =>
      match ref_obj.get("message_id") {
        Some(String(s)) => Some(s)
        _ => None
      }
    _ => None
  }
  // Extract timestamp
  let timestamp = match data.get("timestamp") {
    Some(String(_ts)) => 0 // TODO: parse ISO 8601 to millis
    _ => 0
  }
  Ok({
    event_type: EventType::Message,
    platform: Platform::Discord,
    chat_id,
    message_id,
    sender_id,
    sender_name,
    text,
    attachments,
    timestamp,
    reply_to,
    chat_type,
    raw: Some(json),
    observe_only: false,
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

///|
/// Process a raw Gateway event and dispatch to the message callback.
///
/// This is the main event handler called for each incoming Gateway message.
/// It handles opcodes: Dispatch (0), Heartbeat (1), Reconnect (7),
/// InvalidSession (9), Hello (10), HeartbeatAck (11).
pub fn DiscordAdapter::handle_gateway_event(
  self : DiscordAdapter,
  raw : String,
) -> Unit {
  let json = @json.parse(raw) catch { _ => return }
  let (op, data) = match parse_gateway_event(json) {
    Ok(v) => v
    Err(_) => return
  }
  let state = match self.gateway_state {
    Some(s) => s
    None => return
  }
  // Update sequence number if present
  match extract_seq(json) {
    Some(seq) => state.update_seq(seq)
    None => ()
  }
  match op {
    0 =>
      // Dispatch - check event name
      match extract_event_name(json) {
        Some("MESSAGE_CREATE") =>
          match DiscordAdapter::parse_event(json) {
            Ok(event) =>
              match self.message_callback {
                Some(cb) => cb(event)
                None => ()
              }
            Err(_) => () // filtered (e.g. bot messages)
          }
        Some("READY") =>
          match parse_ready_payload(data) {
            Ok((session_id, resume_url)) =>
              state.handle_ready(session_id, resume_url)
            Err(_) => ()
          }
        _ => () // ignore other dispatch events
      }
    1 => {
      // Heartbeat request from server - respond with heartbeat
      // TODO: send build_heartbeat_payload(state.last_seq) via websocket
      let _ = build_heartbeat_payload(state.last_seq)
    }
    7 =>
      // Reconnect - server requests reconnection
      // TODO: Close current websocket, reconnect to get_gateway_url(state)
      state.reset_connection()
    9 => {
      // Invalid Session
      let resumable = parse_invalid_session(data)
      if !resumable {
        // Clear session data for fresh Identify
        state.session_id = None
        state.last_seq = None
      }
      // TODO: Send Identify or Resume after random 1-5s delay
      state.reset_connection()
    }
    10 =>
      // Hello - extract heartbeat interval and send Identify/Resume
      match parse_hello_payload(data) {
        Ok(interval) => {
          state.handle_hello(interval)
          // TODO: Start heartbeat timer with interval ms
          // TODO: Send Identify or Resume based on should_resume(state)
          if should_resume(state) {
            match (state.session_id, state.last_seq) {
              (Some(sid), Some(seq)) => {
                let _ = build_resume_payload(self.bot_token, sid, seq)
                // TODO: send resume payload via websocket
              }
              _ => {
                let _ = build_identify_payload(self.bot_token, state.intents)
                // TODO: send identify payload via websocket
              }
            }
          } else {
            let _ = build_identify_payload(self.bot_token, state.intents)
            // TODO: send identify payload via websocket
          }
        }
        Err(_) => ()
      }
    11 =>
      // Heartbeat ACK
      state.mark_heartbeat_acked()
    _ => () // ignore unknown opcodes
  }
}
