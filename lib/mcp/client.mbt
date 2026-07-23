///| McpClient: JSON-RPC 2.0 client for MCP protocol communication.

///|
/// MCP protocol version supported.
let mcp_protocol_version : String = "2024-11-05"

///|
/// Default request timeout in seconds.
const DEFAULT_TIMEOUT : Int = 30

///|
/// Initialization handshake timeout in seconds.
const INIT_TIMEOUT : Int = 15

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
/// Sends "initialize" request and "notifications/initialized" notification.
pub fn McpClient::initialize(self : McpClient) -> McpServerInfo raise McpError {
  // Start the transport
  self.transport.start()
  self.started_at = Some(0) // Placeholder: should be current timestamp
  // Build initialize params
  let params : Json = Json::object({
    "protocolVersion": mcp_protocol_version.to_json(),
    "capabilities": Json::object(Map([])),
    "clientInfo": Json::object({
      "name": "MBOpenClacky".to_json(),
      "version": "0.1.0".to_json(),
    }),
  })
  // Send initialize request
  let result = self.send_request("initialize", Some(params))
  // Parse server info from response
  let info = match McpServerInfo::from_json(result) {
    Some(i) => i
    None =>
      raise McpError("Failed to parse server info from initialize response")
  }
  self.server_info = Some(info)
  // Send initialized notification (no id, no response expected)
  let notif_obj : Map[String, Json] = Map([])
  notif_obj["jsonrpc"] = "2.0"
  notif_obj["method"] = "notifications/initialized"
  self.transport.send_message(Json::object(notif_obj).stringify())
  info
}

///|
/// List available tools from the MCP server.
pub fn McpClient::tools_list(self : McpClient) -> Array[McpTool] raise McpError {
  let result = self.send_request("tools/list", None)
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
pub fn McpClient::call_tool(
  self : McpClient,
  tool_name : String,
  arguments : Json,
) -> Json raise McpError {
  let params : Json = Json::object({
    "name": tool_name.to_json(),
    "arguments": arguments,
  })
  self.send_request("tools/call", Some(params))
}

///|
/// Send a JSON-RPC request and return the result.
fn McpClient::send_request(
  self : McpClient,
  http_method : String,
  params : Json?,
) -> Json raise McpError {
  let id = self.next_id
  self.next_id += 1
  self.last_used_at = Some(0) // Placeholder: should be current timestamp
  // Build and send the request
  let request_str = build_jsonrpc_request(id, http_method, params)
  self.transport.send_message(request_str)
  // In a real implementation, we would wait for the response asynchronously.
  // For now, this is a synchronous placeholder that would be filled in
  // with the actual response handling logic (e.g., using callbacks or async).
  // TODO: Implement actual response correlation by request ID
  // For testing purposes, we return a placeholder that indicates the request was sent.
  // The actual response would come through the transport's on_message handler.
  raise McpError(
    "Response handling requires async runtime (method: " +
    http_method +
    ", id: " +
    id.to_string() +
    ")",
  )
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
  self.last_used_at = Some(0)
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
