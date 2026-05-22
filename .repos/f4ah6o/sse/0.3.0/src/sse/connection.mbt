///|
/// SSE Connection structure
pub struct SseConnection {
  event_source : EventSource
  config : @root.ConnectionConfig
  mut retry_count : Int
  mut is_closed : Bool
  state_handlers : Array[@root.ConnectionStateHandler]
  error_handlers : Array[ErrorHandler]
}

///|
/// Create a new SSE connection
pub fn connect(url : String) -> SseConnection {
  connect_with_config(@root.default_connection_config(url))
}

///|
/// Create a new SSE connection with custom configuration
pub fn connect_with_config(config : @root.ConnectionConfig) -> SseConnection {
  let es = if config.with_credentials {
    event_source_new_with_credentials(config.url, config.with_credentials)
  } else {
    event_source_new(config.url)
  }
  {
    event_source: es,
    config,
    retry_count: 0,
    is_closed: false,
    state_handlers: [],
    error_handlers: [],
  }
}

///|
/// Get the current state of the connection
pub fn get_connection_state(conn : SseConnection) -> @root.EventState {
  let ready_state = event_source_ready_state(conn.event_source)
  @root.ready_state_to_event_state(ready_state)
}

///|
/// Check if the connection is open
pub fn is_open(conn : SseConnection) -> Bool {
  match get_connection_state(conn) {
    Open => true
    _ => false
  }
}

///|
/// Check if the connection is closed
pub fn is_closed(conn : SseConnection) -> Bool {
  match get_connection_state(conn) {
    Closed => true
    _ => false
  }
}

///|
/// Close the SSE connection
pub fn close(conn : SseConnection) -> Unit {
  conn.is_closed = true
  event_source_close(conn.event_source)
}

///|
/// Get the URL of the connection
pub fn get_url(conn : SseConnection) -> String {
  event_source_url(conn.event_source)
}

///|
/// Get the configuration of the connection
pub fn get_config(conn : SseConnection) -> @root.ConnectionConfig {
  conn.config
}

///|
/// Get the retry count
pub fn get_retry_count(conn : SseConnection) -> Int {
  conn.retry_count
}

///|
/// Reset the retry count
pub fn reset_retry_count(conn : SseConnection) -> Unit {
  conn.retry_count = 0
}

///|
/// Increment the retry count
pub fn increment_retry_count(conn : SseConnection) -> Unit {
  conn.retry_count = conn.retry_count + 1
}

///|
/// Check if max retries exceeded
pub fn is_max_retries_exceeded(conn : SseConnection) -> Bool {
  conn.retry_count >= conn.config.max_retries
}
