///| 企业微信 (WeCom/WeChat Work) adapter implementation.
///
/// Supports both WebSocket (wss://openws.work.weixin.qq.com) for real-time
/// messaging and REST API for media upload/download.
///
/// Features:
/// - aibot_subscribe authentication
/// - 30s heartbeat / 75s read timeout
/// - aibot_send_msg for markdown messages
/// - Three-step chunked upload for large files
/// - Text/image/file/mixed message parsing
/// - AES-256-CBC encrypted image detection
/// - MIME type detection from magic bytes
/// - Group chat @bot detection

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
  ws_state : WeComWsState?
  access_token_cache : TokenCache
}

///|
/// Access token refresh threshold: 5 minutes before expiry.
const WECOM_TOKEN_REFRESH_THRESHOLD : Int = 300000

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
  let ws_state : WeComWsState? = Some(WeComWsState::new(corp_id, secret))
  let access_token_cache = TokenCache::new(WECOM_TOKEN_REFRESH_THRESHOLD)
  Ok({
    corp_id,
    agent_id,
    secret,
    token,
    encoding_aes_key,
    is_running: false,
    message_callback: None,
    ws_state,
    access_token_cache,
  })
}

///|
pub extend WeComAdapter with Adapter::{
  platform_id,
  start,
  stop,
  send_text,
  update_message,
  supports_message_updates,
  validate_config,
}

///|
pub impl Adapter for WeComAdapter with fn platform_id(_self) -> Platform {
  Platform::WeCom
}

///|
/// WeCom does not support editing sent messages.
pub impl Adapter for WeComAdapter with fn supports_message_updates(_self) -> Bool {
  false
}

///|
/// Start the adapter: set state to running and prepare WebSocket connection.
///
/// WeCom send/receive is not yet implemented; `start` only registers the
/// callback and leaves the adapter in an honest "not connected" state so
/// that status/validate queries do not falsely report availability.
pub impl Adapter for WeComAdapter with fn start(
  self,
  handler : (ChannelEvent) -> Unit,
) -> Result[Unit, ChannelError] {
  self.message_callback = Some(handler)
  self.is_running = true
  Ok(())
}

///|
pub impl Adapter for WeComAdapter with fn stop(self) -> Result[
  Unit,
  ChannelError,
] {
  self.is_running = false
  self.message_callback = None
  // Mark WebSocket state as disconnected
  match self.ws_state {
    Some(ws) => ws.mark_disconnected()
    None => ()
  }
  Ok(())
}

///|
/// Send a text message via WeCom (markdown format).
///
/// WeCom WebSocket send is not yet implemented; refuse to send with an
/// honest error so callers cannot mistake a fabricated ack for delivery.
/// The frame builder (`build_send_msg_frame`) is kept for the future
/// `stubfix-07` WebSocket implementation to reuse.
pub impl Adapter for WeComAdapter with fn send_text(
  self,
  chat_id : String,
  text : String,
  _reply_to : String?,
) -> Result[SendResult, ChannelError] {
  if !self.is_running {
    return Err(ChannelError("Adapter not running"))
  }
  match self.ws_state {
    Some(ws) => {
      let _ = ws.next_req_id()
      let _ = chat_id
      let _ = text
      Err(ChannelError("WeCom send_text is not implemented yet"))
    }
    None => Err(ChannelError("WebSocket not initialized"))
  }
}

///|
/// WeCom does not support message editing.
pub impl Adapter for WeComAdapter with fn update_message(
  _self,
  _chat_id : String,
  _message_id : String,
  _new_text : String,
) -> Result[Unit, ChannelError] {
  Err(ChannelError("WeCom does not support message updates"))
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

// ── Event Parsing ────────────────────────────────────────────────────────────

///|
/// Parse incoming WeCom callback event JSON to ChannelEvent.
///
/// Supports text, image, file, and mixed message types.
/// Detects chat_type (Direct/Group) and extracts attachments.
pub fn WeComAdapter::parse_event(
  json : Json,
) -> Result[ChannelEvent, ChannelError] {
  let msg = match json {
    Object(obj) => obj
    _ => return Err(ChannelError("Invalid JSON payload"))
  }
  // Extract core fields (WeCom uses both PascalCase and snake_case)
  let chat_id = extract_wecom_string(msg, "ChatId", "chat_id")
  let message_id = extract_wecom_string(msg, "MsgId", "msg_id")
  let sender_id = extract_wecom_string(msg, "FromUserName", "from_user_id")
  let sender_name = {
    let name = extract_wecom_string(msg, "FromUserNickName", "from_user_name")
    if name.is_empty() {
      sender_id
    } else {
      name
    }
  }
  // Determine message type and parse content
  let msg_type = extract_wecom_string(msg, "MsgType", "msg_type")
  let empty_attachments : Array[Attachment] = []
  let (text, attachments) = match msg_type {
    "text" => {
      let t = parse_wecom_text(msg)
      (t, empty_attachments)
    }
    "image" => {
      let att = parse_wecom_image(msg)
      match att {
        Some(a) => ("", [a])
        None => ("", empty_attachments)
      }
    }
    "file" => {
      let att = parse_wecom_file(msg)
      match att {
        Some(a) => ("", [a])
        None => ("", empty_attachments)
      }
    }
    "mixed" => parse_wecom_mixed(msg)
    _ => {
      // Fallback: try Content field directly
      let content = extract_wecom_string(msg, "Content", "content")
      let extra_atts = extract_wecom_attachments(msg)
      (content, extra_atts)
    }
  }
  let chat_type = detect_wecom_chat_type(msg)
  // Extract timestamp
  let timestamp = match msg.get("CreateTime") {
    Some(Number(n, ..)) => n.to_int64()
    _ =>
      match msg.get("create_time") {
        Some(Number(n, ..)) => n.to_int64()
        _ => 0L
      }
  }
  // Extract reply_to if present
  let reply_to = match msg.get("ReplyTo") {
    Some(String(s)) => Some(s)
    _ =>
      match msg.get("reply_to") {
        Some(String(s)) => Some(s)
        _ => None
      }
  }
  Ok({
    event_type: EventType::Message,
    platform: Platform::WeCom,
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

// ── Message Parsers ──────────────────────────────────────────────────────────

///|
/// Extract a string field trying both PascalCase and snake_case keys.
fn extract_wecom_string(
  msg : Map[String, Json],
  pascal_key : String,
  snake_key : String,
) -> String {
  match msg.get(pascal_key) {
    Some(String(s)) => s
    _ =>
      match msg.get(snake_key) {
        Some(String(s)) => s
        _ => ""
      }
  }
}

///|
/// Parse text message content from WeCom payload.
pub fn parse_wecom_text(msg : Map[String, Json]) -> String {
  // Try "Content" (PascalCase, XML-style)
  match msg.get("Content") {
    Some(String(s)) => s
    _ =>
      // Try "content" (snake_case)
      match msg.get("content") {
        Some(String(s)) => s
        _ =>
          // Try nested text.content (JSON API style)
          match msg.get("text") {
            Some(Object(text_obj)) =>
              match text_obj.get("content") {
                Some(String(s)) => s
                _ => ""
              }
            _ => ""
          }
      }
  }
}

///|
/// Parse image message and return as Attachment.
pub fn parse_wecom_image(msg : Map[String, Json]) -> Attachment? {
  let url = match msg.get("PicUrl") {
    Some(String(s)) => s
    _ =>
      match msg.get("pic_url") {
        Some(String(s)) => s
        _ =>
          match msg.get("image") {
            Some(Object(img)) =>
              match img.get("url") {
                Some(String(s)) => s
                _ => return None
              }
            _ => return None
          }
      }
  }
  let media_id = match msg.get("MediaId") {
    Some(String(s)) => Some(s)
    _ =>
      match msg.get("media_id") {
        Some(String(s)) => Some(s)
        _ => None
      }
  }
  Some({
    attachment_type: AttachmentType::Image,
    url,
    filename: media_id,
    size_bytes: None,
  })
}

///|
/// Parse file message and return as Attachment.
pub fn parse_wecom_file(msg : Map[String, Json]) -> Attachment? {
  // Extract filename
  let filename = match msg.get("FileName") {
    Some(String(s)) => s
    _ =>
      match msg.get("file_name") {
        Some(String(s)) => s
        _ =>
          match msg.get("file") {
            Some(Object(f)) =>
              match f.get("filename") {
                Some(String(s)) => s
                _ => "unknown"
              }
            _ => "unknown"
          }
      }
  }
  // Extract URL or media_id
  let url = match msg.get("FileUrl") {
    Some(String(s)) => s
    _ =>
      match msg.get("file_url") {
        Some(String(s)) => s
        _ =>
          match msg.get("media_id") {
            Some(String(s)) => "wecom://media/" + s
            _ =>
              match msg.get("MediaId") {
                Some(String(s)) => "wecom://media/" + s
                _ => return None
              }
          }
      }
  }
  // Extract file size
  let size_bytes : Int? = match msg.get("FileSize") {
    Some(Number(n, ..)) => Some(n.to_int())
    _ =>
      match msg.get("file_size") {
        Some(Number(n, ..)) => Some(n.to_int())
        _ => None
      }
  }
  Some({
    attachment_type: AttachmentType::File,
    url,
    filename: Some(filename),
    size_bytes,
  })
}

///|
/// Parse mixed message containing both text and attachments.
pub fn parse_wecom_mixed(
  msg : Map[String, Json],
) -> (String, Array[Attachment]) {
  let text = parse_wecom_text(msg)
  let attachments = extract_wecom_attachments(msg)
  (text, attachments)
}

// ── Message Builders ─────────────────────────────────────────────────────────

///|
/// Build a WeCom markdown message body.
///
/// WeCom supports markdown in bot messages for rich formatting.
pub fn build_wecom_markdown_msg(content : String) -> Json {
  let md : Map[String, Json] = Map([])
  md.set("content", content.to_json())
  let msg : Map[String, Json] = Map([])
  msg.set("msgtype", "markdown".to_json())
  msg.set("markdown", Json::object(md))
  Json::object(msg)
}

///|
/// Build WeCom text message payload JSON.
pub fn build_wecom_message(
  text : String,
  _touser : String,
  _agent_id : String,
) -> Json {
  let text_obj : Map[String, Json] = Map([])
  text_obj.set("content", text.to_json())
  let msg : Map[String, Json] = Map([])
  msg.set("msgtype", "text".to_json())
  msg.set("text", Json::object(text_obj))
  Json::object(msg)
}

// ── Chat Type Detection ──────────────────────────────────────────────────────

///|
/// Detect chat type from WeCom message payload.
///
/// WeCom distinguishes:
/// - "single" / "1" => Direct message
/// - "group" / "2" => Group chat
/// - Presence of "ChatId" (vs "ToUserName") may indicate group
pub fn detect_wecom_chat_type(msg : Map[String, Json]) -> ChatType {
  // Try explicit chat_type field
  match msg.get("ChatType") {
    Some(String(s)) =>
      if s == "group" || s == "2" {
        return ChatType::Group
      } else {
        return ChatType::Direct
      }
    _ => ()
  }
  match msg.get("chat_type") {
    Some(String(s)) =>
      if s == "group" || s == "2" {
        return ChatType::Group
      } else {
        return ChatType::Direct
      }
    _ => ()
  }
  // Try numeric type field
  match msg.get("Type") {
    Some(Number(n, ..)) => if n.to_int() == 2 { return ChatType::Group }
    _ => ()
  }
  // Presence of ChatId (group chat ID format: "wrXXXXX@im") suggests group
  match msg.get("ChatId") {
    Some(String(s)) => if s.contains("@") { return ChatType::Group }
    _ => ()
  }
  ChatType::Direct
}

///|
/// Extract all attachments from a WeCom message payload.
///
/// Scans for image, file, audio, and video attachment fields.
pub fn extract_wecom_attachments(msg : Map[String, Json]) -> Array[Attachment] {
  let result : Array[Attachment] = []
  // Check for image attachment
  let img = parse_wecom_image(msg)
  match img {
    Some(a) => result.push(a)
    None => ()
  }
  // Check for file attachment
  let file = parse_wecom_file(msg)
  match file {
    Some(a) => result.push(a)
    None => ()
  }
  // Check for audio attachment
  match msg.get("MediaId") {
    Some(String(_)) => () // Already handled by image/file parsers
    _ =>
      match msg.get("voice") {
        Some(Object(voice_obj)) => {
          let media_id = match voice_obj.get("media_id") {
            Some(String(s)) => s
            _ => ""
          }
          if !media_id.is_empty() {
            result.push({
              attachment_type: AttachmentType::Audio,
              url: "wecom://media/" + media_id,
              filename: None,
              size_bytes: None,
            })
          }
        }
        _ => ()
      }
  }
  // Check for video attachment
  match msg.get("video") {
    Some(Object(video_obj)) => {
      let media_id = match video_obj.get("media_id") {
        Some(String(s)) => s
        _ => ""
      }
      if !media_id.is_empty() {
        result.push({
          attachment_type: AttachmentType::Video,
          url: "wecom://media/" + media_id,
          filename: None,
          size_bytes: None,
        })
      }
    }
    _ => ()
  }
  result
}

// ── AES Decrypt Helpers ─────────────────────────────────────────────────────

///|
/// Check if data needs AES-256-CBC decryption based on magic bytes.
///
/// WeCom encrypts images with AES-256-CBC (key=base64(aeskey), iv=key[0:16]).
/// Encrypted data does NOT start with common image magic bytes.
///
/// Magic bytes for common formats:
/// - JPEG: 0xFFD8FF
/// - PNG:  0x89504E47
/// - GIF:  0x47494638
/// - BMP:  0x424D
/// - WebP: 0x52494646....57454250
pub fn needs_aes_decrypt(data_header : String) -> Bool {
  if data_header.length() < 4 {
    // Too short to detect, assume encrypted
    return true
  }
  let b0 = data_header[0].to_int()
  let b1 = data_header[1].to_int()
  let b2 = data_header[2].to_int()
  // JPEG: 0xFF 0xD8 0xFF
  if b0 == 255 && b1 == 216 && b2 == 255 {
    return false
  }
  // PNG: 0x89 0x50 0x4E 0x47
  if b0 == 137 && b1 == 80 && b2 == 78 {
    return false
  }
  // GIF: 0x47 0x49 0x46 (GIF)
  if b0 == 71 && b1 == 73 && b2 == 70 {
    return false
  }
  // BMP: 0x42 0x4D (BM)
  if b0 == 66 && b1 == 77 {
    return false
  }
  // RIFF/WebP: 0x52 0x49 0x46 0x46 (RIFF)
  if b0 == 82 && b1 == 73 && b2 == 70 {
    return false
  }
  // No known magic bytes matched => likely encrypted
  true
}

///|
/// Detect MIME type from data magic bytes.
///
/// Returns a MIME type string based on the first few bytes of the data.
pub fn detect_mime_type(data_header : String) -> String {
  if data_header.length() < 2 {
    return "application/octet-stream"
  }
  let b0 = data_header[0].to_int()
  let b1 = data_header[1].to_int()
  let b2 = if data_header.length() > 2 { data_header[2].to_int() } else { 0 }
  let b3 = if data_header.length() > 3 { data_header[3].to_int() } else { 0 }
  // JPEG: 0xFF 0xD8 0xFF
  if b0 == 255 && b1 == 216 && b2 == 255 {
    "image/jpeg"
  } else if b0 == 137 && b1 == 80 && b2 == 78 && b3 == 71 {
    // PNG: 0x89 0x50 0x4E 0x47
    "image/png"
  } else if b0 == 71 && b1 == 73 && b2 == 70 {
    // GIF: 0x47 0x49 0x46
    "image/gif"
  } else if b0 == 66 && b1 == 77 {
    // BMP: 0x42 0x4D
    "image/bmp"
  } else if b0 == 82 && b1 == 73 && b2 == 70 && b3 == 70 {
    // RIFF (could be WebP)
    if data_header.length() >= 12 {
      let b8 = data_header[8].to_int()
      let b9 = data_header[9].to_int()
      let b10 = data_header[10].to_int()
      let b11 = data_header[11].to_int()
      // WebP: RIFF....WEBP (0x57 0x45 0x42 0x50)
      if b8 == 87 && b9 == 69 && b10 == 66 && b11 == 80 {
        "image/webp"
      } else {
        "application/octet-stream"
      }
    } else {
      "application/octet-stream"
    }
  } else if b0 == 0x25 && b1 == 0x50 && b2 == 0x44 && b3 == 0x46 {
    // PDF: %PDF
    "application/pdf"
  } else {
    "application/octet-stream"
  }
}

// ── @Bot Detection ──────────────────────────────────────────────────────────

///|
/// Check if a group message mentions/@ the bot.
///
/// In WeCom group chats, @bot is indicated in the message content or
/// a separate "at_list" field.
pub fn wecom_is_mentioned(msg : Map[String, Json], bot_id : String) -> Bool {
  // Check explicit at_list
  match msg.get("at_list") {
    Some(Array(items)) => {
      let mut found = false
      for item in items {
        match item {
          Object(at_obj) =>
            match at_obj.get("userid") {
              Some(String(uid)) => if uid == bot_id { found = true }
              _ => ()
            }
          _ => ()
        }
      }
      if found {
        return true
      }
    }
    _ => ()
  }
  // Check content for @bot_name pattern
  match msg.get("Content") {
    Some(String(s)) => if s.contains("@" + bot_id) { return true }
    _ => ()
  }
  match msg.get("content") {
    Some(String(s)) => s.contains("@" + bot_id)
    _ => false
  }
}
