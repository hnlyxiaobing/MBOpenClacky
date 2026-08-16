///| Discord Gateway v10 WebSocket client.
///
/// Implements the full Gateway lifecycle:
/// Connect -> Hello (op 10) -> Identify (op 2) -> Heartbeat loop (op 1/11)
/// -> Dispatch events (op 0) -> Resume on disconnect (op 6)
///
/// Features:
/// - Automatic heartbeat with jitter
/// - Session resume on transient disconnects
/// - Fatal close code detection (no reconnect)
/// - Exponential backoff on reconnect failures

///|
/// Gateway v10 WebSocket endpoint.
pub const DISCORD_GATEWAY_URL : String = "wss://gateway.discord.gg/?v=10&encoding=json"

///|
/// Discord Gateway opcodes.
pub(all) enum GatewayOpcode {
  /// 0 - Dispatch: server sends events
  Dispatch
  /// 1 - Heartbeat: bidirectional keepalive
  Heartbeat
  /// 2 - Identify: client sends on connect
  Identify
  /// 3 - Presence Update: client sends
  PresenceUpdate
  /// 4 - Voice State Update: client sends
  VoiceStateUpdate
  /// 6 - Resume: client sends to resume session
  Resume
  /// 7 - Reconnect: server requests reconnection
  Reconnect
  /// 9 - Invalid Session: server rejects session
  InvalidSession
  /// 10 - Hello: server sends on connect with heartbeat_interval
  Hello
  /// 11 - Heartbeat ACK: server acknowledges heartbeat
  HeartbeatAck
} derive(Eq, Debug)

///|
pub extend GatewayOpcode with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend GatewayOpcode with Eq::{not_equal, equal}

///|
/// Convert an integer opcode to GatewayOpcode.
pub fn gateway_opcode_from_int(op : Int) -> GatewayOpcode? {
  match op {
    0 => Some(GatewayOpcode::Dispatch)
    1 => Some(GatewayOpcode::Heartbeat)
    2 => Some(GatewayOpcode::Identify)
    3 => Some(GatewayOpcode::PresenceUpdate)
    4 => Some(GatewayOpcode::VoiceStateUpdate)
    6 => Some(GatewayOpcode::Resume)
    7 => Some(GatewayOpcode::Reconnect)
    9 => Some(GatewayOpcode::InvalidSession)
    10 => Some(GatewayOpcode::Hello)
    11 => Some(GatewayOpcode::HeartbeatAck)
    _ => None
  }
}

///|
/// Convert GatewayOpcode to its integer value.
pub fn GatewayOpcode::to_int(self : GatewayOpcode) -> Int {
  match self {
    Dispatch => 0
    Heartbeat => 1
    Identify => 2
    PresenceUpdate => 3
    VoiceStateUpdate => 4
    Resume => 6
    Reconnect => 7
    InvalidSession => 9
    Hello => 10
    HeartbeatAck => 11
  }
}

///|
/// Gateway connection state.
pub(all) struct GatewayState {
  mut session_id : String?
  mut last_seq : Int?
  mut resume_gateway_url : String?
  mut heartbeat_interval : Int
  mut is_connected : Bool
  mut is_ready : Bool
  mut heartbeat_acked : Bool
  mut reconnect_attempts : Int
  bot_token : String
  intents : Int
}

///|
/// Maximum reconnect attempts before giving up.
pub const MAX_RECONNECT_ATTEMPTS : Int = 10

///|
/// Base reconnect delay in milliseconds (5 seconds).
pub const RECONNECT_BASE_DELAY_MS : Int = 5000

///|
/// Discord Gateway intents.
pub const INTENT_GUILDS : Int = 1

///|
pub const INTENT_GUILD_MESSAGES : Int = 512

///|
pub const INTENT_GUILD_MESSAGE_REACTIONS : Int = 1024

///|
pub const INTENT_DIRECT_MESSAGES : Int = 4096

///|
pub const INTENT_MESSAGE_CONTENT : Int = 32768

///|
/// Default intents for MBOpenClacky bot.
pub const DEFAULT_INTENTS : Int = INTENT_GUILDS +
  INTENT_GUILD_MESSAGES +
  INTENT_GUILD_MESSAGE_REACTIONS +
  INTENT_DIRECT_MESSAGES +
  INTENT_MESSAGE_CONTENT

///|
/// Check if a close code is fatal (should NOT reconnect).
///
/// Fatal codes: 4004, 4010, 4011, 4012, 4013, 4014.
pub fn is_fatal_close(code : Int) -> Bool {
  code == 4004 ||
  code == 4010 ||
  code == 4011 ||
  code == 4012 ||
  code == 4013 ||
  code == 4014
}

///|
/// Create a new GatewayState.
pub fn GatewayState::new(bot_token : String) -> GatewayState {
  {
    session_id: None,
    last_seq: None,
    resume_gateway_url: None,
    heartbeat_interval: 41250,
    is_connected: false,
    is_ready: false,
    heartbeat_acked: true,
    reconnect_attempts: 0,
    bot_token,
    intents: DEFAULT_INTENTS,
  }
}

///|
/// Create a new GatewayState with custom intents.
pub fn GatewayState::with_intents(
  bot_token : String,
  intents : Int,
) -> GatewayState {
  {
    session_id: None,
    last_seq: None,
    resume_gateway_url: None,
    heartbeat_interval: 41250,
    is_connected: false,
    is_ready: false,
    heartbeat_acked: true,
    reconnect_attempts: 0,
    bot_token,
    intents,
  }
}

///|
/// Check whether the gateway can attempt a resume.
///
/// Resume is possible when we have a valid session_id and last_seq.
pub fn should_resume(state : GatewayState) -> Bool {
  match (state.session_id, state.last_seq) {
    (Some(_), Some(_)) => true
    _ => false
  }
}

///|
/// Get the gateway URL to connect to.
///
/// If resume_gateway_url is available (from a previous Reconnect event),
/// use that; otherwise use the default gateway URL.
pub fn get_gateway_url(state : GatewayState) -> String {
  match state.resume_gateway_url {
    Some(url) => url
    None => DISCORD_GATEWAY_URL
  }
}

///|
/// Calculate reconnect delay with exponential backoff.
///
/// delay = base_delay * 2^attempt, capped at 60s.
pub fn reconnect_delay_ms(attempts : Int) -> Int {
  let exp = if attempts > 6 { 6 } else { attempts }
  let delay = RECONNECT_BASE_DELAY_MS * (1 << exp)
  let max_delay = 60000
  if delay > max_delay {
    max_delay
  } else {
    delay
  }
}

///|
/// Check if reconnect should be attempted.
pub fn should_reconnect(state : GatewayState, close_code : Int) -> Bool {
  if is_fatal_close(close_code) {
    false
  } else {
    state.reconnect_attempts < MAX_RECONNECT_ATTEMPTS
  }
}

///|
/// Update state after receiving Hello event (op 10).
///
/// Extracts heartbeat_interval from the Hello payload.
pub fn GatewayState::handle_hello(
  self : GatewayState,
  heartbeat_interval : Int,
) -> Unit {
  self.heartbeat_interval = heartbeat_interval
  self.is_connected = true
  self.heartbeat_acked = true
  self.reconnect_attempts = 0
}

///|
/// Update state after successful Identify/Resume (READY event).
pub fn GatewayState::handle_ready(
  self : GatewayState,
  session_id : String,
  resume_gateway_url : String?,
) -> Unit {
  self.session_id = Some(session_id)
  self.resume_gateway_url = resume_gateway_url
  self.is_ready = true
}

///|
/// Update the last sequence number from a Dispatch event.
pub fn GatewayState::update_seq(self : GatewayState, seq : Int) -> Unit {
  self.last_seq = Some(seq)
}

///|
/// Mark heartbeat as sent (waiting for ACK).
pub fn GatewayState::mark_heartbeat_sent(self : GatewayState) -> Unit {
  self.heartbeat_acked = false
}

///|
/// Mark heartbeat ACK received.
pub fn GatewayState::mark_heartbeat_acked(self : GatewayState) -> Unit {
  self.heartbeat_acked = true
}

///|
/// Record a reconnect attempt.
pub fn GatewayState::record_reconnect_attempt(self : GatewayState) -> Unit {
  self.reconnect_attempts = self.reconnect_attempts + 1
}

///|
/// Reset connection state for a new connect attempt.
pub fn GatewayState::reset_connection(self : GatewayState) -> Unit {
  self.is_connected = false
  self.is_ready = false
  self.heartbeat_acked = true
}

///|
/// Build the Identify payload (op 2).
///
/// Sent after Hello to authenticate with the gateway.
pub fn build_identify_payload(token : String, intents : Int) -> Json {
  let payload : Map[String, Json] = Map([])
  payload.set("op", (2).to_json())
  let d : Map[String, Json] = Map([])
  d.set("token", token.to_json())
  d.set("intents", intents.to_json())
  let properties : Map[String, Json] = Map([])
  properties.set("os", "windows".to_json())
  properties.set("browser", "MBOpenClacky".to_json())
  properties.set("device", "MBOpenClacky".to_json())
  d.set("properties", Json::object(properties))
  payload.set("d", Json::object(d))
  Json::object(payload)
}

///|
/// Build the Resume payload (op 6).
///
/// Sent when reconnecting to resume an existing session.
pub fn build_resume_payload(
  token : String,
  session_id : String,
  seq : Int,
) -> Json {
  let payload : Map[String, Json] = Map([])
  payload.set("op", (6).to_json())
  let d : Map[String, Json] = Map([])
  d.set("token", token.to_json())
  d.set("session_id", session_id.to_json())
  d.set("seq", seq.to_json())
  payload.set("d", Json::object(d))
  Json::object(payload)
}

///|
/// Build the Heartbeat payload (op 1).
///
/// `seq` is the last received sequence number, or null if none.
pub fn build_heartbeat_payload(seq : Int?) -> Json {
  let payload : Map[String, Json] = Map([])
  payload.set("op", (1).to_json())
  match seq {
    Some(s) => payload.set("d", s.to_json())
    None => payload.set("d", Json::null())
  }
  Json::object(payload)
}

///|
/// Parse a Gateway event from raw JSON.
///
/// Returns (opcode, data payload).
/// The data field `d` type depends on the opcode.
pub fn parse_gateway_event(json : Json) -> Result[(Int, Json), ChannelError] {
  match json {
    Object(obj) => {
      let op = match obj.get("op") {
        Some(Number(n, ..)) => n.to_int()
        _ =>
          return Err(ChannelError("Missing or invalid 'op' in gateway event"))
      }
      let d = match obj.get("d") {
        Some(v) => v
        None => Json::null()
      }
      Ok((op, d))
    }
    _ => Err(ChannelError("Invalid gateway event: expected JSON object"))
  }
}

///|
/// Extract the sequence number from a gateway event.
pub fn extract_seq(json : Json) -> Int? {
  match json {
    Object(obj) =>
      match obj.get("s") {
        Some(Number(n, ..)) => Some(n.to_int())
        _ => None
      }
    _ => None
  }
}

///|
/// Extract the event name from a Dispatch event (op 0).
pub fn extract_event_name(json : Json) -> String? {
  match json {
    Object(obj) =>
      match obj.get("t") {
        Some(String(s)) => Some(s)
        _ => None
      }
    _ => None
  }
}

///|
/// Parse the Hello event payload.
///
/// Returns the heartbeat_interval in milliseconds.
pub fn parse_hello_payload(data : Json) -> Result[Int, ChannelError] {
  match data {
    Object(obj) =>
      match obj.get("heartbeat_interval") {
        Some(Number(n, ..)) => Ok(n.to_int())
        _ => Err(ChannelError("Missing heartbeat_interval in Hello payload"))
      }
    _ => Err(ChannelError("Invalid Hello payload"))
  }
}

///|
/// Parse the Ready event payload.
///
/// Returns (session_id, resume_gateway_url?).
pub fn parse_ready_payload(
  data : Json,
) -> Result[(String, String?), ChannelError] {
  match data {
    Object(obj) => {
      let session_id = match obj.get("session_id") {
        Some(String(s)) => s
        _ => return Err(ChannelError("Missing session_id in READY payload"))
      }
      let resume_url = match obj.get("resume_gateway_url") {
        Some(String(s)) => Some(s)
        _ => None
      }
      Ok((session_id, resume_url))
    }
    _ => Err(ChannelError("Invalid READY payload"))
  }
}

///|
/// Handle an Invalid Session event (op 9).
///
/// The data field `d` is a boolean indicating whether the session is resumable.
pub fn parse_invalid_session(data : Json) -> Bool {
  match data {
    True => true
    False => false
    _ => false
  }
}
