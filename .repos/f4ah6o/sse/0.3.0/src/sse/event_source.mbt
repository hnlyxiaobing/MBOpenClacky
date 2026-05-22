///|
/// EventSource type - opaque wrapper around JavaScript EventSource
pub enum EventSource {
  EventSource(raw~ : JsValue)
}

///|
/// Create a new EventSource connection
extern "js" fn event_source_new(url : String) -> EventSource =
  #|(url) => {
  #|  try {
  #|    const es = new EventSource(url);
  #|    return { $tag: 0, raw: es };
  #|  } catch (e) {
  #|    console.error('[sse.mbt] Failed to create EventSource:', e);
  #|    throw e;
  #|  }
  #|}

///|
/// Create a new EventSource connection with credentials option
extern "js" fn event_source_new_with_credentials(
  url : String,
  with_credentials : Bool,
) -> EventSource =
  #|(url, withCredentials) => {
  #|  try {
  #|    const es = new EventSource(url, { withCredentials: withCredentials });
  #|    return { $tag: 0, raw: es };
  #|  } catch (e) {
  #|    console.error('[sse.mbt] Failed to create EventSource:', e);
  #|    throw e;
  #|  }
  #|}

///|
/// Close an EventSource connection
extern "js" fn event_source_close(es : EventSource) -> Unit =
  #|(es) => {
  #|  if (es && es.raw && typeof es.raw.close === 'function') {
  #|    es.raw.close();
  #|  }
  #|}

///|
/// Get the ready state of an EventSource connection
extern "js" fn event_source_ready_state(es : EventSource) -> Int =
  #|(es) => {
  #|  if (es && es.raw && typeof es.raw.readyState !== 'undefined') {
  #|    return es.raw.readyState;
  #|  }
  #|  return 3; // CLOSED
  #|}

///|
/// Add event listener for a specific event name
extern "js" fn event_source_add_listener(
  es : EventSource,
  event_name : String,
  handler : JsValue,
) -> Unit =
  #|(es, eventName, handler) => {
  #|  if (es && es.raw && typeof es.raw.addEventListener === 'function') {
  #|    es.raw.addEventListener(eventName, handler);
  #|  }
  #|}

///|
/// Remove event listener for a specific event name
extern "js" fn event_source_remove_listener(
  es : EventSource,
  event_name : String,
  handler : JsValue,
) -> Unit =
  #|(es, eventName, handler) => {
  #|  if (es && es.raw && typeof es.raw.removeEventListener === 'function') {
  #|    es.raw.removeEventListener(eventName, handler);
  #|  }
  #|}

///|
/// Add onopen handler
extern "js" fn event_source_on_open(
  es : EventSource,
  handler : JsValue,
) -> Unit =
  #|(es, handler) => {
  #|  if (es && es.raw) {
  #|    es.raw.onopen = handler;
  #|  }
  #|}

///|
/// Add onerror handler
extern "js" fn event_source_on_error(
  es : EventSource,
  handler : JsValue,
) -> Unit =
  #|(es, handler) => {
  #|  if (es && es.raw) {
  #|    es.raw.onerror = handler;
  #|  }
  #|}

///|
/// Get the URL of an EventSource
extern "js" fn event_source_url(es : EventSource) -> String =
  #|(es) => {
  #|  if (es && es.raw && typeof es.raw.url === 'string') {
  #|    return es.raw.url;
  #|  }
  #|  return '';
  #|}
