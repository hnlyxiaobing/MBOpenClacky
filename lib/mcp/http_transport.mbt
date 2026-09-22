///| HttpTransport: communicates with an MCP server over HTTP/SSE.

///|
/// Transport that communicates with an MCP server over HTTP, implementing
/// the MCP **Streamable HTTP** shape: one POST per JSON-RPC message, with
/// the reply arriving either as an `application/json` body or as a
/// `text/event-stream` (SSE) stream. A server-assigned `Mcp-Session-Id`
/// header is captured and echoed on later requests.
///
/// There is no long-lived connection to establish, so `start` validates the
/// configuration and marks the transport usable; reachability is reported
/// honestly by the first request instead (a broken URL or a refused
/// connection surfaces as a request error, never as silent success).
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
    None => Map([])
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
pub extend HttpTransport with Transport::{
  start,
  stop,
  alive,
  send_message,
  send_request,
  on_message,
  stderr_tail,
}

// ── URL and header plumbing ─────────────────────────────────────────────────

///|
/// Split a server URL into the origin handed to `@http.Client` (scheme and
/// authority only — the constructor rejects a URL carrying a path) and the
/// request path used for every JSON-RPC POST.
fn split_server_url(url : String) -> Result[(String, String), String] {
  if !(url.has_prefix("http://") || url.has_prefix("https://")) {
    return Err(
      "HTTP MCP transport requires an absolute http(s) url, got: \{url}",
    )
  }
  let scheme_end = match url.find("://") {
    Some(i) => i + 3
    None => return Err("HTTP MCP transport could not parse the url: \{url}")
  }
  let rest = url[scheme_end:].to_owned()
  let slash = match rest.find("/") {
    Some(i) => i
    None => rest.length()
  }
  if slash == 0 {
    return Err("HTTP MCP transport has no host in the url: \{url}")
  }
  let origin = url[:scheme_end + slash].to_owned()
  let path = if slash >= rest.length() {
    "/"
  } else {
    rest[slash:].to_owned()
  }
  Ok((origin, path))
}

///|
/// Parse JSON text, returning None instead of raising.
fn parse_json_opt(text : String) -> Json? {
  let parsed : Result[Json, Unit] = Ok(@json.parse(text)) catch { _ => Err(()) }
  match parsed {
    Ok(json) => Some(json)
    Err(_) => None
  }
}

///|
/// The header set sent with every JSON-RPC POST, as the HTTP client's
/// case-insensitive header map.
fn HttpTransport::request_headers(self : HttpTransport) -> @http.Headers {
  let result : @http.Headers = Map([])
  self.build_headers().each(fn(k, v) {
    result[@http.CaseInsensitiveString(k)] = v
  })
  result
}

///|
/// Record the session id the server assigned; later requests must echo it.
fn HttpTransport::capture_session_id(
  self : HttpTransport,
  headers : @http.Headers,
) -> Unit {
  match headers.get(@http.CaseInsensitiveString("mcp-session-id")) {
    Some(id) => if !id.is_empty() { self.session_id = Some(id) }
    None => ()
  }
}

// ── Reply correlation ───────────────────────────────────────────────────────

///|
/// True when a frame is the JSON-RPC response addressed to `id`.
fn frame_matches_id(text : String, id : Int) -> Bool {
  match parse_jsonrpc_response(text) {
    Some(resp) => resp.id == Some(id)
    None => false
  }
}

///|
/// Extract the response frame addressed to `id` from one message payload,
/// which may be a single response or a batch array. Returns None when the
/// payload carries no reply for that id.
fn extract_reply(text : String, id : Int) -> String? {
  match parse_json_opt(text) {
    Some(Array(items)) => {
      for item in items {
        let frame = item.stringify()
        if frame_matches_id(frame, id) {
          return Some(frame)
        }
      }
      None
    }
    Some(_) => if frame_matches_id(text, id) { Some(text) } else { None }
    None => None
  }
}

///|
/// Forward one non-reply message (notification or server-initiated request)
/// to the registered handler, if any.
fn HttpTransport::forward(self : HttpTransport, payload : String) -> Unit {
  match self.message_handler {
    Some(handler) => handler(payload)
    None => ()
  }
}

// ── Trait implementation ────────────────────────────────────────────────────

///|
/// Validate the configured URL and mark the transport usable. No network
/// round trip happens here: Streamable HTTP has no connection to establish,
/// and the first request reports reachability honestly.
pub impl Transport for HttpTransport with fn start(self) -> Result[
  Unit,
  String,
] {
  if self.is_alive {
    return Ok(())
  }
  match split_server_url(self.url) {
    Ok(_) => ()
    Err(reason) => return Err(reason)
  }
  self.is_alive = true
  Ok(())
}

///|
/// Stop the HTTP transport (close session).
pub impl Transport for HttpTransport with fn stop(self) -> Unit {
  self.is_alive = false
  self.session_id = None
}

///|
/// Check if the transport is still alive.
pub impl Transport for HttpTransport with fn alive(self) -> Bool {
  self.is_alive
}

///|
/// POST a JSON-RPC notification. No response body is expected; a server
/// error status is reported rather than swallowed.
pub impl Transport for HttpTransport with fn send_message(self, message) -> Result[
  Unit,
  String,
] {
  if !self.is_alive {
    return Err("MCP transport is not started")
  }
  let (origin, path) = match self.open_endpoint() {
    Ok(parts) => parts
    Err(reason) => return Err(reason)
  }
  let client = match self.connect(origin) {
    Ok(c) => c
    Err(reason) => return Err(reason)
  }
  defer client.close()
  let posted : Result[@http.Response, String] = Ok(
      client.post(path, message, extra_headers=self.request_headers()),
    ) catch {
    _ => Err("Failed to POST to the MCP server: \{self.url}")
  }
  let response = match posted {
    Ok(r) => r
    Err(reason) => return Err(reason)
  }
  self.capture_session_id(response.headers)
  if response.code >= 400 {
    return Err("MCP server rejected the notification with HTTP \{response.code}")
  }
  // 202 Accepted (notifications) and 200 with an empty body are both normal.
  let text = client.read_all().text().trim().to_owned()
  if text.is_empty() {
    return Ok(())
  }
  // A body here is a server error object: successful notifications are empty.
  match parse_jsonrpc_response(text) {
    Some(resp) =>
      match resp.error {
        Some(err) => Err("MCP server returned an error: \{err.message}")
        None => Ok(())
      }
    None => Ok(())
  }
}

///|
/// Send a JSON-RPC request and wait for the response correlated by id.
/// Non-reply messages seen on an SSE stream are forwarded to the handler.
pub impl Transport for HttpTransport with fn send_request(
  self,
  id,
  message,
  timeout_s,
) -> Result[String, String] {
  if !self.is_alive {
    return Err("MCP transport is not started")
  }
  let (origin, path) = match self.open_endpoint() {
    Ok(parts) => parts
    Err(reason) => return Err(reason)
  }
  let result : Result[String, String] = @async.with_timeout(
    timeout_s * 1000,
    () => self.round_trip(origin, path, id, message),
  ) catch {
    @async.TimeoutError =>
      Err(
        "MCP request timed out after \{timeout_s}s (id: \{id}, url: \{self.url})",
      )
    _ => Err("MCP request wait failed (id: \{id})")
  }
  result
}

///|
/// Register a message handler for incoming responses.
pub impl Transport for HttpTransport with fn on_message(self, handler) -> Unit {
  self.message_handler = Some(handler)
}

///|
/// Get stderr tail (not applicable for HTTP, returns empty string).
pub impl Transport for HttpTransport with fn stderr_tail(_self) -> String {
  ""
}

// ── Request round trip ──────────────────────────────────────────────────────

///|
/// Resolve the configured URL into the origin and request path, reporting an
/// unusable configuration instead of building an invalid request.
fn HttpTransport::open_endpoint(
  self : HttpTransport,
) -> Result[(String, String), String] {
  split_server_url(self.url)
}

///|
/// Open a connection to the server origin, reporting a refused or
/// unresolvable connection as an error.
async fn HttpTransport::connect(self : HttpTransport, origin : String) -> Result[
  @http.Client,
  String,
] {
  let connected : Result[@http.Client, String] = Ok(@http.Client(origin)) catch {
    _ => Err("Failed to connect to the MCP server: \{self.url}")
  }
  connected
}

///|
/// POST one JSON-RPC request on a fresh connection and return the frame
/// carrying its reply.
///
/// A connection per request keeps the SSE path simple: reading stops as soon
/// as the reply arrives, so a server that keeps its stream open cannot wedge
/// the client.
async fn HttpTransport::round_trip(
  self : HttpTransport,
  origin : String,
  path : String,
  id : Int,
  message : String,
) -> Result[String, String] {
  let client = match self.connect(origin) {
    Ok(c) => c
    Err(reason) => return Err(reason)
  }
  defer client.close()
  let posted : Result[@http.Response, String] = Ok(
      client.post(path, message, extra_headers=self.request_headers()),
    ) catch {
    _ => Err("Failed to POST to the MCP server: \{self.url}")
  }
  let response = match posted {
    Ok(r) => r
    Err(reason) => return Err(reason)
  }
  self.capture_session_id(response.headers)
  if response.code >= 400 {
    return Err("MCP server answered HTTP \{response.code} (id: \{id})")
  }
  let content_type = match
    response.headers.get(@http.CaseInsensitiveString("content-type")) {
    Some(value) => value.to_lower()
    None => ""
  }
  if content_type.contains("text/event-stream") {
    self.read_sse_reply(client, id)
  } else {
    let text = client.read_all().text()
    match extract_reply(text, id) {
      Some(reply) => Ok(reply)
      None =>
        Err(
          "MCP server response carried no reply for id \{id} (url: \{self.url})",
        )
    }
  }
}

///|
/// Read an SSE response frame by frame until the reply for `id` arrives.
/// `event:`, `id:`, comment and blank lines are protocol framing, not
/// messages; anything that is a JSON-RPC message but not our reply goes to
/// the message handler.
async fn HttpTransport::read_sse_reply(
  self : HttpTransport,
  client : @http.Client,
  id : Int,
) -> Result[String, String] {
  while true {
    match client.read_until("\n") {
      None =>
        return Err(
          "MCP SSE stream closed before the reply arrived (id: \{id}, url: \{self.url})",
        )
      Some(raw) => {
        let text = raw.trim().to_owned()
        if !text.has_prefix("data:") {
          continue
        }
        let payload = text[5:].trim().to_owned()
        if payload.is_empty() {
          continue
        }
        match extract_reply(payload, id) {
          Some(reply) => return Ok(reply)
          None => self.forward(payload)
        }
      }
    }
  }
  // unreachable: the loop only exits by returning
  Err("MCP SSE stream ended unexpectedly (id: \{id})")
}

// ── Helpers kept for callers that inspect the transport ─────────────────────

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
  let result : Map[String, String] = Map([])
  self.headers.each(fn(k, v) { result[k] = v })
  result["Content-Type"] = "application/json"
  // Streamable HTTP servers may answer either inline JSON or an SSE stream.
  result["Accept"] = "application/json, text/event-stream"
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