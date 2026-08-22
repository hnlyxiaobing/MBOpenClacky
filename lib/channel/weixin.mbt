///| 微信 iLink Bot (Weixin) adapter implementation.
///
/// Handles communication with Weixin via iLink Bot API:
/// - Long-polling for incoming messages (get_updates)
/// - Text message sending with throttling and queue
/// - CDN media upload/download
/// - Markdown sanitization (Weixin does not support Markdown)

// ---------------------------------------------------------------------------
// Send queue structures
// ---------------------------------------------------------------------------

///|
/// Pending message in the send queue.
pub(all) struct WeixinPendingMsg {
  chat_id : String
  text : String
  context_token : String
  retry_count : Int
}

///|
/// Weixin message send queue with throttling and retry.
pub(all) struct WeixinSendQueue {
  mut pending_messages : Array[WeixinPendingMsg]
  buffer_threshold : Int // 400 chars — flush when accumulated text exceeds
  flush_interval_ms : Int // 800ms
  min_send_interval_ms : Int // 1000ms between sends
  max_message_length : Int // 2000 chars per message
}

///|
/// Create a new WeixinSendQueue with default settings.
pub fn WeixinSendQueue::new() -> WeixinSendQueue {
  {
    pending_messages: [],
    buffer_threshold: 400,
    flush_interval_ms: 800,
    min_send_interval_ms: 1000,
    max_message_length: 2000,
  }
}

///| Enqueue a message. If accumulated text exceeds buffer_threshold, the

///|
/// queue is flagged for flush on next check.
pub fn WeixinSendQueue::enqueue(
  self : WeixinSendQueue,
  msg : WeixinPendingMsg,
) -> Unit {
  self.pending_messages.push(msg)
}

///|
/// Check whether the queue should be flushed (has pending messages).
pub fn WeixinSendQueue::should_flush(self : WeixinSendQueue) -> Bool {
  self.pending_messages.length() > 0
}

///|
/// Dequeue the next pending message, or None if empty.
pub fn WeixinSendQueue::dequeue(self : WeixinSendQueue) -> WeixinPendingMsg? {
  if self.pending_messages.length() == 0 {
    None
  } else {
    let msg = self.pending_messages[0]
    // Remove the first element by rebuilding the array
    let rest : Array[WeixinPendingMsg] = []
    let mut i = 1
    while i < self.pending_messages.length() {
      rest.push(self.pending_messages[i])
      i = i + 1
    }
    self.pending_messages = rest
    Some(msg)
  }
}

///|
/// Calculate exponential backoff delay for a given retry count.
///
/// Delays: [1000, 2000, 4000] ms, capped at 4000ms.
pub fn WeixinSendQueue::calculate_retry_delay(
  _self : WeixinSendQueue,
  retry_count : Int,
) -> Int {
  if retry_count <= 0 {
    1000
  } else if retry_count == 1 {
    2000
  } else {
    4000
  }
}

///|
/// Get the number of pending messages in the queue.
pub fn WeixinSendQueue::pending_count(self : WeixinSendQueue) -> Int {
  self.pending_messages.length()
}

// ---------------------------------------------------------------------------
// WeixinAdapter
// ---------------------------------------------------------------------------

///|
/// WeixinAdapter handles communication with Weixin iLink Bot API.
pub(all) struct WeixinAdapter {
  app_id : String
  app_secret : String
  token : String
  encoding_aes_key : String?
  mut is_running : Bool
  mut message_callback : ((ChannelEvent) -> Unit)?
  api_client : WeixinApiClient?
  send_queue : WeixinSendQueue?
  mut context_token : String?
  mut updates_buf : String?
  mut last_send_time : Int
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
  // Build API client if uin is available
  let uin = config.settings.get("uin")
  let api_client = match uin {
    Some(u) => Some(WeixinApiClient::new(token, u))
    None => None
  }
  let send_queue = WeixinSendQueue::new()
  Ok({
    app_id,
    app_secret,
    token,
    encoding_aes_key,
    is_running: false,
    message_callback: None,
    api_client,
    send_queue: Some(send_queue),
    context_token: None,
    updates_buf: None,
    last_send_time: 0,
  })
}

///|
pub extend WeixinAdapter with Adapter::{
  platform_id,
  start,
  stop,
  send_text,
  update_message,
  supports_message_updates,
  validate_config,
}

///|
pub impl Adapter for WeixinAdapter with fn platform_id(_self) -> Platform {
  Platform::Weixin
}

///|
pub impl Adapter for WeixinAdapter with fn supports_message_updates(_self) -> Bool {
  false // Weixin does not support message editing
}

///|
pub impl Adapter for WeixinAdapter with fn start(
  self,
  handler : (ChannelEvent) -> Unit,
) -> Result[Unit, ChannelError] {
  self.message_callback = Some(handler)
  self.is_running = true
  // TODO: Spawn long-polling loop via async runtime:
  //   loop {
  //     let req = api_client.build_get_updates_request(self.updates_buf)
  //     let resp = await @http.post(url, headers, req.to_string())
  //     let (messages, next_buf) = api_client.parse_get_updates_response(resp)
  //     self.updates_buf = next_buf
  //     for msg in messages { handler(parse_event(msg)?) }
  //   }
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
/// Send a text message via Weixin iLink Bot API.
///
/// Weixin send is not yet implemented; refuse to send with an honest error
/// so callers cannot mistake a fabricated ack for delivery. The send queue
/// and request builder are kept for the future Weixin implementation
/// (backlog) to reuse.
pub impl Adapter for WeixinAdapter with fn send_text(
  self,
  chat_id : String,
  text : String,
  _reply_to : String?,
) -> Result[SendResult, ChannelError] {
  if !self.is_running {
    return Err(ChannelError("Adapter not running"))
  }
  let _ = chat_id
  let _ = text
  Err(ChannelError("Weixin send_text is not implemented yet"))
}

///|
pub impl Adapter for WeixinAdapter with fn update_message(
  _self,
  _chat_id : String,
  _message_id : String,
  _new_text : String,
) -> Result[Unit, ChannelError] {
  Err(ChannelError("Weixin does not support message updates"))
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

// ---------------------------------------------------------------------------
// Event parsing (iLink get_updates format)
// ---------------------------------------------------------------------------

///|
/// Parse an incoming iLink message JSON to ChannelEvent.
///
/// Supports item_list message types:
/// - TEXT (1): extract text_item.text
/// - IMAGE (2): extract image_item as Attachment
/// - VOICE (3): extract voice_text as text
/// - FILE (4): extract file_item as Attachment
/// - VIDEO (5): extract video_item as Attachment
pub fn WeixinAdapter::parse_event(
  json : Json,
) -> Result[ChannelEvent, ChannelError] {
  let msg = match json {
    Object(obj) => obj
    _ => return Err(ChannelError("Invalid JSON payload"))
  }
  // Extract sender info
  let sender_id = match msg.get("from_user_name") {
    Some(String(s)) => s
    _ =>
      match msg.get("FromUserName") {
        Some(String(s)) => s
        _ => ""
      }
  }
  let sender_name = match msg.get("from_user_nick") {
    Some(String(s)) => s
    _ => sender_id
  }
  // Extract chat_id (conversation ID)
  let chat_id = match msg.get("to_user_name") {
    Some(String(s)) => s
    _ =>
      match msg.get("ToUserName") {
        Some(String(s)) => s
        _ => ""
      }
  }
  // Extract message_id
  let message_id = match msg.get("msg_id") {
    Some(String(s)) => s
    _ =>
      match msg.get("MsgId") {
        Some(String(s)) => s
        _ => ""
      }
  }
  // Parse item_list for content
  let (text, attachments) = match msg.get("item_list") {
    Some(Array(items)) => parse_weixin_items(items)
    _ => {
      // Fallback to legacy Content field
      let fallback_text = match msg.get("Content") {
        Some(String(s)) => s
        _ => ""
      }
      (fallback_text, [])
    }
  }
  // Extract and update context_token
  let _ctx = extract_weixin_context_token(msg)
  // Determine chat_type (iLink currently only supports Direct)
  let chat_type = ChatType::Direct
  // Determine event_type
  let event_type = match msg.get("msg_type") {
    Some(Number(n, ..)) =>
      if n == 0.0 {
        EventType::Join
      } else {
        EventType::Message
      }
    Some(String(s)) =>
      if s == "event" {
        EventType::Join
      } else {
        EventType::Message
      }
    _ => EventType::Message
  }
  // Timestamp
  let timestamp = match msg.get("create_time") {
    Some(Number(n, ..)) => n.to_int()
    _ => 0
  }
  Ok({
    event_type,
    platform: Platform::Weixin,
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

// ---------------------------------------------------------------------------
// Item list parsing helpers
// ---------------------------------------------------------------------------

///|
/// Parse an iLink item_list array into (text, attachments).
///
/// Each item has a `type` field:
/// - 1 = TEXT: extract text_item.text
/// - 2 = IMAGE: extract image_item as Attachment
/// - 3 = VOICE: extract voice_text as text
/// - 4 = FILE: extract file_item as Attachment
/// - 5 = VIDEO: extract video_item as Attachment
pub fn parse_weixin_items(
  item_list : Array[Json],
) -> (String, Array[Attachment]) {
  let text_parts : Array[String] = []
  let attachments : Array[Attachment] = []
  for item_json in item_list {
    let item = match item_json {
      Object(o) => o
      _ => continue
    }
    let item_type = match item.get("type") {
      Some(Number(n, ..)) => n.to_int()
      _ => 0
    }
    match item_type {
      1 => {
        // TEXT
        let t = parse_weixin_text_item(item)
        if !t.is_empty() {
          text_parts.push(t)
        }
      }
      2 =>
        // IMAGE
        match parse_weixin_image_item(item) {
          Some(att) => attachments.push(att)
          None => ()
        }
      3 => {
        // VOICE (voice-to-text)
        let vt = parse_weixin_voice_item(item)
        if !vt.is_empty() {
          text_parts.push(vt)
        }
      }
      4 =>
        // FILE
        match parse_weixin_file_item(item) {
          Some(att) => attachments.push(att)
          None => ()
        }
      5 =>
        // VIDEO
        match parse_weixin_video_item(item) {
          Some(att) => attachments.push(att)
          None => ()
        }
      _ => ()
    }
  }
  // Join text parts with newline
  let mut combined = ""
  let mut first = true
  for part in text_parts {
    if first {
      combined = part
      first = false
    } else {
      combined = combined + "\n" + part
    }
  }
  (combined, attachments)
}

///|
/// Parse a TEXT item (type=1) from item_list.
pub fn parse_weixin_text_item(item : Map[String, Json]) -> String {
  match item.get("text_item") {
    Some(Object(ti)) =>
      match ti.get("text") {
        Some(String(s)) => s
        _ => ""
      }
    _ => ""
  }
}

///|
/// Parse an IMAGE item (type=2) from item_list into an Attachment.
pub fn parse_weixin_image_item(item : Map[String, Json]) -> Attachment? {
  match item.get("image_item") {
    Some(Object(ii)) => {
      let url = match ii.get("cdn_file_id") {
        Some(String(s)) => WEIXIN_CDN_BASE + "/download/" + s
        _ =>
          match ii.get("url") {
            Some(String(s)) => s
            _ => return None
          }
      }
      let filename = match ii.get("filename") {
        Some(String(s)) => Some(s)
        _ => None
      }
      let size_bytes = match ii.get("file_size") {
        Some(Number(n, ..)) => Some(n.to_int())
        _ => None
      }
      Some({ attachment_type: AttachmentType::Image, url, filename, size_bytes })
    }
    _ => None
  }
}

///|
/// Parse a FILE item (type=4) from item_list into an Attachment.
pub fn parse_weixin_file_item(item : Map[String, Json]) -> Attachment? {
  match item.get("file_item") {
    Some(Object(fi)) => {
      let url = match fi.get("cdn_file_id") {
        Some(String(s)) => WEIXIN_CDN_BASE + "/download/" + s
        _ =>
          match fi.get("url") {
            Some(String(s)) => s
            _ => return None
          }
      }
      let filename = match fi.get("filename") {
        Some(String(s)) => Some(s)
        _ => None
      }
      let size_bytes = match fi.get("file_size") {
        Some(Number(n, ..)) => Some(n.to_int())
        _ => None
      }
      Some({ attachment_type: AttachmentType::File, url, filename, size_bytes })
    }
    _ => None
  }
}

///|
/// Parse a VOICE item (type=3) from item_list, returning voice-to-text.
pub fn parse_weixin_voice_item(item : Map[String, Json]) -> String {
  match item.get("voice_item") {
    Some(Object(vi)) =>
      match vi.get("voice_text") {
        Some(String(s)) => s
        _ => ""
      }
    _ => ""
  }
}

///|
/// Parse a VIDEO item (type=5) from item_list into an Attachment.
pub fn parse_weixin_video_item(item : Map[String, Json]) -> Attachment? {
  match item.get("video_item") {
    Some(Object(vi)) => {
      let url = match vi.get("cdn_file_id") {
        Some(String(s)) => WEIXIN_CDN_BASE + "/download/" + s
        _ =>
          match vi.get("url") {
            Some(String(s)) => s
            _ => return None
          }
      }
      let filename = match vi.get("filename") {
        Some(String(s)) => Some(s)
        _ => None
      }
      let size_bytes = match vi.get("file_size") {
        Some(Number(n, ..)) => Some(n.to_int())
        _ => None
      }
      Some({ attachment_type: AttachmentType::Video, url, filename, size_bytes })
    }
    _ => None
  }
}

///|
/// Extract context_token from a message object.
///
/// The context_token is used for replying within a conversation session.
pub fn extract_weixin_context_token(msg : Map[String, Json]) -> String? {
  match msg.get("context_token") {
    Some(String(s)) => if s.is_empty() { None } else { Some(s) }
    _ => None
  }
}

// ---------------------------------------------------------------------------
// Text processing helpers
// ---------------------------------------------------------------------------

///|
/// Sanitize text for Weixin by stripping Markdown syntax.
///
/// Transformations:
/// - **bold** → bold
/// - *italic* → italic
/// - `code` → code
/// - ```block``` → block
/// - [link](url) → link
pub fn sanitize_for_weixin(text : String) -> String {
  let mut result = text
  // Strip code blocks first (``` ... ```)
  result = strip_markdown_code_blocks(result)
  // Strip inline code (`...`)
  result = strip_markdown_inline_code(result)
  // Strip bold (**...**)
  result = strip_markdown_bold(result)
  // Strip italic (*...*)
  result = strip_markdown_italic(result)
  // Strip links [text](url) → text
  result = strip_markdown_links(result)
  result
}

///|
/// Strip Markdown code blocks (``` ... ```) keeping inner content.
fn strip_markdown_code_blocks(text : String) -> String {
  let mut result : String = ""
  let mut i = 0
  let len = text.length()
  while i < len {
    if i + 2 < len &&
      text[i:i + 1] == "`" &&
      text[i + 1:i + 2] == "`" &&
      text[i + 2:i + 3] == "`" {
      // Skip opening ```
      i = i + 3
      // Skip optional language tag until newline
      while i < len && text[i:i + 1] != "\n" {
        i = i + 1
      }
      if i < len {
        i = i + 1 // skip newline
      }
      // Copy until closing ```
      while i + 2 < len {
        if text[i:i + 1] == "`" &&
          text[i + 1:i + 2] == "`" &&
          text[i + 2:i + 3] == "`" {
          i = i + 3
          break
        }
        result = result + text[i:i + 1].to_owned()
        i = i + 1
      }
    } else {
      result = result + text[i:i + 1].to_owned()
      i = i + 1
    }
  }
  result
}

///|
/// Strip inline code backticks (`...`) keeping inner content.
fn strip_markdown_inline_code(text : String) -> String {
  let mut result : String = ""
  let mut i = 0
  let len = text.length()
  while i < len {
    if text[i:i + 1] == "`" {
      i = i + 1
      while i < len && text[i:i + 1] != "`" {
        result = result + text[i:i + 1].to_owned()
        i = i + 1
      }
      if i < len {
        i = i + 1 // skip closing `
      }
    } else {
      result = result + text[i:i + 1].to_owned()
      i = i + 1
    }
  }
  result
}

///|
/// Strip Markdown bold (**...**) keeping inner content.
fn strip_markdown_bold(text : String) -> String {
  let mut result : String = ""
  let mut i = 0
  let len = text.length()
  while i < len {
    if i + 1 < len && text[i:i + 1] == "*" && text[i + 1:i + 2] == "*" {
      i = i + 2
      while i + 1 < len {
        if text[i:i + 1] == "*" && text[i + 1:i + 2] == "*" {
          i = i + 2
          break
        }
        result = result + text[i:i + 1].to_owned()
        i = i + 1
      }
    } else {
      result = result + text[i:i + 1].to_owned()
      i = i + 1
    }
  }
  result
}

///|
/// Strip Markdown italic (*...*) keeping inner content.
fn strip_markdown_italic(text : String) -> String {
  let mut result : String = ""
  let mut i = 0
  let len = text.length()
  while i < len {
    if text[i:i + 1] == "*" {
      i = i + 1
      while i < len && text[i:i + 1] != "*" {
        result = result + text[i:i + 1].to_owned()
        i = i + 1
      }
      if i < len {
        i = i + 1 // skip closing *
      }
    } else {
      result = result + text[i:i + 1].to_owned()
      i = i + 1
    }
  }
  result
}

///|
/// Strip Markdown links [text](url) → text.
fn strip_markdown_links(text : String) -> String {
  let mut result : String = ""
  let mut i = 0
  let len = text.length()
  while i < len {
    if text[i:i + 1] == "[" {
      i = i + 1
      // Collect link text
      let mut link_text : String = ""
      while i < len && text[i:i + 1] != "]" {
        link_text = link_text + text[i:i + 1].to_owned()
        i = i + 1
      }
      if i < len {
        i = i + 1 // skip ]
      }
      // Check for (url)
      if i < len && text[i:i + 1] == "(" {
        i = i + 1
        while i < len && text[i:i + 1] != ")" {
          i = i + 1
        }
        if i < len {
          i = i + 1 // skip )
        }
        result = result + link_text
      } else {
        result = result + "[" + link_text
      }
    } else {
      result = result + text[i:i + 1].to_owned()
      i = i + 1
    }
  }
  result
}

///|
/// Split a long message into chunks of max_length characters.
///
/// Splits at newline boundaries when possible.
pub fn split_weixin_message(text : String, max_length : Int) -> Array[String] {
  if text.length() <= max_length {
    [text]
  } else {
    let chunks : Array[String] = []
    let mut remaining = text
    while remaining.length() > max_length {
      // Try to find a newline to split at
      let mut split_at = max_length
      let mut search_pos = max_length
      while search_pos > 0 {
        if remaining[search_pos:search_pos + 1] == "\n" {
          split_at = search_pos
          break
        }
        search_pos = search_pos - 1
      }
      if split_at == 0 {
        split_at = max_length
      }
      chunks.push(remaining[0:split_at].to_owned())
      remaining = remaining[split_at:].to_owned()
      // Skip leading newline
      if remaining.length() > 0 && remaining[0:1] == "\n" {
        remaining = remaining[1:].to_owned()
      }
    }
    if !remaining.is_empty() {
      chunks.push(remaining)
    }
    chunks
  }
}

///|
/// Check if the iLink API response indicates rate limiting.
///
/// ret == -2 means the bot is sending too fast.
pub fn is_rate_limited(ret_code : Int) -> Bool {
  ret_code == -2
}

// ---------------------------------------------------------------------------
// Legacy helper (backward compatibility)
// ---------------------------------------------------------------------------

///|
/// Build a legacy Weixin reply message payload (XML-as-JSON format).
pub fn build_weixin_message(
  to_user : String,
  from_user : String,
  text : String,
) -> Json {
  let msg : Map[String, Json] = Map([])
  msg.set("ToUserName", to_user.to_json())
  msg.set("FromUserName", from_user.to_json())
  msg.set("MsgType", "text".to_json())
  msg.set("Content", text.to_json())
  Json::object(msg)
}
