///| Transport trait and helper functions for MCP communication.

///|
/// Transport abstraction for MCP server communication.
/// Implementations handle the actual I/O (stdio, HTTP, etc.).
pub(open) trait Transport {
  fn start(Self) -> Unit
  fn stop(Self) -> Unit
  fn alive(Self) -> Bool
  fn send_message(Self, String) -> Unit
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
    None => Json::object({})
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
/// Parse a JSON-RPC 2.0 response from a text string.
pub fn parse_jsonrpc_response(text : String) -> JsonRpcResponse? {
  let trimmed = text.trim()
  if trimmed.length() == 0 {
    return None
  }
  let json : Json = @json.parse(trimmed) catch { _ => return None }
  JsonRpcResponse::from_json(json)
}
