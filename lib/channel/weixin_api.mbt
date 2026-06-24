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
  { token, uin, base_url: WEIXIN_API_BASE, cdn_base: WEIXIN_CDN_BASE }
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
  let payload : Map[String, Json] = {}
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
  let text_item : Map[String, Json] = {}
  text_item.set("text", text.to_json())
  let payload : Map[String, Json] = {}
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
  let payload : Map[String, Json] = {}
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
  let payload : Map[String, Json] = {}
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
    if first == "\xFF" || first == "\x89" {
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
/// key = hex_decode(aes_key_str), iv = first 16 bytes of key.
///
/// NOTE: Actual AES-128-ECB encrypt/decrypt is not implemented here because
/// MoonBit stdlib does not include AES primitives. Use an external crypto
/// library (e.g., moonbitlang/x/crypto) for the actual cipher operations.
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
/// Placeholder for AES-128-ECB encryption of media data.
///
/// TODO: Implement using moonbitlang/x/crypto or FFI to OpenSSL.
/// Input: plaintext bytes (as String), key (16 bytes hex).
/// Output: ciphertext bytes (as String).
pub fn weixin_aes_encrypt(
  _plaintext : String,
  _key_hex : String,
) -> Result[String, ChannelError] {
  // TODO: Implement AES-128-ECB encryption
  // let key = hex_decode(key_hex)
  // let cipher = AES128ECB.new(key)
  // Ok(cipher.encrypt(plaintext))
  Err(
    ChannelError(
      "AES encryption not yet implemented: requires moonbitlang/x/crypto",
    ),
  )
}

///|
/// Placeholder for AES-128-ECB decryption of media data.
///
/// TODO: Implement using moonbitlang/x/crypto or FFI to OpenSSL.
/// Input: ciphertext bytes (as String), key (16 bytes hex).
/// Output: plaintext bytes (as String).
pub fn weixin_aes_decrypt(
  _ciphertext : String,
  _key_hex : String,
) -> Result[String, ChannelError] {
  // TODO: Implement AES-128-ECB decryption
  // let key = hex_decode(key_hex)
  // let cipher = AES128ECB.new(key)
  // Ok(cipher.decrypt(ciphertext))
  Err(
    ChannelError(
      "AES decryption not yet implemented: requires moonbitlang/x/crypto",
    ),
  )
}
