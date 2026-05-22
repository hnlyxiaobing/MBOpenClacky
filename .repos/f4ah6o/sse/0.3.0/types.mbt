///|
/// SSE Event State enumeration
pub enum EventState {
  Connecting
  Open
  Closed
  Error
} derive(Show)

///|
/// SSE Message structure
pub struct SseMessage {
  event_name : String
  data : String
  origin : String
  id : String?
}

///|
/// Connection configuration for SSE
pub struct ConnectionConfig {
  url : String
  with_credentials : Bool
  reconnect_interval : Int
  max_retries : Int
}

///|
/// Default connection configuration
pub fn default_connection_config(url : String) -> ConnectionConfig {
  { url, with_credentials: false, reconnect_interval: 3000, max_retries: 10 }
}

///|
/// Event handler type for SSE events
pub type EventHandler = (SseMessage) -> Unit

///|
/// Connection state handler type
pub type ConnectionStateHandler = (EventState) -> Unit

///|
/// EventSource ready state constants
pub const CONNECTING : Int = 0

///|
pub const OPEN : Int = 1

///|
pub const CLOSED : Int = 2

///|
/// Convert ready state to EventState
pub fn ready_state_to_event_state(state : Int) -> EventState {
  match state {
    0 => EventState::Connecting
    1 => EventState::Open
    2 => EventState::Closed
    _ => EventState::Error
  }
}

///|
/// Server-side SSE event structure
pub(all) struct SSEEvent {
  data : String
  event : String?
  id : String?
} derive(Show, Eq)

///|
pub fn SSEEvent::new(data : String, event : String, id : String?) -> SSEEvent {
  { data, event: Some(event), id }
}

///|
pub fn SSEEvent::data_only(data : String) -> SSEEvent {
  { data, event: None, id: None }
}

///|
pub fn format_event(event : SSEEvent) -> String {
  let mut result = ""
  match event.id {
    Some(id) => result = result + "id: " + id + "\n"
    None => ()
  }
  match event.event {
    Some(e) => result = result + "event: " + e + "\n"
    None => ()
  }
  let data_lines = event.data.split("\n")
  for line_view in data_lines {
    let line = line_view.to_string()
    result = result + "data: " + line + "\n"
  }
  result + "\n"
}
