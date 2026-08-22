///| Transport trait and helper functions for MCP communication.

///|
/// Transport abstraction for MCP server communication.
/// Implementations handle the actual I/O (stdio, HTTP, etc.).
/// start/send paths are async because they perform real I/O; stop is
/// synchronous (it fails pending waiters immediately and defers process
/// termination to a background task).
pub(open) trait Transport {
  async fn start(Self) -> Result[Unit, String]
  fn stop(Self) -> Unit
  fn alive(Self) -> Bool
  async fn send_message(Self, String) -> Result[Unit, String]
  async fn send_request(Self, id : Int, message : String, timeout_s : Int) -> Result[
    String,
    String,
  ]
  fn on_message(Self, (String) -> Unit) -> Unit
  fn stderr_tail(Self) -> String
}

///|
/// Build a JSON-RPC 2.0 request string.
pub fn build_jsonrpc_request(
  id : Int,
  rpc_method : String,
  params : Json?,
) -> String {
  let p : Json = match params {
    Some(p) => p
    None => Json::object(Map([]))
  }
  let obj = Json::object({
    "jsonrpc": "2.0".to_json(),
    "id": id.to_json(),
    "method": rpc_method.to_json(),
    "params": p,
  })
  obj.stringify()
}

///|
/// Build a JSON-RPC 2.0 notification string (no id, no response expected).
pub fn build_jsonrpc_notification(rpc_method : String) -> String {
  Json::object({
    "jsonrpc": "2.0".to_json(),
    "method": rpc_method.to_json(),
    "params": Json::object(Map([])),
  }).stringify()
}

///|
/// Parse a JSON-RPC 2.0 response from a text string.
pub fn parse_jsonrpc_response(text : String) -> JsonRpcResponse? {
  let trimmed = text.trim()
  if trimmed.length() == 0 {
    return None
  }
  let json : Json = @json.parse(trimmed) catch { _ => return None }
  JsonRpcResponse::from_json(json)
}

///|
/// Classify a line received from an MCP server: a response carries an id
/// and no method; notifications and server-initiated requests carry a
/// method and must never complete a pending request.
fn is_jsonrpc_response_line(json : Json) -> Bool {
  match json {
    { "method": _, .. } => false
    _ => true
  }
}
