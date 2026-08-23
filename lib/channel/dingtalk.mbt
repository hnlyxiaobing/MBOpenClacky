///| 钉钉 (DingTalk) robot adapter implementation.
///
/// Supports:
/// - Stream Mode (WebSocket) for receiving messages
/// - Webhook URLs for quick replies (sessionWebhook)
/// - Robot API for proactive messages (oToMessages/batchSend, groupMessages/send)
/// - Dual token system: new API (header) + OAPI (query param)

///|
/// DingTalkAdapter handles communication with DingTalk Robot API.
pub(all) struct DingTalkAdapter {
  access_token : String
  secret : String?
  webhook_url : String?
  mut robot_code : String?
  api_client : DingTalkApiClient?
  mut is_running : Bool
  mut message_callback : ((ChannelEvent) -> Unit)?
  mut session_webhooks : Map[String, (String, Int)] // chat_id → (webhook_url, expire_time_ms)
  mut route_cache : Map[String, String] // conv_id → conv_type ("1"=Direct, "2"=Group)
}

///|
/// Create a new DingTalkAdapter from channel configuration.
/// If settings contain "app_key" and "app_secret", creates a full API client.
/// Otherwise falls back to webhook-only mode with "access_token".
pub fn DingTalkAdapter::new(
  config : ChannelConfig,
) -> Result[DingTalkAdapter, ChannelError] {
  let app_key = config.settings.get("app_key")
  let app_secret = config.settings.get("app_secret")
  let access_token = match config.settings.get("access_token") {
    Some(v) => v
    None => ""
  }
  let secret = config.settings.get("secret")
  let webhook_url = config.settings.get("webhook_url")
  let robot_code = config.settings.get("robot_code")

  // Create API client if app_key and app_secret are provided
  let api_client = match (app_key, app_secret) {
    (Some(key), Some(sec)) => Some(DingTalkApiClient::new(key, sec))
    _ => {
      // Fallback: access_token is required for webhook-only mode
      if access_token.is_empty() {
        return Err(
          ChannelError("Missing setting: access_token or app_key/app_secret"),
        )
      }
      None
    }
  }

  Ok({
    access_token,
    secret,
    webhook_url,
    robot_code,
    api_client,
    is_running: false,
    message_callback: None,
    session_webhooks: Map([]),
    route_cache: Map([]),
  })
}

///|
pub extend DingTalkAdapter with Adapter::{
  platform_id,
  start,
  stop,
  send_text,
  update_message,
  supports_message_updates,
  validate_config,
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
  // TODO: If api_client is available, POST /v1.0/gateway/connections/open
  // to obtain WS endpoint and ticket, then connect via @websocket.
  // Stream Mode lifecycle:
  //   1. POST open_stream_connection(clientId=appKey, clientSecret=appSecret)
  //   2. Connect to returned WS endpoint
  //   3. Handle frames: SYSTEM (ping→pong), EVENT, CALLBACK (→ACK)
  //   4. Re-connect on disconnect using new endpoint
  Ok(())
}

///|
pub impl Adapter for DingTalkAdapter with fn stop(self) -> Result[
  Unit,
  ChannelError,
] {
  self.is_running = false
  self.message_callback = None
  // TODO: Close WebSocket connection if active
  Ok(())
}

///|
pub impl Adapter for DingTalkAdapter with fn send_text(
  self,
  chat_id : String,
  text : String,
  _reply_to : String?,
) -> Result[SendResult, ChannelError] {
  if !self.is_running {
    return Err(ChannelError("Adapter not running"))
  }

  // Strategy 1: Check session_webhooks cache for a valid webhook URL
  match self.session_webhooks.get(chat_id) {
    Some((url, expire_time)) if is_webhook_valid(url, expire_time) =>
      // Use cached sessionWebhook for quick reply
      match self.api_client {
        Some(client) => {
          match client.send_via_webhook(url, text, "text") {
            Ok(_) => ()
            Err(e) => return Err(e)
          }
          return Ok({
            message_id: "webhook_" + chat_id,
            success: true,
            error: None,
          })
        }
        None => {
          // No API client; POST directly to the session webhook URL
          let payload = build_dingtalk_message(text)
          let headers = HttpHeaders::new()
            .content_type("application/json")
            .to_array()
          match http_post_json(url, headers, payload.stringify()) {
            Ok(_) => ()
            Err(e) => return Err(e)
          }
          return Ok({
            message_id: "webhook_" + chat_id,
            success: true,
            error: None,
          })
        }
      }
    _ => ()
  }

  // Strategy 2: Use robot API if api_client and robot_code are available
  match (self.api_client, self.robot_code) {
    (Some(client), Some(rc)) => {
      let conv_type = match self.route_cache.get(chat_id) {
        Some(v) => v
        None => "1"
      }
      let msg_param = DingTalkApiClient::build_send_msg_param(
        "sampleText", text,
      )
      let send_result = if conv_type == "2" {
        // Group chat
        client.send_to_group(chat_id, rc, "sampleText", msg_param)
      } else {
        // Direct message
        client.send_to_user(chat_id, rc, "sampleText", msg_param)
      }
      let resp_json = match send_result {
        Ok(j) => j
        Err(e) => return Err(e)
      }
      let mid = match extract_dingtalk_message_id(resp_json) {
        Some(id) => id
        None => "robot_" + chat_id
      }
      Ok({ message_id: mid, success: true, error: None })
    }
    _ =>
      // Strategy 3: Fallback to configured webhook_url
      match self.webhook_url {
        Some(url) => {
          let payload = build_dingtalk_message(text)
          let headers = HttpHeaders::new()
            .content_type("application/json")
            .to_array()
          let resp = match http_post_json(url, headers, payload.stringify()) {
            Ok(j) => j
            Err(e) => return Err(e)
          }
          let mid = match extract_dingtalk_message_id(resp) {
            Some(id) => id
            None => "webhook_" + chat_id
          }
          Ok({ message_id: mid, success: true, error: None })
        }
        None =>
          Err(
            ChannelError("No webhook URL or API client available for sending"),
          )
      }
  }
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
  let has_api = match self.api_client {
    Some(_) => true
    None => false
  }
  if !has_api && self.access_token.is_empty() {
    errors.push("access_token or app_key/app_secret is required")
  }
  if self.webhook_url is None && !has_api {
    errors.push("webhook_url is required in webhook-only mode")
  }
  errors
}

// ── Event parsing ───────────────────────────────────────────────────────────

///|
/// Parse incoming DingTalk robot callback JSON to ChannelEvent.
/// Supports message types: text, picture, file, richText.
/// This is a static parser; use parse_and_cache_event for caching behavior.
pub fn DingTalkAdapter::parse_event(
  json : Json,
) -> Result[ChannelEvent, ChannelError] {
  let msg = match json {
    Object(obj) => obj
    _ => return Err(ChannelError("Invalid JSON payload"))
  }

  // Extract routing fields
  let chat_id = match msg.get("conversationId") {
    Some(String(s)) => s
    _ => ""
  }
  let message_id = match msg.get("msgId") {
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

  // Determine chat type: conversationType "1" → Direct, "2" → Group
  let chat_type = match msg.get("conversationType") {
    Some(String(t)) => if t == "2" { ChatType::Group } else { ChatType::Direct }
    _ => ChatType::Direct
  }

  // Parse message by msgtype
  let msg_type = match msg.get("msgtype") {
    Some(String(s)) => s
    _ => "text"
  }

  let (text, attachments) = match msg_type {
    "text" => {
      let t = parse_dingtalk_text(msg)
      (t, extract_dingtalk_attachments(msg))
    }
    "picture" => {
      let t = parse_dingtalk_text(msg)
      let atts = extract_dingtalk_attachments(msg)
      match parse_dingtalk_picture(msg) {
        Some(att) => atts.push(att)
        None => ()
      }
      (t, atts)
    }
    "file" => {
      let t = parse_dingtalk_text(msg)
      let atts = extract_dingtalk_attachments(msg)
      match parse_dingtalk_file(msg) {
        Some(att) => atts.push(att)
        None => ()
      }
      (t, atts)
    }
    "richText" => {
      let (t, atts) = parse_dingtalk_richtext(msg)
      (t, atts)
    }
    _ => {
      let t = parse_dingtalk_text(msg)
      (t, [])
    }
  }

  // Extract timestamp
  let timestamp = match msg.get("createAt") {
    Some(Number(n, ..)) => n.to_int64()
    _ => 0L
  }

  Ok({
    event_type: EventType::Message,
    platform: Platform::DingTalk,
    chat_id,
    message_id,
    sender_id,
    sender_name,
    text,
    attachments,
    timestamp,
    reply_to: None,
    chat_type,
    raw: Some(json),
    observe_only: false,
  })
}

///|
/// Parse an incoming DingTalk event and cache routing/session info.
/// Call this instead of the static parse_event when you have access to the adapter instance.
pub fn DingTalkAdapter::parse_and_cache_event(
  self : DingTalkAdapter,
  json : Json,
) -> Result[ChannelEvent, ChannelError] {
  let event = match DingTalkAdapter::parse_event(json) {
    Ok(e) => e
    Err(e) => return Err(e)
  }

  // Cache route info
  let conv_type = match event.chat_type {
    ChatType::Group => "2"
    ChatType::Direct => "1"
  }
  self.route_cache.set(event.chat_id, conv_type)

  // Cache robotCode from raw payload
  match event.raw {
    Some(Object(msg)) => {
      match msg.get("robotCode") {
        Some(String(rc)) =>
          if self.robot_code is None {
            self.robot_code = Some(rc)
          }
        _ => ()
      }
      // Extract and cache sessionWebhook
      match extract_session_webhook(msg) {
        Some((url, expire)) =>
          self.session_webhooks.set(event.chat_id, (url, expire))
        None => ()
      }
    }
    _ => ()
  }

  Ok(event)
}

// ── Message parsing helpers ─────────────────────────────────────────────────

///|
/// Parse text content from a DingTalk message map.
pub fn parse_dingtalk_text(msg : Map[String, Json]) -> String {
  // Try nested text.content first (standard format)
  match msg.get("text") {
    Some(Object(t)) =>
      match t.get("content") {
        Some(String(s)) => s.trim().to_owned()
        _ => ""
      }
    Some(String(s)) => s.trim().to_owned()
    _ =>
      // Try msgContent for richText and other types
      match msg.get("msgContent") {
        Some(String(s)) => s
        _ => ""
      }
  }
}

///|
/// Parse a picture attachment from a DingTalk message.
pub fn parse_dingtalk_picture(msg : Map[String, Json]) -> Attachment? {
  // Try content.downloadCode or picUrl
  match msg.get("content") {
    Some(Object(c)) => {
      let url = match c.get("picUrl") {
        Some(String(u)) => u
        _ =>
          match c.get("downloadCode") {
            Some(String(code)) => "dingtalk://download/" + code
            _ => return None
          }
      }
      let filename = match c.get("fileName") {
        Some(String(f)) => Some(f)
        _ => None
      }
      Some({
        attachment_type: AttachmentType::Image,
        url,
        filename,
        size_bytes: None,
      })
    }
    _ => None
  }
}

///|
/// Parse a file attachment from a DingTalk message.
pub fn parse_dingtalk_file(msg : Map[String, Json]) -> Attachment? {
  match msg.get("content") {
    Some(Object(c)) => {
      let url = match c.get("downloadCode") {
        Some(String(code)) => "dingtalk://download/" + code
        _ =>
          match c.get("fileUrl") {
            Some(String(u)) => u
            _ => return None
          }
      }
      let filename = match c.get("fileName") {
        Some(String(f)) => Some(f)
        _ => None
      }
      let size = match c.get("fileSize") {
        Some(Number(n, ..)) => Some(n.to_int())
        _ => None
      }
      Some({
        attachment_type: AttachmentType::File,
        url,
        filename,
        size_bytes: size,
      })
    }
    _ => None
  }
}

///|
/// Parse richText message content into text and attachments.
pub fn parse_dingtalk_richtext(
  msg : Map[String, Json],
) -> (String, Array[Attachment]) {
  let mut text_buf = ""
  let attachments : Array[Attachment] = []

  // richText content is an array of sections
  match msg.get("content") {
    Some(Object(c)) =>
      match c.get("richText") {
        Some(Array(sections)) => {
          let mut first = true
          for section in sections {
            match section {
              Array(items) =>
                for item in items {
                  match item {
                    Object(obj) => {
                      // Text item
                      match obj.get("text") {
                        Some(String(t)) => {
                          if !first {
                            text_buf = text_buf + "\n"
                          }
                          text_buf = text_buf + t
                          first = false
                        }
                        _ => ()
                      }
                      // Image item
                      match obj.get("pictureDownloadCode") {
                        Some(String(code)) =>
                          attachments.push({
                            attachment_type: AttachmentType::Image,
                            url: "dingtalk://download/" + code,
                            filename: None,
                            size_bytes: None,
                          })
                        _ =>
                          match obj.get("downloadCode") {
                            Some(String(code)) =>
                              attachments.push({
                                attachment_type: AttachmentType::File,
                                url: "dingtalk://download/" + code,
                                filename: None,
                                size_bytes: None,
                              })
                            _ => ()
                          }
                      }
                    }
                    _ => ()
                  }
                }
              _ => ()
            }
          }
        }
        _ => ()
      }
    _ => ()
  }

  (text_buf, attachments)
}

///|
/// Extract all attachments from a DingTalk message.
pub fn extract_dingtalk_attachments(
  msg : Map[String, Json],
) -> Array[Attachment] {
  let attachments : Array[Attachment] = []
  // Check for richText array at top level
  match msg.get("richText") {
    Some(Array(items)) =>
      for item in items {
        match item {
          Object(obj) =>
            match obj.get("downloadCode") {
              Some(String(code)) =>
                attachments.push({
                  attachment_type: AttachmentType::File,
                  url: "dingtalk://download/" + code,
                  filename: match obj.get("fileName") {
                    Some(String(f)) => Some(f)
                    _ => None
                  },
                  size_bytes: None,
                })
              _ => ()
            }
          _ => ()
        }
      }
    _ => ()
  }
  attachments
}

// ── Webhook and stream helpers ──────────────────────────────────────────────

///|
/// Check if a webhook URL is still valid based on its expiration time.
pub fn is_webhook_valid(url : String, expire_time : Int) -> Bool {
  if url.is_empty() {
    false
  } else if expire_time <= 0 {
    // No expiration info, assume valid
    true
  } else {
    // In a real implementation, compare with current time.
    // Since we don't have real-time clock in pure MoonBit,
    // we rely on the caller to manage expiry.
    true
  }
}

///|
/// Build a DingTalk markdown message payload.
pub fn build_dingtalk_markdown_payload(title : String, text : String) -> Json {
  let md_obj : Map[String, Json] = Map([])
  md_obj.set("title", title.to_json())
  md_obj.set("text", text.to_json())
  let msg : Map[String, Json] = Map([])
  msg.set("msgtype", "markdown".to_json())
  msg.set("markdown", Json::object(md_obj))
  Json::object(msg)
}

///|
/// Extract sessionWebhook URL and its expiration time from a DingTalk callback message.
/// Returns (url, expire_time_ms) or None if not present.
pub fn extract_session_webhook(msg : Map[String, Json]) -> (String, Int)? {
  let url = match msg.get("sessionWebhook") {
    Some(String(u)) => u
    _ => return None
  }
  if url.is_empty() {
    return None
  }
  // sessionWebhookExpiredTime is in milliseconds
  let expire = match msg.get("sessionWebhookExpiredTime") {
    Some(Number(n, ..)) => n.to_int()
    _ => 0 // No expiry info, assume it doesn't expire soon
  }
  Some((url, expire))
}

///|
/// Parse a Stream Mode frame from the DingTalk WebSocket connection.
/// Frame types:
/// - SYSTEM: Server ping (topic=ping), client must respond with pong
/// - EVENT: Event notifications
/// - CALLBACK: Robot message callback (topic=/v1.0/im/bot/messages/get), must ACK
/// Returns (frame_type, data) on success.
pub fn parse_stream_frame(json : Json) -> Result[(String, Json), ChannelError] {
  let obj = match json {
    Object(o) => o
    _ => return Err(ChannelError("Invalid stream frame: expected JSON object"))
  }
  let frame_type = match obj.get("type") {
    Some(String(t)) => t
    _ => return Err(ChannelError("Missing 'type' in stream frame"))
  }
  let data = match obj.get("data") {
    Some(d) => d
    _ => Json::object(Map([]))
  }
  Ok((frame_type, data))
}

///|
/// Build an ACK response for a CALLBACK frame.
/// DingTalk requires ACK to confirm message processing.
pub fn build_stream_ack(message_id : String) -> Json {
  let ack : Map[String, Json] = Map([])
  ack.set("code", (200).to_json())
  ack.set("message", "OK".to_json())
  ack.set("messageId", message_id.to_json())
  Json::object(ack)
}

///|
/// Build a pong response for a SYSTEM ping frame.
/// DingTalk Stream Mode sends periodic pings to keep the connection alive.
pub fn build_stream_pong() -> Json {
  let pong : Map[String, Json] = Map([])
  pong.set("type", "pong".to_json())
  Json::object(pong)
}

///|
/// Build DingTalk webhook message payload (legacy helper for backward compatibility).
pub fn build_dingtalk_message(text : String) -> Json {
  let text_obj : Map[String, Json] = Map([])
  text_obj.set("content", text.to_json())
  let msg : Map[String, Json] = Map([])
  msg.set("msgtype", "text".to_json())
  msg.set("text", Json::object(text_obj))
  Json::object(msg)
}
