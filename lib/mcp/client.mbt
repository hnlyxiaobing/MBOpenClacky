///| McpClient: JSON-RPC 2.0 client for MCP protocol communication.

///|
/// MCP protocol version supported.
let mcp_protocol_version : String = "2024-11-05"

///|
/// Default request timeout in seconds.
const DEFAULT_TIMEOUT : Int = 30

///|
/// Initialization handshake timeout in seconds. Generous default: npx/uvx
/// based servers can take tens of seconds to boot (spec risk table).
const INIT_TIMEOUT : Int = 60

///|
/// JSON-RPC 2.0 client for communicating with an MCP server.
pub(all) struct McpClient {
  name : String
  transport : &Transport
  mut tools : Array[McpTool]
  mut server_info : McpServerInfo?
  mut started_at : Int?
  mut last_used_at : Int?
  mut next_id : Int
  timeout_s : Int
}

///|
/// Create a new McpClient with the given name and transport.
pub fn McpClient::new(name : String, transport : &Transport) -> McpClient {
  {
    name,
    transport,
    tools: [],
    server_info: None,
    started_at: None,
    last_used_at: None,
    next_id: 1,
    timeout_s: DEFAULT_TIMEOUT,
  }
}

///|
/// Factory method: create an McpClient from a server spec.
/// Automatically selects the appropriate transport based on server_type.
pub fn McpClient::from_spec(spec : McpServerSpec) -> McpClient {
  match spec.server_type {
    Stdio => McpClient::new(spec.name, StdioTransport::new(spec))
    Http => McpClient::new(spec.name, HttpTransport::new(spec))
  }
}

///|
/// Initialize the MCP connection (protocol handshake).
/// Starts the transport, sends the "initialize" request, then the
/// "notifications/initialized" notification. On any failure the transport
/// is stopped so no half-connected state survives (spec decision 3).
pub async fn McpClient::initialize(
  self : McpClient,
) -> McpServerInfo raise McpError {
  if !self.transport.alive() {
    let start_result : Result[Unit, String] = self.transport.start() catch {
      _ => Err("Transport start was cancelled")
    }
    match start_result {
      Ok(_) => ()
      Err(e) => raise McpError("Failed to start MCP transport: " + e)
    }
  }
  self.started_at = Some(@utils.now_seconds())
  self.last_used_at = Some(@utils.now_seconds())
  // Build initialize params
  let params : Json = Json::object({
    "protocolVersion": mcp_protocol_version.to_json(),
    "capabilities": Json::object(Map([])),
    "clientInfo": Json::object({
      "name": "MBOpenClacky".to_json(),
      "version": "0.1.0".to_json(),
    }),
  })
  // Any failure past this point leaves a half-open connection: stop the
  // transport before propagating the error (spec decision 3).
  errdefer self.disconnect()
  // Send initialize request (handshake timeout)
  let result = self.send_request("initialize", Some(params), INIT_TIMEOUT)
  // Parse server info from response
  let info = match McpServerInfo::from_json(result) {
    Some(i) => i
    None =>
      raise McpError("Failed to parse server info from initialize response")
  }
  self.server_info = Some(info)
  // Send initialized notification (no id, no response expected)
  let notif = build_jsonrpc_notification("notifications/initialized")
  let send_result : Result[Unit, String] = self.transport.send_message(notif) catch {
    _ => Err("Transport send was cancelled")
  }
  match send_result {
    Ok(_) => ()
    Err(e) => raise McpError("Failed to send initialized notification: " + e)
  }
  info
}

///|
/// List available tools from the MCP server.
pub async fn McpClient::tools_list(
  self : McpClient,
) -> Array[McpTool] raise McpError {
  let result = self.send_request("tools/list", None, self.timeout_s)
  let tools : Array[McpTool] = []
  match result {
    { "tools": Array(arr), .. } =>
      for item in arr {
        match McpTool::from_json(item) {
          Some(tool) => tools.push(tool)
          None => continue
        }
      }
    _ => ()
  }
  self.tools = tools
  tools
}

///|
/// Call a tool on the MCP server.
pub async fn McpClient::call_tool(
  self : McpClient,
  tool_name : String,
  arguments : Json,
) -> Json raise McpError {
  let params : Json = Json::object({
    "name": tool_name.to_json(),
    "arguments": arguments,
  })
  self.send_request("tools/call", Some(params), self.timeout_s)
}

///|
/// Send a JSON-RPC request and return the result. The transport
/// correlates the response by request id; errors and timeouts surface
/// as McpError.
async fn McpClient::send_request(
  self : McpClient,
  http_method : String,
  params : Json?,
  timeout_s : Int,
) -> Json raise McpError {
  let id = self.next_id
  self.next_id += 1
  self.last_used_at = Some(@utils.now_seconds())
  // Build and send the request
  let request_str = build_jsonrpc_request(id, http_method, params)
  let transport_result : Result[String, String] = self.transport.send_request(
    id, request_str, timeout_s,
  ) catch {
    _ => Err("Transport request was cancelled")
  }
  let line = match transport_result {
    Ok(l) => l
    Err(e) => raise McpError(e)
  }
  // Parse the correlated response
  match parse_jsonrpc_response(line) {
    None =>
      raise McpError(
        "Invalid JSON-RPC response for \{http_method} (id: \{id.to_string()})",
      )
    Some(resp) =>
      match resp.error {
        Some(err) =>
          raise McpError(
            "RPC error " + err.code.to_string() + ": " + err.message,
          )
        None =>
          match resp.result {
            Some(r) => r
            None => Json::null()
          }
      }
  }
}

///|
/// Send a request and process a pre-received response (for testing).
/// This simulates the full request-response cycle with a known response.
pub fn McpClient::send_request_with_response(
  self : McpClient,
  http_method : String,
  params : Json?,
  response_text : String,
) -> Json raise McpError {
  let id = self.next_id
  self.next_id += 1
  self.last_used_at = Some(@utils.now_seconds())
  let request_str = build_jsonrpc_request(id, http_method, params)
  ignore(request_str)
  // Parse the provided response
  match parse_jsonrpc_response(response_text) {
    Some(resp) =>
      match resp.error {
        Some(err) =>
          raise McpError(
            "RPC error " + err.code.to_string() + ": " + err.message,
          )
        None =>
          match resp.result {
            Some(r) => r
            None => Json::null()
          }
      }
    None =>
      raise McpError("Failed to parse response for method: " + http_method)
  }
}

///|
/// Get the protocol version.
pub fn McpClient::protocol_version(_self : McpClient) -> String {
  mcp_protocol_version
}

///|
/// Get the default timeout.
pub fn McpClient::default_timeout(_self : McpClient) -> Int {
  DEFAULT_TIMEOUT
}

///|
/// Get the init timeout.
pub fn McpClient::init_timeout(_self : McpClient) -> Int {
  INIT_TIMEOUT
}

///|
/// Check if the client is connected.
pub fn McpClient::is_connected(self : McpClient) -> Bool {
  self.transport.alive()
}

///|
/// Disconnect the client.
pub fn McpClient::disconnect(self : McpClient) -> Unit {
  self.transport.stop()
  self.server_info = None
  self.tools = []
}
