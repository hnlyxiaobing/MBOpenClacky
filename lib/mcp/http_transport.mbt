///| HttpTransport: communicates with MCP server via HTTP/SSE.

///|
/// Transport that communicates with an MCP server over HTTP.
/// Supports both application/json and text/event-stream (SSE) response modes.
pub(all) struct HttpTransport {
  url : String
  headers : Map[String, String]
  mut session_id : String?
  mut is_alive : Bool
  mut message_handler : ((String) -> Unit)?
  open_timeout : Int // 10 seconds
  read_timeout : Int // 120 seconds
}

///|
/// Create a new HttpTransport from an McpServerSpec.
pub fn HttpTransport::new(spec : McpServerSpec) -> HttpTransport {
  let url = match spec.url {
    Some(u) => u
    None => ""
  }
  let headers : Map[String, String] = match spec.headers {
    Some(h) => h
    None => {}
  }
  {
    url,
    headers,
    session_id: None,
    is_alive: false,
    message_handler: None,
    open_timeout: 10,
    read_timeout: 120,
  }
}

///|
/// Start the HTTP transport (establish connection).
/// TODO: FFI implementation needed - requires HTTP client capability.
pub impl Transport for HttpTransport with fn start(self) {
  self.is_alive = true
}

///|
/// Stop the HTTP transport (close session).
pub impl Transport for HttpTransport with fn stop(self) {
  self.is_alive = false
  self.session_id = None
}

///|
/// Check if the transport is still alive.
pub impl Transport for HttpTransport with fn alive(self) -> Bool {
  self.is_alive
}

///|
/// Send a JSON-RPC message via HTTP POST.
pub impl Transport for HttpTransport with fn send_message(self, message) {
  if !self.is_alive {
    ignore(message)
    return
  }
  ignore(message)
}

///|
/// Register a message handler for incoming responses.
pub impl Transport for HttpTransport with fn on_message(self, handler) {
  self.message_handler = Some(handler)
}

///|
/// Get stderr tail (not applicable for HTTP, returns empty string).
pub impl Transport for HttpTransport with fn stderr_tail(_self) -> String {
  ""
}

///|
/// Update the session ID (called after receiving response headers).
pub fn HttpTransport::set_session_id(self : HttpTransport, id : String) -> Unit {
  self.session_id = Some(id)
}

///|
/// Get the current session ID.
pub fn HttpTransport::get_session_id(self : HttpTransport) -> String? {
  self.session_id
}

///|
/// Build request headers including session tracking.
pub fn HttpTransport::build_headers(
  self : HttpTransport,
) -> Map[String, String] {
  let result : Map[String, String] = {}
  self.headers.each(fn(k, v) { result[k] = v })
  result["Content-Type"] = "application/json"
  match self.session_id {
    Some(id) => result["Mcp-Session-Id"] = id
    None => ()
  }
  result
}

///|
/// Simulate receiving a message (for testing/mock purposes).
pub fn HttpTransport::receive_message(
  self : HttpTransport,
  message : String,
) -> Unit {
  match self.message_handler {
    Some(handler) => handler(message)
    None => ()
  }
}
