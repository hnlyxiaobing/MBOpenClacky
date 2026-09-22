///| Weixin iLink API client.
///
/// Provides methods for iLink bot API operations:
/// long-polling get_updates, send_text, send_typing,
/// media upload/download with AES encryption support.
/// Since MoonBit Adapter trait methods are synchronous, HTTP calls
/// are prepared here and dispatched via the async runtime separately.

///|
/// Weixin iLink API client.
pub(all) struct WeixinApiClient {
  token : String // Bot token from QR scan
  uin : String // X-WECHAT-UIN header value
  base_url : String // WEIXIN_API_BASE
  cdn_base : String // WEIXIN_CDN_BASE
}

///|
/// Create a new WeixinApiClient with default base URLs.
pub fn WeixinApiClient::new(token : String, uin : String) -> WeixinApiClient {
  WeixinApiClient::with_base_url(token, uin, WEIXIN_API_BASE)
}

///|
/// Create a WeixinApiClient with a custom API base (for testing). The CDN base
/// stays at the production value: it is only used to build download URLs.
pub fn WeixinApiClient::with_base_url(
  token : String,
  uin : String,
  base_url : String,
) -> WeixinApiClient {
  { token, uin, base_url, cdn_base: WEIXIN_CDN_BASE, }
}

///|
/// Build authentication headers for iLink Bot API.
///
/// Includes:
/// - Authorization: Bearer {token}
/// - AuthorizationType: ilink_bot_token
/// - X-WECHAT-UIN: {uin}
/// - Content-Type: application/json
pub fn WeixinApiClient::auth_headers(self : WeixinApiClient) -> HttpHeaders {
  HttpHeaders::new()
  .bearer(self.token)
  .set("AuthorizationType", "ilink_bot_token")
  .set("X-WECHAT-UIN", self.uin)
  .content_type("application/json")
}

// ---------------------------------------------------------------------------
// Long-polling: get_updates
// ---------------------------------------------------------------------------

///|
/// Build the full URL for get_updates endpoint.
pub fn WeixinApiClient::get_updates_url(
  self : WeixinApiClient,
  _buf : String?,
) -> String {
  let base = if self.base_url.has_suffix("/") {
    self.base_url[:self.base_url.length() - 1].to_owned()
  } else {
    self.base_url
  }
  base + "/cgi-bin/mmfinderassistantbin/getupdates"
}

///|
/// Build the JSON request body for get_updates.
///
/// Fields:
/// - timeout: 40 (long-poll seconds)
/// - buf: cursor from previous response (empty on first call)
pub fn WeixinApiClient::build_get_updates_request(
  self : WeixinApiClient,
  buf : String?,
) -> Json {
  let _ = self.token
  let payload : Map[String, Json] = Map([])
  let timeout = 40
  payload.set("timeout", timeout.to_json())
  match buf {
    Some(b) => payload.set("buf", b.to_json())
    None => payload.set("buf", "".to_json())
  }
  Json::object(payload)
}

///|
/// Parse the get_updates response.
///
/// Returns (messages, next_buf) where:
/// - messages: array of message JSON objects from item_list
/// - next_buf: opaque cursor string for next poll (None if absent)
pub fn WeixinApiClient::parse_get_updates_response(
  _self : WeixinApiClient,
  json : Json,
) -> Result[(Array[Json], String?), ChannelError] {
  let obj = match json {
    Object(o) => o
    _ => return Err(ChannelError("get_updates: invalid JSON response"))
  }
  // Check for error in response
  match obj.get("ret") {
    Some(Number(n, ..)) =>
      if n != 0.0 {
        let err_msg = match obj.get("errmsg") {
          Some(String(s)) => s
          _ => "Unknown error"
        }
        return Err(
          ChannelError(
            "get_updates failed (ret=" + n.to_string() + "): " + err_msg,
          ),
        )
      }
    _ => ()
  }
  // Extract messages array
  let messages : Array[Json] = match obj.get("item_list") {
    Some(Array(arr)) => arr
    _ => []
  }
  // Extract next_buf cursor
  let next_buf = match obj.get("buf") {
    Some(String(s)) => if s.is_empty() { None } else { Some(s) }
    _ => None
  }
  Ok((messages, next_buf))
}

// ---------------------------------------------------------------------------
// Send text message
// ---------------------------------------------------------------------------

///|
/// Build the full URL for sendmessage endpoint.
pub fn WeixinApiClient::send_text_url(self : WeixinApiClient) -> String {
  let base = if self.base_url.has_suffix("/") {
    self.base_url[:self.base_url.length() - 1].to_owned()
  } else {
    self.base_url
  }
  base + "/cgi-bin/mmfinderassistantbin/sendmessage"
}

///|
/// Build the JSON request body for sending a text message.
///
/// Fields:
/// - to_user_name: recipient user ID
/// - text_item: { text: "..." }
/// - context_token: session context token
pub fn WeixinApiClient::build_send_text_request(
  self : WeixinApiClient,
  to_user_id : String,
  text : String,
  context_token : String,
) -> Json {
  let _ = self.token
  let text_item : Map[String, Json] = Map([])
  text_item.set("text", text.to_json())
  let payload : Map[String, Json] = Map([])
  payload.set("to_user_name", to_user_id.to_json())
  payload.set("text_item", Json::object(text_item))
  payload.set("context_token", context_token.to_json())
  let msg_type = 1 // TEXT
  payload.set("msg_type", msg_type.to_json())
  Json::object(payload)
}

///|
/// Parse the send message response.
///
/// Returns (message_id, ret_code).
pub fn WeixinApiClient::parse_send_response(
  _self : WeixinApiClient,
  json : Json,
) -> Result[(String, Int), ChannelError] {
  let obj = match json {
    Object(o) => o
    _ => return Err(ChannelError("send_message: invalid JSON response"))
  }
  let ret_code = match obj.get("ret") {
    Some(Number(n, ..)) => n.to_int()
    _ => 0
  }
  let message_id = match obj.get("msg_id") {
    Some(String(s)) => s
    _ => ""
  }
  Ok((message_id, ret_code))
}

///|
/// Cheap credential/liveness probe: one `getupdates` round trip with a 1s
/// long-poll timeout instead of the 40s used by the receive loop.
/// A usable bot token yields ret == 0 (possibly with no messages); any other
/// ret is surfaced as an error so a broken token cannot look healthy.
pub async fn WeixinApiClient::probe_connectivity(
  self : WeixinApiClient,
) -> Result[Unit, ChannelError] {
  let payload : Map[String, Json] = Map([])
  payload.set("timeout", (1).to_json())
  payload.set("buf", "".to_json())
  let json = match
    http_post_json(
      self.get_updates_url(None),
      self.auth_headers().to_array(),
      Json::object(payload).stringify(),
    ) {
    Ok(j) => j
    Err(e) => return Err(e)
  }
  match self.parse_get_updates_response(json) {
    Ok(_) => Ok(())
    Err(e) => Err(e)
  }
}

// ---------------------------------------------------------------------------
// Send typing indicator
// ---------------------------------------------------------------------------

///|
/// Build the full URL for sendtyping endpoint.
pub fn WeixinApiClient::send_typing_url(self : WeixinApiClient) -> String {
  let base = if self.base_url.has_suffix("/") {
    self.base_url[:self.base_url.length() - 1].to_owned()
  } else {
    self.base_url
  }
  base + "/cgi-bin/mmfinderassistantbin/sendtyping"
}

///|
/// Build the JSON request body for typing indicator.
///
/// status: 1 = typing start, 0 = typing stop
pub fn WeixinApiClient::build_typing_request(
  self : WeixinApiClient,
  to_user_id : String,
  status : Int,
) -> Json {
  let _ = self.token
  let payload : Map[String, Json] = Map([])
  payload.set("to_user_name", to_user_id.to_json())
  payload.set("typing_status", status.to_json())
  Json::object(payload)
}

// ---------------------------------------------------------------------------
// Media upload
// ---------------------------------------------------------------------------

///|
/// Build the full URL for getuploadurl endpoint.
pub fn WeixinApiClient::get_upload_url(self : WeixinApiClient) -> String {
  let base = if self.base_url.has_suffix("/") {
    self.base_url[:self.base_url.length() - 1].to_owned()
  } else {
    self.base_url
  }
  base + "/cgi-bin/mmfinderassistantbin/getuploadurl"
}

///|
/// Build the JSON request body for requesting an upload URL.
///
/// media_type: 1=image, 2=file, 3=video
pub fn WeixinApiClient::build_upload_request(
  self : WeixinApiClient,
  media_type : Int,
  file_size : Int,
) -> Json {
  let _ = self.token
  let payload : Map[String, Json] = Map([])
  payload.set("media_type", media_type.to_json())
  payload.set("file_size", file_size.to_json())
  Json::object(payload)
}

// ---------------------------------------------------------------------------
// Media download (CDN)
// ---------------------------------------------------------------------------

///|
/// Build the CDN download URL for a given file ID.
pub fn WeixinApiClient::download_media_url(
  self : WeixinApiClient,
  cdn_file_id : String,
) -> String {
  let cdn = if self.cdn_base.has_suffix("/") {
    self.cdn_base[:self.cdn_base.length() - 1].to_owned()
  } else {
    self.cdn_base
  }
  cdn + "/download/" + cdn_file_id
}

// ---------------------------------------------------------------------------
// AES encryption support (simplified interface)
// ---------------------------------------------------------------------------

///|
/// Weixin AES encryption mode.
pub(all) enum WeixinAesMode {
  OutboundImage // 出站图片
  OutboundOther // 出站非图片
  Inbound // 入站
} derive(Eq, Debug)

///|
pub extend WeixinAesMode with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend WeixinAesMode with Eq::{not_equal, equal}

///|
/// Detect AES mode from data header magic bytes.
///
/// Weixin media may use AES-128-ECB encryption with mode determined
/// by the first bytes of the payload:
/// - Image outbound: magic prefix for image data
/// - Other outbound: non-image attachments
/// - Inbound: received media requiring decryption
pub fn detect_weixin_aes_mode(data_header : String) -> WeixinAesMode {
  if data_header.length() < 4 {
    WeixinAesMode::Inbound
  } else {
    // Check for common image magic bytes (JPEG: 0xFFD8, PNG: 0x8950)
    // In string representation, these appear as specific byte patterns
    let first = data_header[0:1].to_owned()
    if first == "\u00FF" || first == "\u0089" {
      WeixinAesMode::OutboundImage
    } else {
      WeixinAesMode::Inbound
    }
  }
}

///|
/// Build AES key components for Weixin media encryption.
///
/// Returns (key_hex, iv_hex) pair.
/// key = hex_decode(aes_key_str), iv = first 16 bytes of key (ECB ignores it).
pub fn build_weixin_aes_key(aes_key_str : String) -> (String, String) {
  if aes_key_str.length() >= 32 {
    // Key is first 32 hex chars (16 bytes), IV is first 16 bytes of key (same as key for ECB)
    let key_hex = aes_key_str[0:32].to_owned()
    let iv_hex = aes_key_str[0:32].to_owned() // ECB mode: IV is not used, but keep for API compat
    (key_hex, iv_hex)
  } else {
    // Pad or use as-is
    (aes_key_str, "")
  }
}

///|
/// Determine if AES encryption is needed for outbound media.
///
/// Weixin iLink API requires AES-128-ECB encryption for uploaded media.
/// Returns true if the aes_key is non-empty.
pub fn weixin_media_requires_encryption(aes_key : String) -> Bool {
  !aes_key.is_empty()
}

///|
/// Value of a single hex digit, or None when the char is not hex.
fn hex_digit_value(c : Char) -> Int? {
  if c >= '0' && c <= '9' {
    Some(c.to_int() - '0'.to_int())
  } else if c >= 'a' && c <= 'f' {
    Some(c.to_int() - 'a'.to_int() + 10)
  } else if c >= 'A' && c <= 'F' {
    Some(c.to_int() - 'A'.to_int() + 10)
  } else {
    None
  }
}

///|
/// Decode a 32-hex-char key string into the 16 raw bytes AES-128 needs.
pub fn weixin_aes_key_from_hex(key_hex : String) -> Result[Bytes, ChannelError] {
  if key_hex.length() != 32 {
    return Err(
      ChannelError(
        "Weixin AES key must be 32 hex chars (16 bytes), got " +
        key_hex.length().to_string(),
      ),
    )
  }
  let out : Array[Byte] = []
  let mut high = -1
  for c in key_hex {
    let digit = match hex_digit_value(c) {
      Some(v) => v
      None =>
        return Err(
          ChannelError("Invalid hex digit in Weixin AES key: " + c.to_string()),
        )
    }
    if high < 0 {
      high = digit
    } else {
      out.push((high * 16 + digit).to_byte())
      high = -1
    }
  }
  Ok(Bytes::from_array(out))
}

///|
/// Pad data to a 16-byte multiple with PKCS#7 (always appends 1..16 bytes).
pub fn pkcs7_pad(data : Bytes) -> Bytes {
  let pad_len = 16 - data.length() % 16
  let out : Array[Byte] = []
  for b in data {
    out.push(b)
  }
  for _ in 0..<pad_len {
    out.push(pad_len.to_byte())
  }
  Bytes::from_array(out)
}

///|
/// Strip PKCS#7 padding, rejecting inconsistent padding.
pub fn pkcs7_unpad(data : Bytes) -> Result[Bytes, ChannelError] {
  let len = data.length()
  if len == 0 || len % 16 != 0 {
    return Err(ChannelError("Invalid padded length: " + len.to_string()))
  }
  let pad_len = data[len - 1].to_int()
  if pad_len == 0 || pad_len > 16 {
    return Err(
      ChannelError("Invalid PKCS#7 pad length: " + pad_len.to_string()),
    )
  }
  let body_len = len - pad_len
  let mut i = body_len
  while i < len {
    if data[i].to_int() != pad_len {
      return Err(ChannelError("Malformed PKCS#7 padding"))
    }
    i = i + 1
  }
  let out : Array[Byte] = []
  let mut j = 0
  while j < body_len {
    out.push(data[j])
    j = j + 1
  }
  Ok(Bytes::from_array(out))
}

///|
/// AES-128-ECB encrypt of a block-aligned buffer (caller owns padding).
pub fn weixin_aes_ecb_encrypt(
  key : Bytes,
  data : Bytes,
) -> Result[Bytes, ChannelError] {
  let out = @crypto.aes_ecb_encrypt(key, data) catch {
    _ =>
      return Err(
        ChannelError("AES-128-ECB encryption failed (key or data length)"),
      )
  }
  Ok(out)
}

///|
/// AES-128-ECB decrypt of a block-aligned buffer (caller strips padding).
pub fn weixin_aes_ecb_decrypt(
  key : Bytes,
  data : Bytes,
) -> Result[Bytes, ChannelError] {
  let out = @crypto.aes_ecb_decrypt(key, data) catch {
    _ =>
      return Err(
        ChannelError("AES-128-ECB decryption failed (key or data length)"),
      )
  }
  Ok(out)
}

///|
/// AES-128-ECB encrypt with PKCS#7 padding, as used for Weixin media.
pub fn weixin_aes_encrypt(
  plaintext : Bytes,
  key : Bytes,
) -> Result[Bytes, ChannelError] {
  weixin_aes_ecb_encrypt(key, pkcs7_pad(plaintext))
}

///|
/// AES-128-ECB decrypt followed by PKCS#7 unpadding.
pub fn weixin_aes_decrypt(
  ciphertext : Bytes,
  key : Bytes,
) -> Result[Bytes, ChannelError] {
  let raw = match weixin_aes_ecb_decrypt(key, ciphertext) {
    Ok(r) => r
    Err(e) => return Err(e)
  }
  pkcs7_unpad(raw)
}
