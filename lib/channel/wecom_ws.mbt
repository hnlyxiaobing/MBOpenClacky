///| WeCom (企业微信) WebSocket client implementation.
///
/// Implements the WeCom Bot WebSocket protocol:
/// - Connect to wss://openws.work.weixin.qq.com
/// - aibot_subscribe authentication frame
/// - 30s heartbeat / 75s read timeout
/// - aibot_send_msg message sending
/// - Three-step chunked upload (init -> chunks -> finish)
/// - ACK waiting with req_id matching

///|
/// WeCom WebSocket endpoint URL.
pub const WECOM_WS_URL : String = "wss://openws.work.weixin.qq.com"

///|
/// Default heartbeat interval in milliseconds.
pub const WECOM_HEARTBEAT_INTERVAL : Int = 30000

///|
/// Default read timeout in milliseconds (2.5x heartbeat).
pub const WECOM_READ_TIMEOUT : Int = 75000

///|
/// Default ACK wait timeout in milliseconds.
pub const WECOM_ACK_TIMEOUT : Int = 30000

///|
/// Default chunk size for file upload (512KB).
pub const WECOM_DEFAULT_CHUNK_SIZE : Int = 524288

///|
/// WeCom WebSocket frame types.
pub(all) enum WeComFrameType {
  /// aibot_subscribe authentication frame
  Subscribe
  /// aibot_send_msg message sending frame
  SendMsg
  /// Heartbeat ping
  Ping
  /// Heartbeat pong response
  Pong
  /// ACK acknowledgment
  Ack
  /// Incoming data message
  Data
} derive(Eq, Debug)

///|
/// WeCom WebSocket connection state.
pub(all) struct WeComWsState {
  bot_id : String
  secret : String
  mut is_connected : Bool
  mut req_counter : Int
  heartbeat_interval : Int
  read_timeout : Int
}

///|
/// Create a new WeComWsState.
pub fn WeComWsState::new(bot_id : String, secret : String) -> WeComWsState {
  {
    bot_id,
    secret,
    is_connected: false,
    req_counter: 0,
    heartbeat_interval: WECOM_HEARTBEAT_INTERVAL,
    read_timeout: WECOM_READ_TIMEOUT,
  }
}

///|
/// Generate the next request ID for frame matching.
pub fn WeComWsState::next_req_id(self : WeComWsState) -> String {
  self.req_counter = self.req_counter + 1
  self.req_counter.to_string()
}

///|
/// Mark the connection as established.
pub fn WeComWsState::mark_connected(self : WeComWsState) -> Unit {
  self.is_connected = true
  self.req_counter = 0
}

///|
/// Mark the connection as disconnected.
pub fn WeComWsState::mark_disconnected(self : WeComWsState) -> Unit {
  self.is_connected = false
}

///|
/// Reset the request counter.
pub fn WeComWsState::reset_counter(self : WeComWsState) -> Unit {
  self.req_counter = 0
}

// ── Frame Builders ───────────────────────────────────────────────────────────

///|
/// Build the authentication/subscribe frame.
///
/// Format: {"type":"aibot_subscribe","bot_id":"...","secret":"..."}
pub fn build_subscribe_frame(bot_id : String, secret : String) -> Json {
  let frame : Map[String, Json] = {}
  frame.set("type", "aibot_subscribe".to_json())
  frame.set("bot_id", bot_id.to_json())
  frame.set("secret", secret.to_json())
  Json::object(frame)
}

///|
/// Build a message sending frame.
///
/// Format: {"type":"aibot_send_msg","req_id":"...","chat_id":"...","content":"...","msg_type":"..."}
pub fn build_send_msg_frame(
  chat_id : String,
  content : String,
  msg_type : String,
  req_id : String,
) -> Json {
  let frame : Map[String, Json] = {}
  frame.set("type", "aibot_send_msg".to_json())
  frame.set("req_id", req_id.to_json())
  frame.set("chat_id", chat_id.to_json())
  frame.set("content", content.to_json())
  frame.set("msg_type", msg_type.to_json())
  Json::object(frame)
}

///|
/// Build a heartbeat ping frame.
///
/// Format: {"type":"ping"}
pub fn build_ping_frame() -> Json {
  let frame : Map[String, Json] = {}
  frame.set("type", "ping".to_json())
  Json::object(frame)
}

///|
/// Build an ACK response frame.
///
/// Format: {"type":"ack","req_id":"..."}
pub fn build_ack_frame(req_id : String) -> Json {
  let frame : Map[String, Json] = {}
  frame.set("type", "ack".to_json())
  frame.set("req_id", req_id.to_json())
  Json::object(frame)
}

// ── Frame Parsers ────────────────────────────────────────────────────────────

///|
/// Parse an incoming WebSocket frame.
///
/// Returns (frame_type, frame_data) on success.
pub fn parse_incoming_frame(
  json : Json,
) -> Result[(WeComFrameType, Json), ChannelError] {
  match json {
    Object(obj) => {
      let frame_type = match obj.get("type") {
        Some(String(s)) => s
        _ => return Err(ChannelError("Missing 'type' in WebSocket frame"))
      }
      let wft = match frame_type {
        "aibot_subscribe" => WeComFrameType::Subscribe
        "aibot_send_msg" => WeComFrameType::SendMsg
        "ping" => WeComFrameType::Ping
        "pong" => WeComFrameType::Pong
        "ack" => WeComFrameType::Ack
        "data" => WeComFrameType::Data
        _ => return Err(ChannelError("Unknown frame type: " + frame_type))
      }
      Ok((wft, json))
    }
    _ => Err(ChannelError("Invalid WebSocket frame: expected JSON object"))
  }
}

///|
/// Check if the frame contains an authentication error.
///
/// Auth errors are fatal and should NOT be retried.
pub fn is_auth_error(json : Json) -> Bool {
  match json {
    Object(obj) => {
      // Check for explicit auth_error type
      let is_type_auth = match obj.get("type") {
        Some(String(s)) => s == "auth_error"
        _ => false
      }
      if is_type_auth {
        return true
      }
      // Check for error code indicating auth failure
      match obj.get("errcode") {
        Some(Number(n, ..)) => {
          let code = n.to_int()
          // WeCom auth error codes: 40001 (invalid credential), 40014 (invalid access_token)
          code == 40001 || code == 40014
        }
        _ => false
      }
    }
    _ => false
  }
}

///|
/// Extract the req_id from a frame for ACK matching.
pub fn extract_req_id(json : Json) -> String? {
  match json {
    Object(obj) =>
      match obj.get("req_id") {
        Some(String(s)) => Some(s)
        _ => None
      }
    _ => None
  }
}

///|
/// Extract the message content from a Data frame.
pub fn extract_data_content(json : Json) -> String? {
  match json {
    Object(obj) =>
      match obj.get("content") {
        Some(String(s)) => Some(s)
        _ => None
      }
    _ => None
  }
}

///|
/// Extract the chat_id from a Data frame.
pub fn extract_data_chat_id(json : Json) -> String? {
  match json {
    Object(obj) =>
      match obj.get("chat_id") {
        Some(String(s)) => Some(s)
        _ => None
      }
    _ => None
  }
}

///|
/// Extract the sender info from a Data frame.
pub fn extract_data_sender(json : Json) -> (String, String) {
  match json {
    Object(obj) => {
      let sender_id = match obj.get("from_user_id") {
        Some(String(s)) => s
        _ => ""
      }
      let sender_name = match obj.get("from_user_name") {
        Some(String(s)) => s
        _ => sender_id
      }
      (sender_id, sender_name)
    }
    _ => ("", "")
  }
}

// ── Chunked Upload ───────────────────────────────────────────────────────────

///|
/// WeCom chunked upload state for large file transfers.
pub(all) struct WeComUploadState {
  mut upload_id : String
  mut chunk_index : Int
  chunk_size : Int
  total_size : Int
}

///|
/// Create a new WeComUploadState.
pub fn WeComUploadState::new(total_size : Int) -> WeComUploadState {
  {
    upload_id: "",
    chunk_index: 0,
    chunk_size: WECOM_DEFAULT_CHUNK_SIZE,
    total_size,
  }
}

///|
/// Create a WeComUploadState with custom chunk size.
pub fn WeComUploadState::with_chunk_size(
  total_size : Int,
  chunk_size : Int,
) -> WeComUploadState {
  { upload_id: "", chunk_index: 0, chunk_size, total_size }
}

///|
/// Set the upload_id after receiving init response.
pub fn WeComUploadState::set_upload_id(
  self : WeComUploadState,
  id : String,
) -> Unit {
  self.upload_id = id
}

///|
/// Advance to the next chunk and return its index.
pub fn WeComUploadState::next_chunk(self : WeComUploadState) -> Int {
  let idx = self.chunk_index
  self.chunk_index = self.chunk_index + 1
  idx
}

///|
/// Check if all chunks have been sent.
pub fn WeComUploadState::is_complete(self : WeComUploadState) -> Bool {
  self.chunk_index >= calculate_chunk_count(self.total_size, self.chunk_size)
}

///|
/// Reset the upload state for retry.
pub fn WeComUploadState::reset(self : WeComUploadState) -> Unit {
  self.upload_id = ""
  self.chunk_index = 0
}

///|
/// Build the upload initialization frame.
///
/// Step 1 of 3-step chunked upload: init -> chunks -> finish.
pub fn build_upload_init_frame(
  upload_id : String,
  filename : String,
  total_size : Int,
) -> Json {
  let frame : Map[String, Json] = {}
  frame.set("type", "aibot_upload_init".to_json())
  frame.set("upload_id", upload_id.to_json())
  frame.set("filename", filename.to_json())
  frame.set("total_size", total_size.to_json())
  Json::object(frame)
}

///|
/// Build a chunk data frame.
///
/// Step 2 of 3-step chunked upload: send each chunk sequentially.
pub fn build_upload_chunk_frame(
  upload_id : String,
  chunk_index : Int,
  data : String,
) -> Json {
  let frame : Map[String, Json] = {}
  frame.set("type", "aibot_upload_chunk".to_json())
  frame.set("upload_id", upload_id.to_json())
  frame.set("chunk_index", chunk_index.to_json())
  frame.set("data", data.to_json())
  Json::object(frame)
}

///|
/// Build the upload finish frame.
///
/// Step 3 of 3-step chunked upload: finalize and receive media_id.
pub fn build_upload_finish_frame(upload_id : String) -> Json {
  let frame : Map[String, Json] = {}
  frame.set("type", "aibot_upload_finish".to_json())
  frame.set("upload_id", upload_id.to_json())
  Json::object(frame)
}

///|
/// Calculate the total number of chunks needed.
pub fn calculate_chunk_count(total_size : Int, chunk_size : Int) -> Int {
  if chunk_size <= 0 {
    1
  } else {
    (total_size + chunk_size - 1) / chunk_size
  }
}

// ── Utility ──────────────────────────────────────────────────────────────────

///|
/// Build a full subscribe frame from WeComWsState.
pub fn WeComWsState::build_auth_frame(self : WeComWsState) -> Json {
  build_subscribe_frame(self.bot_id, self.secret)
}

///|
/// Build a send_msg frame from WeComWsState with auto-incremented req_id.
pub fn WeComWsState::build_msg_frame(
  self : WeComWsState,
  chat_id : String,
  content : String,
  msg_type : String,
) -> Json {
  let req_id = self.next_req_id()
  build_send_msg_frame(chat_id, content, msg_type, req_id)
}

///|
/// Build a ping frame (convenience method on state).
pub fn WeComWsState::build_heartbeat(_self : WeComWsState) -> Json {
  build_ping_frame()
}

///|
/// Determine if a frame type requires an ACK response.
pub fn needs_ack(frame_type : WeComFrameType) -> Bool {
  match frame_type {
    WeComFrameType::SendMsg => true
    WeComFrameType::Data => true
    _ => false
  }
}

///|
/// Check if a frame type represents a server response to our request.
pub fn is_response_frame(frame_type : WeComFrameType) -> Bool {
  match frame_type {
    WeComFrameType::Ack => true
    WeComFrameType::Pong => true
    WeComFrameType::Data => true
    _ => false
  }
}
