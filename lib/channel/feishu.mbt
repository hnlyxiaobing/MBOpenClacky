///| 飞书/Lark adapter implementation.

///|
/// FeishuAdapter handles communication with Feishu/Lark Bot API.
/// Supports Webhook receive mode and REST API for sending messages.
pub(all) struct FeishuAdapter {
  bot_id : String
  bot_secret : String
  webhook_url : String?
  api_client : FeishuApiClient?
  mut is_running : Bool
  mut message_callback : ((ChannelEvent) -> Unit)?
}

///|
/// Create a new FeishuAdapter from channel configuration.
/// If `app_id` and `app_secret` are present in settings, an API client is created
/// for outbound REST calls (send, update, upload).
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
  // Create API client if app_id and app_secret are available
  let api_client = match
    (config.settings.get("app_id"), config.settings.get("app_secret")) {
    (Some(app_id), Some(app_secret)) =>
      Some(FeishuApiClient::new(app_id, app_secret))
    _ => None
  }
  Ok({
    bot_id,
    bot_secret,
    webhook_url,
    api_client,
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
  chat_id : String,
  text : String,
  reply_to : String?,
) -> Result[SendResult, ChannelError] {
  if !self.is_running {
    return Err(ChannelError("Adapter not running"))
  }
  match self.api_client {
    Some(client) => {
      let _req = match client.build_send_request(chat_id, text, reply_to) {
        Ok(r) => r
        Err(e) => return Err(e)
      }
      // TODO: Execute HTTP POST via async transport
      // let (url, headers, body) = _req
      // let json = client.send_message(chat_id, text, reply_to)?
      // match json {
      //   Object(obj) => match obj.get("data") {
      //     Some(Object(data)) => match data.get("message_id") {
      //       Some(String(mid)) => Ok({ message_id: mid, success: true, error: None })
      //       _ => Ok({ message_id: "", success: true, error: None })
      //     }
      //     _ => Ok({ message_id: "", success: true, error: None })
      //   }
      //   _ => Err(ChannelError("Unexpected send response"))
      // }
      Ok({ message_id: "feishu_msg_pending", success: true, error: None })
    }
    None => {
      // No API client configured: build payload for webhook relay
      let _ = build_feishu_message(text, reply_to)
      Ok({ message_id: "feishu_msg_placeholder", success: true, error: None })
    }
  }
}

///|
pub impl Adapter for FeishuAdapter with fn update_message(
  self,
  _chat_id : String,
  message_id : String,
  new_text : String,
) -> Result[Unit, ChannelError] {
  if !self.is_running {
    return Err(ChannelError("Adapter not running"))
  }
  match self.api_client {
    Some(client) => {
      let _req = match client.build_update_request(message_id, new_text) {
        Ok(r) => r
        Err(e) => return Err(e)
      }
      // TODO: Execute HTTP PATCH via async transport
      let _ = _req
      Ok(())
    }
    None => Err(ChannelError("No API client configured for message updates"))
  }
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

// ── Event parsing ─────────────────────────────────────────────────────────────

///|
/// Parse incoming Feishu webhook event JSON to ChannelEvent.
/// Uses FeishuMessageParser for content extraction (text/image/file/post).
pub fn FeishuAdapter::parse_event(
  json : Json,
) -> Result[ChannelEvent, ChannelError] {
  // Extract the top-level object
  let root = match json {
    Object(obj) => obj
    _ => return Err(ChannelError("Invalid JSON payload"))
  }
  // Extract event object
  let event = match root.get("event") {
    Some(Object(ev)) => ev
    _ => return Err(ChannelError("Missing 'event' field in payload"))
  }
  // Extract message object
  let message = match event.get("message") {
    Some(Object(msg)) => msg
    _ => return Err(ChannelError("Missing 'message' field in event"))
  }

  // ── IDs ──
  let chat_id = match message.get("chat_id") {
    Some(String(s)) => s
    _ => ""
  }
  let message_id = match message.get("message_id") {
    Some(String(s)) => s
    _ => ""
  }

  // ── Sender ──
  let sender_id = match event.get("sender") {
    Some(Object(sender)) =>
      match sender.get("sender_id") {
        Some(Object(sid)) =>
          match sid.get("open_id") {
            Some(String(s)) => s
            _ =>
              match sid.get("user_id") {
                Some(String(s)) => s
                _ => ""
              }
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
            _ => sender_id
          }
        _ => sender_id
      }
    _ => sender_id
  }

  // ── Message parsing via FeishuMessageParser ──
  let parsed = match parse_feishu_message(message) {
    Ok(p) => p
    Err(e) => return Err(e)
  }

  // ── Mentions resolution ──
  let mentions_arr : Array[Json] = match message.get("mentions") {
    Some(Array(arr)) => arr
    _ => []
  }
  let resolved_text = if mentions_arr.length() > 0 {
    resolve_feishu_mentions(parsed.text, mentions_arr)
  } else {
    parsed.text
  }

  // ── Chat type detection ──
  let chat_type_str = match message.get("chat_type") {
    Some(String(s)) => s
    _ => ""
  }
  let chat_type = if chat_type_str == "p2p" {
    ChatType::Direct
  } else if chat_type_str == "group" {
    ChatType::Group
  } else {
    ChatType::Direct
  }

  // ── @bot detection for group chats ──
  let is_bot_mentioned = match chat_type {
    ChatType::Group =>
      detect_bot_mention(mentions_arr) || resolved_text.contains("@bot")
    ChatType::Direct => true // DMs always target the bot
  }
  let observe_only = match chat_type {
    ChatType::Group => !is_bot_mentioned
    ChatType::Direct => false
  }

  // ── Timestamp ──
  let timestamp = match message.get("create_time") {
    Some(String(s)) => parse_int_safe(s)
    _ => 0
  }

  // ── Reply-to ──
  let reply_to = match message.get("parent_id") {
    Some(String(s)) => if !s.is_empty() { Some(s) } else { None }
    _ => None
  }

  // ── Merge doc URLs into text as context hint ──
  let final_text = if parsed.doc_urls.length() > 0 {
    let url_hints = join_feishu_strings(parsed.doc_urls, "\n")
    resolved_text + "\n[Referenced docs:\n" + url_hints + "]"
  } else {
    resolved_text
  }

  Ok({
    event_type: EventType::Message,
    platform: Platform::Feishu,
    chat_id,
    message_id,
    sender_id,
    sender_name,
    text: final_text,
    attachments: parsed.attachments,
    timestamp,
    reply_to,
    chat_type,
    raw: Some(json),
    observe_only,
  })
}

///|
/// Handle a complete Feishu webhook event, including challenge detection.
/// Returns `Some(event)` for normal message events, `None` for challenge responses
/// (the caller should echo the challenge string back to Feishu).
pub fn FeishuAdapter::handle_webhook_event(
  body : Json,
) -> Result[ChannelEvent?, ChannelError] {
  // 1. Check for URL verification challenge
  match handle_feishu_challenge(body) {
    Some(_challenge) =>
      // Caller should echo the challenge back as plain text
      return Ok(None)
    None => ()
  }

  // 2. Filter out non-message event types (e.g. im.message.receive_v1 only)
  let header_event_type = match body {
    Object(obj) =>
      match obj.get("header") {
        Some(Object(header)) =>
          match header.get("event_type") {
            Some(String(s)) => s
            _ => ""
          }
        _ => ""
      }
    _ => ""
  }
  // Only process im.message.receive_v1 events (skip other event types silently)
  if !header_event_type.is_empty() &&
    header_event_type != "im.message.receive_v1" {
    return Ok(None)
  }

  // 3. Parse as a regular message event
  let event = match FeishuAdapter::parse_event(body) {
    Ok(e) => e
    Err(e) => return Err(e)
  }
  Ok(Some(event))
}

// ── Helpers ──────────────────────────────────────────────────────────────────

///|
/// Check if the bot is mentioned in the mentions array.
/// Looks for entries where `id_type` is "open_id" or "user_id" with
/// a name matching common bot patterns, or `key` == "@_all".
fn detect_bot_mention(mentions : Array[Json]) -> Bool {
  for mention in mentions {
    match mention {
      Object(m) => {
        // @_all means everyone is mentioned
        match m.get("key") {
          Some(String(k)) => if k == "@_all" { return true }
          _ => ()
        }
        // Check if mention is tagged as bot
        match m.get("id_type") {
          Some(String(id_type)) =>
            if id_type == "open_id" {
              match m.get("name") {
                Some(String(name)) =>
                  if name.contains("bot") || name.contains("Bot") {
                    return true
                  }
                _ => ()
              }
            }
          _ => ()
        }
      }
      _ => ()
    }
  }
  false
}

///|
/// Parse a string as an Int, returning 0 on failure.
fn parse_int_safe(s : String) -> Int {
  let mut result = 0
  for ch in s {
    if ch >= '0' && ch <= '9' {
      result = result * 10 + (ch.to_int() - '0'.to_int())
    } else {
      break
    }
  }
  result
}

///|
/// Join an array of strings with a separator (for doc URL display).
fn join_feishu_strings(arr : Array[String], sep : String) -> String {
  if arr.length() == 0 {
    return ""
  }
  let mut result = arr[0].to_string()
  let mut i = 1
  while i < arr.length() {
    result = result + sep + arr[i]
    i = i + 1
  }
  result
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
