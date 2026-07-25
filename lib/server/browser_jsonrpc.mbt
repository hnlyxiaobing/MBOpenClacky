///|
/// JSON-RPC 2.0 client for MCP protocol communication over a BrowserProcess.
/// Handles request/response correlation, notifications, and the MCP handshake.

// ── JsonRpcClient struct ────────────────────────────────────────────────────

///|
/// JSON-RPC 2.0 client wrapping a BrowserProcess for MCP protocol communication.
pub(all) struct JsonRpcClient {
  process : BrowserProcess
  mut id_counter : Int
}

///|
/// Create a new JsonRpcClient wrapping the given process.
pub fn JsonRpcClient::new(process : BrowserProcess) -> JsonRpcClient {
  { process, id_counter: 1 }
}

///|
/// Get the underlying BrowserProcess reference.
pub fn JsonRpcClient::get_process(self : JsonRpcClient) -> BrowserProcess {
  self.process
}

// ── Core methods (shared across targets) ────────────────────────────────────

///|
/// Build a JSON-RPC 2.0 request string with the given id, method, and params.
fn build_request(id : Int, http_method : String, params : Json?) -> String {
  let p : Json = match params {
    Some(p) => p
    None => Json::object(Map([]))
  }
  Json::object({
    "jsonrpc": "2.0".to_json(),
    "id": id.to_json(),
    "method": http_method.to_json(),
    "params": p,
  }).stringify()
}

///|
/// Build a JSON-RPC 2.0 notification string (no id field, no response expected).
fn build_notification(http_method : String, params : Json?) -> String {
  let p : Json = match params {
    Some(p) => p
    None => Json::object(Map([]))
  }
  Json::object({
    "jsonrpc": "2.0".to_json(),
    "method": http_method.to_json(),
    "params": p,
  }).stringify()
}

///|
/// Parse a JSON-RPC 2.0 response, returning (id, result_or_error).
/// Returns Err on parse failure or JSON-RPC error field.
fn parse_response(text : String) -> Result[(Int, Json), String] {
  let trimmed = text.trim()
  if trimmed.length() == 0 {
    return Err("Empty response from process")
  }
  let json : Json = @json.parse(trimmed) catch {
    _ => return Err("Invalid JSON in response: \{trimmed}")
  }
  // Extract id
  let id : Int = match json {
    { "id": Number(n, ..), .. } => n.to_int()
    _ => return Err("Missing or invalid 'id' in response")
  }
  // Check for error field
  match json {
    { "error": Object(err_obj), .. } => {
      let code = match err_obj.get("code") {
        Some(Number(n, ..)) => n.to_int().to_string()
        _ => "?"
      }
      let message = match err_obj.get("message") {
        Some(String(s)) => s
        _ => "Unknown error"
      }
      return Err("JSON-RPC error \{code}: \{message}")
    }
    _ => ()
  }
  // Extract result
  let result : Json = match json {
    { "result": r, .. } => r
    _ => Json::object(Map([]))
  }
  Ok((id, result))
}

// ── Native implementation ───────────────────────────────────────────────────

///|
/// Send a JSON-RPC request and wait for the response.
/// Returns the result Json on success, or an error string.
#cfg(target="native")
pub async fn JsonRpcClient::call(
  self : JsonRpcClient,
  http_method : String,
  params : Json,
) -> Result[Json, String] {
  let id = self.id_counter
  self.id_counter = self.id_counter + 1
  let request_str = build_request(id, http_method, Some(params))
  // Send request
  match self.process.write_line(request_str) {
    Ok(_) => ()
    Err(e) => return Err(e)
  }
  // Read response
  let response_line = match self.process.read_line() {
    Ok(line) => line
    Err(e) => return Err(e)
  }
  // Parse response
  let (resp_id, result) = match parse_response(response_line) {
    Ok(pair) => pair
    Err(e) => return Err(e)
  }
  if resp_id != id {
    return Err("Response id mismatch: expected \{id}, got \{resp_id}")
  }
  Ok(result)
}

///|
/// Send a JSON-RPC notification (no response expected).
#cfg(target="native")
pub async fn JsonRpcClient::notify(
  self : JsonRpcClient,
  http_method : String,
  params : Json,
) -> Result[Unit, String] {
  let notif_str = build_notification(http_method, Some(params))
  match self.process.write_line(notif_str) {
    Ok(_) => ()
    Err(e) => return Err(e)
  }
  Ok(())
}

///|
/// Perform the MCP initialize handshake.
/// Sends: initialize request (protocolVersion: "2024-11-05")
/// Then: notifications/initialized notification.
/// Returns the server capabilities from the response.
#cfg(target="native")
pub async fn JsonRpcClient::initialize(
  self : JsonRpcClient,
) -> Result[Json, String] {
  let params : Json = Json::object({
    "protocolVersion": mcp_protocol_version.to_json(),
    "capabilities": Json::object(Map([])),
    "clientInfo": Json::object({
      "name": "MBOpenClacky".to_json(),
      "version": "0.1.0".to_json(),
    }),
  })
  let result = match self.call("initialize", params) {
    Ok(r) => r
    Err(e) => return Err(e)
  }
  // Send initialized notification
  match self.notify("notifications/initialized", Json::object(Map([]))) {
    Ok(_) => ()
    Err(e) => return Err(e)
  }
  Ok(result)
}

// ── WASM fallback stubs ────────────────────────────────────────────────────

///|
/// Send a JSON-RPC request (WASM stub — not supported).
#cfg(any(target="wasm", target="wasm-gc", target="js"))
pub async fn JsonRpcClient::call(
  self : JsonRpcClient,
  http_method : String,
  params : Json,
) -> Result[Json, String] {
  let _ = http_method
  let _ = params
  Err("JSON-RPC not supported on wasm target")
}

///|
/// Send a JSON-RPC notification (WASM stub — not supported).
#cfg(any(target="wasm", target="wasm-gc", target="js"))
pub async fn JsonRpcClient::notify(
  self : JsonRpcClient,
  http_method : String,
  params : Json,
) -> Result[Unit, String] {
  let _ = http_method
  let _ = params
  Err("JSON-RPC not supported on wasm target")
}

///|
/// Perform MCP initialize handshake (WASM stub — not supported).
#cfg(any(target="wasm", target="wasm-gc", target="js"))
pub async fn JsonRpcClient::initialize(
  self : JsonRpcClient,
) -> Result[Json, String] {
  Err("JSON-RPC not supported on wasm target")
}
