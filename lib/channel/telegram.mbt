///| Telegram Bot API adapter implementation.

///|
/// Maximum message length for Telegram Bot API.
pub const TELEGRAM_MAX_MESSAGE_LENGTH : Int = 4096

///|
/// Telegram API client for making Bot API calls.
/// Provides URL building, request payload construction, and response parsing.
pub(all) struct TelegramApiClient {
  bot_token : String
  base_url : String
  http_headers : HttpHeaders
}

///|
/// Create a new TelegramApiClient with default settings.
pub fn TelegramApiClient::new(bot_token : String) -> TelegramApiClient {
  let headers = HttpHeaders::new()
    .content_type("application/json")
    .set("Accept", "application/json")
  { bot_token, base_url: TELEGRAM_API_BASE, http_headers: headers }
}

///|
/// Build the full API URL for a given Bot API method.
/// Format: `{base_url}/bot{token}/{method}`
pub fn TelegramApiClient::api_url(
  self : TelegramApiClient,
  api_method : String,
) -> String {
  self.base_url + "/bot" + self.bot_token + "/" + api_method
}

///|
/// Build request headers as an array of key-value pairs for HTTP requests.
pub fn TelegramApiClient::request_headers(
  _self : TelegramApiClient,
) -> Array[(String, String)] {
  _self.http_headers.to_array()
}

///|
/// Build the getUpdates API request payload as JSON.
pub fn TelegramApiClient::get_updates_payload(
  _self : TelegramApiClient,
  offset : Int,
  timeout : Int,
) -> Json {
  let payload : Map[String, Json] = Map([])
  payload.set("offset", offset.to_json())
  payload.set("timeout", timeout.to_json())
  payload.set("allowed_updates", Json::array([]))
  Json::object(payload)
}

///|
/// Parse the getUpdates API response into an array of Update JSON objects.
pub fn TelegramApiClient::parse_updates_response(
  json : Json,
) -> Result[Array[Json], ChannelError] {
  match json {
    Object(obj) => {
      match obj.get("ok") {
        Some(True) => ()
        _ => {
          let desc = match obj.get("description") {
            Some(String(s)) => s
            _ => "API returned ok=false"
          }
          return Err(ChannelError(desc))
        }
      }
      match obj.get("result") {
        Some(Array(arr)) => Ok(arr)
        _ => Err(ChannelError("Missing 'result' array in getUpdates response"))
      }
    }
    _ => Err(ChannelError("Invalid getUpdates response format"))
  }
}

///|
/// Parse a sendMessage / editMessageText API response to extract message_id.
pub fn TelegramApiClient::parse_send_response(
  json : Json,
) -> Result[SendResult, ChannelError] {
  match json {
    Object(obj) => {
      match obj.get("ok") {
        Some(True) => ()
        _ => {
          let desc = match obj.get("description") {
            Some(String(s)) => s
            _ => "API returned ok=false"
          }
          return Err(ChannelError(desc))
        }
      }
      match obj.get("result") {
        Some(Object(result)) => {
          let msg_id = match result.get("message_id") {
            Some(Number(n, ..)) => n.to_int().to_string()
            _ => ""
          }
          Ok({ message_id: msg_id, success: true, error: None })
        }
        _ => Err(ChannelError("Missing 'result' in send response"))
      }
    }
    _ => Err(ChannelError("Invalid send response format"))
  }
}

///|
/// Parse a generic API response (for deleteMessage, etc.)
pub fn TelegramApiClient::parse_ok_response(
  json : Json,
) -> Result[Bool, ChannelError] {
  match json {
    Object(obj) =>
      match obj.get("ok") {
        Some(True) => Ok(true)
        _ => {
          let desc = match obj.get("description") {
            Some(String(s)) => s
            _ => "API returned ok=false"
          }
          Err(ChannelError(desc))
        }
      }
    _ => Err(ChannelError("Invalid response format"))
  }
}

///|
/// Build the getMe API URL.
pub fn TelegramApiClient::get_me_url(self : TelegramApiClient) -> String {
  self.api_url("getMe")
}

///|
/// Build the getUpdates API URL.
pub fn TelegramApiClient::get_updates_url(self : TelegramApiClient) -> String {
  self.api_url("getUpdates")
}

///|
/// Build the sendMessage API URL.
pub fn TelegramApiClient::send_message_url(self : TelegramApiClient) -> String {
  self.api_url("sendMessage")
}

///|
/// Build the editMessageText API URL.
pub fn TelegramApiClient::edit_message_url(self : TelegramApiClient) -> String {
  self.api_url("editMessageText")
}

///|
/// Build the getFile API URL.
pub fn TelegramApiClient::get_file_url(self : TelegramApiClient) -> String {
  self.api_url("getFile")
}

///|
/// Build the deleteMessage API URL.
pub fn TelegramApiClient::delete_message_url(
  self : TelegramApiClient,
) -> String {
  self.api_url("deleteMessage")
}

// ── TelegramAdapter ──────────────────────────────────────────────────────────

///|
/// TelegramAdapter handles communication via Telegram Bot API.
/// Uses long polling (getUpdates) for receiving messages.
pub(all) struct TelegramAdapter {
  bot_token : String
  mut is_running : Bool
  mut message_callback : ((ChannelEvent) -> Unit)?
  mut last_update_id : Int
  api_client : TelegramApiClient
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
  let api_client = TelegramApiClient::new(bot_token)
  Ok({
    bot_token,
    is_running: false,
    message_callback: None,
    last_update_id: 0,
    api_client,
  })
}

///|
pub extend TelegramAdapter with Adapter::{
  platform_id,
  start,
  stop,
  send_text,
  update_message,
  supports_message_updates,
  validate_config,
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
  // TODO: Start long-polling loop via getUpdates API.
  // The loop should:
  // 1. Call api_client.get_updates_payload(last_update_id + 1, 25) to build request
  // 2. POST to api_client.get_updates_url() with the payload
  // 3. Parse response via api_client.parse_updates_response()
  // 4. For each update, call parse_event() and invoke handler
  // 5. Update last_update_id from each processed update
  // Requires async context: spawn async task using @async runtime
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
  chat_id : String,
  text : String,
  reply_to : String?,
) -> Result[SendResult, ChannelError] {
  if !self.is_running {
    return Err(ChannelError("Adapter not running"))
  }
  // Build request payload (no parse_mode for plain text, decision: risk R3)
  let payload = build_telegram_send_request(chat_id, text, reply_to, None)
  let url = self.api_client.send_message_url()
  let headers = self.api_client.request_headers()
  // Send via http_post_json (same path as Feishu/Discord, decision 1)
  let json = match http_post_json(url, headers, payload.stringify()) {
    Ok(j) => j
    Err(e) => return Err(e)
  }
  // Parse response: extract message_id or map error (decision 2-3)
  TelegramApiClient::parse_send_response(json)
}

///|
pub impl Adapter for TelegramAdapter with fn update_message(
  self,
  chat_id : String,
  message_id : String,
  new_text : String,
) -> Result[Unit, ChannelError] {
  if !self.is_running {
    return Err(ChannelError("Adapter not running"))
  }
  let _ = chat_id
  let _ = message_id
  let _ = new_text
  Err(ChannelError("Telegram update_message is not implemented yet"))
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

// ── Event Parsing ────────────────────────────────────────────────────────────

///|
/// Extract the update_id from a Telegram Update JSON object.
pub fn extract_update_id(update : Map[String, Json]) -> Int {
  match update.get("update_id") {
    Some(Number(n, ..)) => n.to_int()
    _ => 0
  }
}

///|
/// Detect chat type from Telegram message chat object.
/// "private" → Direct, everything else → Group.
pub fn detect_chat_type(message : Map[String, Json]) -> ChatType {
  match message.get("chat") {
    Some(Object(chat)) =>
      match chat.get("type") {
        Some(String(t)) =>
          if t == "private" {
            ChatType::Direct
          } else {
            ChatType::Group
          }
        _ => ChatType::Direct
      }
    _ => ChatType::Direct
  }
}

///|
/// Extract file attachments from a Telegram message.
/// Handles photo (largest size) and document attachments.
pub fn extract_telegram_attachments(
  message : Map[String, Json],
) -> Array[Attachment] {
  let attachments : Array[Attachment] = []
  // Photo: array of PhotoSize, pick the largest (last element)
  match message.get("photo") {
    Some(Array(sizes)) =>
      if sizes.length() > 0 {
        // Last element is the largest photo size
        let largest = sizes[sizes.length() - 1]
        match largest {
          Object(photo) => {
            let file_id = match photo.get("file_id") {
              Some(String(s)) => s
              _ => ""
            }
            let width = match photo.get("width") {
              Some(Number(n, ..)) => n.to_int()
              _ => 0
            }
            let height = match photo.get("height") {
              Some(Number(n, ..)) => n.to_int()
              _ => 0
            }
            let file_size = match photo.get("file_size") {
              Some(Number(n, ..)) => Some(n.to_int())
              _ => None
            }
            if !file_id.is_empty() {
              attachments.push({
                attachment_type: AttachmentType::Image,
                url: file_id, // file_id; needs getFile to get actual download URL
                filename: Some("photo_\{width}x\{height}.jpg"),
                size_bytes: file_size,
              })
            }
          }
          _ => ()
        }
      }
    _ => ()
  }
  // Document attachment
  match message.get("document") {
    Some(Object(doc)) => {
      let file_id = match doc.get("file_id") {
        Some(String(s)) => s
        _ => ""
      }
      let file_name = match doc.get("file_name") {
        Some(String(s)) => Some(s)
        _ => None
      }
      let file_size = match doc.get("file_size") {
        Some(Number(n, ..)) => Some(n.to_int())
        _ => None
      }
      if !file_id.is_empty() {
        attachments.push({
          attachment_type: AttachmentType::File,
          url: file_id, // file_id; needs getFile to get actual download URL
          filename: file_name,
          size_bytes: file_size,
        })
      }
    }
    _ => ()
  }
  // Audio attachment
  match message.get("audio") {
    Some(Object(audio)) => {
      let file_id = match audio.get("file_id") {
        Some(String(s)) => s
        _ => ""
      }
      let file_name = match audio.get("file_name") {
        Some(String(s)) => Some(s)
        _ => None
      }
      let file_size = match audio.get("file_size") {
        Some(Number(n, ..)) => Some(n.to_int())
        _ => None
      }
      if !file_id.is_empty() {
        attachments.push({
          attachment_type: AttachmentType::Audio,
          url: file_id,
          filename: file_name,
          size_bytes: file_size,
        })
      }
    }
    _ => ()
  }
  // Video attachment
  match message.get("video") {
    Some(Object(video)) => {
      let file_id = match video.get("file_id") {
        Some(String(s)) => s
        _ => ""
      }
      let file_name = match video.get("file_name") {
        Some(String(s)) => Some(s)
        _ => None
      }
      let file_size = match video.get("file_size") {
        Some(Number(n, ..)) => Some(n.to_int())
        _ => None
      }
      if !file_id.is_empty() {
        attachments.push({
          attachment_type: AttachmentType::Video,
          url: file_id,
          filename: file_name,
          size_bytes: file_size,
        })
      }
    }
    _ => ()
  }
  attachments
}

///|
/// Parse Telegram Update JSON to ChannelEvent.
/// Handles text messages, photos, documents, reply detection, and chat type.
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
    _ =>
      // If no text, check for caption (photo/document messages)
      match message.get("caption") {
        Some(String(s)) => s
        _ => ""
      }
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
  // Extract timestamp (Telegram uses Unix seconds, convert to milliseconds)
  let timestamp = match message.get("date") {
    Some(Number(n, ..)) => n.to_int64() * 1000L
    _ => 0L
  }
  // Detect chat type from chat.type field
  let chat_type = detect_chat_type(message)
  // Extract attachments (photo, document, audio, video)
  let attachments = extract_telegram_attachments(message)
  // Preserve raw JSON payload
  Ok({
    event_type: EventType::Message,
    platform: Platform::Telegram,
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

// ── Request Payload Builders ─────────────────────────────────────────────────

///|
/// Build the full sendMessage request payload as JSON.
pub fn build_telegram_send_request(
  chat_id : String,
  text : String,
  reply_to : String?,
  parse_mode : String?,
) -> Json {
  let msg : Map[String, Json] = Map([])
  msg.set("chat_id", chat_id.to_json())
  msg.set("text", text.to_json())
  match parse_mode {
    Some(mode) => msg.set("parse_mode", mode.to_json())
    None => ()
  }
  match reply_to {
    Some(id) => msg.set("reply_to_message_id", id.to_json())
    None => ()
  }
  Json::object(msg)
}

///|
/// Build the editMessageText request payload as JSON.
pub fn build_telegram_edit_request(
  chat_id : String,
  message_id : String,
  text : String,
) -> Json {
  let msg : Map[String, Json] = Map([])
  msg.set("chat_id", chat_id.to_json())
  msg.set("message_id", message_id.to_json())
  msg.set("text", text.to_json())
  msg.set("parse_mode", "Markdown".to_json())
  Json::object(msg)
}

///|
/// Build Telegram sendMessage payload (legacy compatibility wrapper).
pub fn build_telegram_message(
  chat_id : String,
  text : String,
  reply_to : String?,
) -> Json {
  build_telegram_send_request(chat_id, text, reply_to, None)
}

///|
/// Build the getFile request payload as JSON.
pub fn build_telegram_get_file_request(file_id : String) -> Json {
  let payload : Map[String, Json] = Map([])
  payload.set("file_id", file_id.to_json())
  Json::object(payload)
}

///|
/// Build the deleteMessage request payload as JSON.
pub fn build_telegram_delete_request(
  chat_id : String,
  message_id : String,
) -> Json {
  let payload : Map[String, Json] = Map([])
  payload.set("chat_id", chat_id.to_json())
  payload.set("message_id", message_id.to_json())
  Json::object(payload)
}

// ── Message Splitting ────────────────────────────────────────────────────────

///|
/// Find the last occurrence of `needle` in `haystack`.
/// Returns the starting index of the last occurrence, or None if not found.
pub fn find_last_str(haystack : StringView, needle : String) -> Int? {
  let mut result : Int? = None
  let needle_len = needle.length()
  if needle_len == 0 || needle_len > haystack.length() {
    return None
  }
  let mut i = haystack.length() - needle_len
  while i >= 0 {
    if haystack[i:i + needle_len] == needle {
      result = Some(i)
      break
    }
    if i == 0 {
      break
    }
    i = i - 1
  }
  result
}

///|
/// Split a message into chunks respecting Telegram's 4096 char limit.
/// Splits at paragraph, line, or space boundaries to avoid breaking words.
pub fn split_telegram_message(text : String) -> Array[String] {
  let max_len = TELEGRAM_MAX_MESSAGE_LENGTH
  if text.length() <= max_len {
    return [text]
  }
  let chunks : Array[String] = []
  let mut remaining = text
  while remaining.length() > max_len {
    // Try to find a good split point within the max length
    let mut split_pos = max_len
    // Strategy 1: Find last double-newline (paragraph boundary)
    let para_break = find_last_str(remaining[:max_len], "\n\n")
    // Strategy 2: Find last single newline (line boundary)
    let line_break = find_last_str(remaining[:max_len], "\n")
    // Strategy 3: Find last space (word boundary)
    let space_break = find_last_str(remaining[:max_len], " ")
    // Pick the best split point (prefer paragraph > line > space > hard cut)
    split_pos = match para_break {
      Some(pos) if pos > max_len / 2 => pos + 2 // skip the \n\n
      _ =>
        match line_break {
          Some(pos) if pos > max_len / 2 => pos + 1 // skip the \n
          _ =>
            match space_break {
              Some(pos) if pos > max_len / 2 => pos + 1 // skip the space
              _ => max_len // hard cut at max length
            }
        }
    }
    let chunk = remaining[:split_pos].to_owned()
    chunks.push(chunk)
    remaining = remaining[split_pos:].to_owned()
  }
  if remaining.length() > 0 {
    chunks.push(remaining)
  }
  chunks
}

// ── Utility Functions ────────────────────────────────────────────────────────

///|
/// Build the file download URL from a file_path returned by getFile.
/// Format: `{base_url}/file/bot{token}/{file_path}`
pub fn build_telegram_file_url(
  bot_token : String,
  file_path : String,
) -> String {
  TELEGRAM_API_BASE + "/file/bot" + bot_token + "/" + file_path
}

///|
/// Extract file_path from a getFile API response.
pub fn parse_get_file_response(json : Json) -> Result[String, ChannelError] {
  match json {
    Object(obj) => {
      match obj.get("ok") {
        Some(True) => ()
        _ => {
          let desc = match obj.get("description") {
            Some(String(s)) => s
            _ => "getFile API returned ok=false"
          }
          return Err(ChannelError(desc))
        }
      }
      match obj.get("result") {
        Some(Object(result)) =>
          match result.get("file_path") {
            Some(String(path)) => Ok(path)
            _ => Err(ChannelError("Missing file_path in getFile response"))
          }
        _ => Err(ChannelError("Missing result in getFile response"))
      }
    }
    _ => Err(ChannelError("Invalid getFile response format"))
  }
}

///|
/// Detect if a message text mentions the bot (for group chat @bot filtering).
/// Returns true if text starts with "/" (command) or contains @bot_username.
pub fn is_bot_mention(text : String, bot_username : String?) -> Bool {
  // Commands always target the bot
  if text.length() > 0 && text[0:1] == "/" {
    return true
  }
  // Check for @bot_username mention
  match bot_username {
    Some(username) => text.contains("@" + username)
    None => false
  }
}
