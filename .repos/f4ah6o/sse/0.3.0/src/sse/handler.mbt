///|
/// Register an event handler for a specific event name
/// Returns the SseConnection for chaining
pub fn on(
  conn : SseConnection,
  event_name : String,
  handler : @root.EventHandler,
) -> SseConnection {
  let js_handler = create_event_wrapper(event_name, handler)
  event_source_add_listener(conn.event_source, event_name, js_handler)
  conn
}

///|
/// Register an open handler
/// Returns the SseConnection for chaining
pub fn on_open(
  conn : SseConnection,
  handler : @root.ConnectionStateHandler,
) -> SseConnection {
  let js_handler = create_open_handler(conn, handler)
  event_source_on_open(conn.event_source, js_handler)
  conn
}

///|
/// Register an error handler
/// Returns the SseConnection for chaining
pub fn on_error(conn : SseConnection, handler : ErrorHandler) -> SseConnection {
  let js_handler = create_error_handler(conn, handler)
  event_source_on_error(conn.event_source, js_handler)
  conn
}

///|
/// Register a message handler (default "message" event)
/// Returns the SseConnection for chaining
pub fn on_message(
  conn : SseConnection,
  handler : @root.EventHandler,
) -> SseConnection {
  on(conn, "message", handler)
}

///|
/// Create a JavaScript wrapper function for SSE events
extern "js" fn create_event_wrapper(
  event_name : String,
  moonbit_handler : @root.EventHandler,
) -> JsValue =
  #|(eventName, moonbitHandler) => {
  #|  return function(evt) {
  #|    const message = {
  #|      event_name: evt.type || eventName,
  #|      data: evt.data || '',
  #|      origin: evt.origin || '',
  #|      id: evt.lastEventId || null
  #|    };
  #|    moonbitHandler(message);
  #|  };
  #|}

///|
/// Create a JavaScript wrapper function for open event
extern "js" fn create_open_handler(
  conn : SseConnection,
  moonbit_handler : @root.ConnectionStateHandler,
) -> JsValue =
  #|(conn, moonbitHandler) => {
  #|  return function(evt) {
  #|    conn.retry_count = 0;
  #|    moonbitHandler({ $tag: 1 }); // EventState::Open
  #|  };
  #|}

///|
/// Create a JavaScript wrapper function for error event
extern "js" fn create_error_handler(
  conn : SseConnection,
  moonbit_handler : ErrorHandler,
) -> JsValue =
  #|(conn, moonbitHandler) => {
  #|  return function(evt) {
  #|    conn.retry_count = (conn.retry_count || 0) + 1;
  #|    moonbitHandler(evt);
  #|  };
  #|}

///|
/// Unregister an event handler for a specific event name
pub fn off(
  conn : SseConnection,
  event_name : String,
  handler : JsValue,
) -> SseConnection {
  event_source_remove_listener(conn.event_source, event_name, handler)
  conn
}
