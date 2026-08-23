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
  ws_client : WsClient
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
    ws_client: WsClient::new(),
  })
}

///|
pub extend DiscordAdapter with Adapter::{
  platform_id,
  start,
  stop,
  send_text,
  update_message,
  supports_message_updates,
  validate_config,
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
      let empty : Map[String, Json] = Map([])
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

  // Step 3: Gateway connection is handled by run_gateway_loop (async).
  // The caller (server/channel manager) should spawn run_gateway_loop
  // as an async task after calling start.
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
  let msg_id = match extract_discord_message_id(resp) {
    Some(id) => id
    None => return Err(ChannelError("Discord response missing message id"))
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
  // Extract timestamp (ISO 8601 -> epoch ms)
  let timestamp : Int64 = match data.get("timestamp") {
    Some(String(ts)) => parse_iso8601_to_ms(ts)
    _ => 0L
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
  let msg : Map[String, Json] = Map([])
  msg.set("content", text.to_json())
  match reply_to {
    Some(id) => {
      let ref_obj : Map[String, Json] = Map([])
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
pub async fn DiscordAdapter::handle_gateway_event(
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
      // Heartbeat request from server - respond immediately
      let payload = build_heartbeat_payload(state.last_seq)
      let _ = self.ws_client.send_text(payload.stringify())
      state.mark_heartbeat_sent()
    }
    7 => {
      // Reconnect - server requests reconnection
      state.reset_connection()
      let _ = self.ws_client.close()
    }
    9 => {
      // Invalid Session
      let resumable = parse_invalid_session(data)
      if !resumable {
        state.session_id = None
        state.last_seq = None
      }
      state.reset_connection()
      let _ = self.ws_client.close()
      // Discord requires waiting a random 1-5s before reconnecting after
      // an Invalid Session (a fixed 2s is within the allowed window).
      @async.sleep(2000)
    }
    10 =>
      // Hello - extract heartbeat interval and send Identify/Resume
      match parse_hello_payload(data) {
        Ok(interval) => {
          state.handle_hello(interval)
          // Send Identify or Resume based on session state
          if should_resume(state) {
            match (state.session_id, state.last_seq) {
              (Some(sid), Some(seq)) => {
                let payload = build_resume_payload(self.bot_token, sid, seq)
                let _ = self.ws_client.send_text(payload.stringify())
              }
              _ => {
                let payload = build_identify_payload(
                  self.bot_token,
                  state.intents,
                )
                let _ = self.ws_client.send_text(payload.stringify())
              }
            }
          } else {
            let payload = build_identify_payload(self.bot_token, state.intents)
            let _ = self.ws_client.send_text(payload.stringify())
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

///|
/// Run the Discord Gateway event loop (async, long-running).
/// Connects to the gateway, handles Hello/Identify/Resume, runs a
/// client-side heartbeat task (required by the Discord protocol - the
/// server disconnects clients that do not send op 1 heartbeats within
/// ~1.5x heartbeat_interval), and processes incoming events.
///
/// Call this after adapter.start() to begin receiving events.
pub async fn DiscordAdapter::run_gateway_loop(self : DiscordAdapter) -> Unit {
  @async.with_task_group(group => {
    // Heartbeat task: sends op 1 every heartbeat_interval. If the server
    // missed the previous ACK, closes the connection to force a reconnect.
    group.spawn_bg(no_wait=true, allow_failure=true, () => self.heartbeat_loop())
    // Main connect/event loop.
    self.gateway_connect_loop()
  })
}

///|
/// Heartbeat loop (spawned by run_gateway_loop).
///
/// Discord requires the FIRST heartbeat to be sent after
/// heartbeat_interval * random(0..1) ms, and every subsequent heartbeat
/// every heartbeat_interval ms. The server almost never sends op 1
/// itself - the client must initiate. If a heartbeat is not ACKed (op 11)
/// before the next one is due, the connection is considered zombie and
/// is closed so the main loop reconnects (typically with Resume).
pub async fn DiscordAdapter::heartbeat_loop(self : DiscordAdapter) -> Unit {
  while self.is_running {
    let state = match self.gateway_state {
      Some(s) => s
      None => return
    }
    let interval = state.heartbeat_interval
    // Jitter in [0, interval) for the first heartbeat after (re)connect,
    // derived from the millisecond clock (no RNG primitive available).
    let jitter = (@utils.now_ms() % interval.to_int64()).to_int()
    @async.sleep(jitter)
    if !self.is_running {
      return
    }
    // Re-read state: it may have been replaced by stop()/reset.
    let state = match self.gateway_state {
      Some(s) => s
      None => return
    }
    if !state.is_connected || !self.ws_client.connected() {
      // Not connected (yet); wait a full interval before retrying so the
      // cadence restarts after the next HELLO.
      @async.sleep(interval)
      continue
    }
    if !state.heartbeat_acked {
      // Server never ACKed our previous heartbeat: zombie connection.
      // Close it - the main loop's recv() will surface Closed and
      // reconnect (Resume keeps the session when possible).
      let _ = self.ws_client.close()
      state.reset_connection()
      continue
    }
    let payload = build_heartbeat_payload(state.last_seq)
    let _ = self.ws_client.send_text(payload.stringify())
    state.mark_heartbeat_sent()
    // Wait out the remainder of the interval.
    @async.sleep(interval - jitter)
  }
}

///|
/// Reconnect/event loop (the connect -> recv -> dispatch cycle).
pub async fn DiscordAdapter::gateway_connect_loop(
  self : DiscordAdapter,
) -> Unit {
  while self.is_running {
    let state = match self.gateway_state {
      Some(s) => s
      None => return
    }
    // Connect to gateway
    let url = get_gateway_url(state)
    match self.ws_client.connect(url) {
      Ok(_) => ()
      Err(_) => {
        // Connection failed - backoff and retry
        state.record_reconnect_attempt()
        if state.reconnect_attempts >= MAX_RECONNECT_ATTEMPTS {
          return
        }
        let delay = reconnect_delay_ms(state.reconnect_attempts)
        @async.sleep(delay)
        continue
      }
    }
    // Event loop: receive and process messages
    while self.is_running && self.ws_client.connected() {
      let msg = self.ws_client.recv()
      match msg {
        WsMessage::Text(text) => {
          let _ = self.handle_gateway_event(text)
        }
        WsMessage::Closed(code, _) => {
          // Connection closed
          if is_fatal_close(code) {
            // Fatal close - do not reconnect
            self.is_running = false
            return
          }
          // Non-fatal close - attempt reconnect with backoff
          state.reset_connection()
          state.record_reconnect_attempt()
          if !should_reconnect(state, code) {
            self.is_running = false
            return
          }
          let delay = reconnect_delay_ms(state.reconnect_attempts)
          @async.sleep(delay)
          break // break inner loop to reconnect
        }
      }
    }
    // Heartbeat check: if we're still connected but missed ACK, reconnect
    if self.is_running && self.ws_client.connected() {
      match self.gateway_state {
        Some(s) if !s.heartbeat_acked => {
          // Missed heartbeat ACK - force reconnect
          let _ = self.ws_client.close()
          s.reset_connection()
        }
        _ => ()
      }
    }
  }
}

///|
/// Send a heartbeat to the gateway (called periodically).
pub async fn DiscordAdapter::send_heartbeat(self : DiscordAdapter) -> Unit {
  let state = match self.gateway_state {
    Some(s) => s
    None => return
  }
  let payload = build_heartbeat_payload(state.last_seq)
  let _ = self.ws_client.send_text(payload.stringify())
  state.mark_heartbeat_sent()
}

// ── ISO 8601 Timestamp Parsing ──────────────────────────────────────────────

///|
/// Parse an ISO 8601 timestamp string to Unix epoch milliseconds.
/// Handles format: "YYYY-MM-DDTHH:MM:SS.ffffff+HH:MM" or "...Z"
/// Returns 0 on parse failure.
pub fn parse_iso8601_to_ms(ts : String) -> Int64 {
  // Minimum valid: "2026-01-01T00:00:00Z" = 20 chars
  if ts.length() < 20 {
    return 0L
  }
  // Parse date components
  let year = parse_digits(ts, 0, 4)
  let month = parse_digits(ts, 5, 7)
  let day = parse_digits(ts, 8, 10)
  let hour = parse_digits(ts, 11, 13)
  let minute = parse_digits(ts, 14, 16)
  let second = parse_digits(ts, 17, 19)
  if year == 0 && month == 0 && day == 0 {
    return 0L
  }
  // Convert to days since epoch using simplified calculation
  let days = days_since_epoch(year, month, day)
  let total_seconds = days.to_int64() * 86400L +
    hour.to_int64() * 3600L +
    minute.to_int64() * 60L +
    second.to_int64()
  // Parse timezone offset
  let offset_seconds = parse_tz_offset(ts)
  let utc_seconds = total_seconds - offset_seconds.to_int64()
  // Parse fractional seconds (milliseconds)
  let mut ms = 0L
  if ts.length() > 19 && ts[19:20] == "." {
    // Extract up to 3 digits of fractional seconds
    let mut i = 20
    let mut frac = 0
    let mut digits = 0
    while i < ts.length() && digits < 3 {
      let ch = ts[i:i + 1]
      if ch >= "0" && ch <= "9" {
        frac = frac * 10 + (ch[0].to_int() - '0'.to_int())
        digits = digits + 1
      } else {
        break
      }
      i = i + 1
    }
    // Pad to 3 digits
    while digits < 3 {
      frac = frac * 10
      digits = digits + 1
    }
    ms = frac.to_int64()
  }
  utc_seconds * 1000L + ms
}

///|
/// Parse decimal digits from a string slice [start, end).
fn parse_digits(s : String, start : Int, end : Int) -> Int {
  if end > s.length() {
    return 0
  }
  let mut result = 0
  for i = start; i < end; i = i + 1 {
    let ch = s[i]
    if ch >= '0' && ch <= '9' {
      result = result * 10 + (ch.to_int() - '0'.to_int())
    } else {
      return 0
    }
  }
  result
}

///|
/// Parse timezone offset from ISO 8601 string.
/// Handles "+HH:MM", "-HH:MM", and "Z" suffix.
/// Returns offset in seconds (positive = ahead of UTC).
fn parse_tz_offset(ts : String) -> Int {
  let len = ts.length()
  if len == 0 {
    return 0
  }
  // Check for Z suffix
  if ts[len - 1:] == "Z" {
    return 0
  }
  // Look for + or - in the last 6 characters
  let mut i = len - 6
  if i < 19 {
    i = 19
  }
  while i < len {
    if ts[i:i + 1] == "+" || ts[i:i + 1] == "-" {
      let sign = if ts[i:i + 1] == "-" { -1 } else { 1 }
      let hh = parse_digits(ts, i + 1, i + 3)
      let mm = parse_digits(ts, i + 4, i + 6)
      return sign * (hh * 3600 + mm * 60)
    }
    i = i + 1
  }
  0
}

///|
/// Calculate days since Unix epoch (1970-01-01) for a given date.
fn days_since_epoch(year : Int, month : Int, day : Int) -> Int {
  // Algorithm from http://howardhinnant.github.io/date_algorithms.html
  let y = if month <= 2 { year - 1 } else { year }
  let adjusted = if y >= 0 { y } else { y - 399 }
  let era = adjusted / 400
  let yoe = y - era * 400 // [0, 399]
  let m = if month > 2 { month - 3 } else { month + 9 } // [0, 11]
  let doy = (153 * m + 2) / 5 + day - 1 // [0, 365]
  let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy // [0, 146096]
  era * 146097 + doe - 719468
}
