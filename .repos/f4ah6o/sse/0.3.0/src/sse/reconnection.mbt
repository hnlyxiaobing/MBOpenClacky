///|
/// Set up automatic reconnection for an SSE connection
pub fn setup_auto_reconnect(conn : SseConnection) -> SseConnection {
  let reconnect_handler = create_reconnect_handler(conn)
  let error_handler_adapter = create_error_adapter(conn, reconnect_handler)
  let _ = on_error(conn, error_handler_adapter)
  conn
}

///|
/// Create a JavaScript wrapper function that handles reconnection
extern "js" fn create_reconnect_handler(conn : SseConnection) -> ErrorHandler =
  #|(conn) => {
  #|  return function(evt) {
  #|    const es = conn.event_source.raw;
  #||
  #|    // Check if we should attempt reconnection
  #|    if (conn.is_closed) {
  #|      console.log('[sse.mbt] Connection is closed, not reconnecting');
  #|      return;
  #|    }
  #|
  #|    if (conn.retry_count >= conn.config.max_retries) {
  #|      console.error('[sse.mbt] Max retries exceeded, giving up');
  #|      return;
  #|    }
  #|
  #|    // Check if the EventSource is actually closed
  #|    if (es.readyState === 2) { // CLOSED
  #|      console.log('[sse.mbt] Connection closed, attempting reconnect...');
  #|      conn.retry_count = (conn.retry_count || 0) + 1;
  #|
  #|      // Wait before reconnecting
  #|      setTimeout(() => {
  #|        if (conn.is_closed) return;
  #|
  #|        try {
  #|          const newEs = conn.config.with_credentials
  #|            ? new EventSource(conn.config.url, { withCredentials: true })
  #|            : new EventSource(conn.config.url);
  #|
  #|          // Replace the old EventSource with the new one
  #|          conn.event_source.raw = newEs;
  #|
  #|          console.log('[sse.mbt] Reconnection successful');
  #|        } catch (e) {
  #|          console.error('[sse.mbt] Reconnection failed:', e);
  #|        }
  #|      }, conn.config.reconnect_interval);
  #|    }
  #|  };
  #|}

///|
/// Create an adapter that wraps the error handler with reconnection logic
extern "js" fn create_error_adapter(
  conn : SseConnection,
  reconnect_handler : ErrorHandler,
) -> ErrorHandler =
  #|(conn, reconnectHandler) => {
  #|  return function(evt) {
  #|    // Call the reconnection handler first
  #|    reconnectHandler(evt);
  #|  };
  #|}

///|
/// Manually trigger a reconnection
pub fn reconnect(conn : SseConnection) -> Unit {
  if conn.is_closed {
    return
  }
  event_source_close(conn.event_source)
  let new_es = if conn.config.with_credentials {
    event_source_new_with_credentials(
      conn.config.url,
      conn.config.with_credentials,
    )
  } else {
    event_source_new(conn.config.url)
  }
  replace_event_source(conn, new_es)
}

///|
/// Replace the EventSource in a connection (internal use)
extern "js" fn replace_event_source(
  conn : SseConnection,
  new_es : EventSource,
) -> Unit =
  #|(conn, newEs) => {
  #|  conn.event_source = newEs;
  #|  conn.retry_count = 0;
  #|}
