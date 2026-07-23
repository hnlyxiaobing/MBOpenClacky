///| MCP Protocol data types.

///|
/// Transport type for MCP server connection.
pub(all) enum TransportType {
  Stdio
  Http
} derive(Eq, Debug, ToJson)

///|
/// Specification for an MCP server connection.
pub(all) struct McpServerSpec {
  name : String
  server_type : TransportType
  command : String?
  url : String?
  args : Array[String]?
  env : Map[String, String]?
  cwd : String?
  description : String?
  headers : Map[String, String]?
} derive(Eq, Debug, ToJson)

///|
/// An MCP tool exposed by a server.
pub(all) struct McpTool {
  name : String
  description : String
  input_schema : Json
} derive(Eq, Debug, ToJson)

///|
/// JSON-RPC 2.0 request structure.
pub(all) struct JsonRpcRequest {
  jsonrpc : String
  id : Int
  rpc_method : String
  params : Json?
} derive(Eq, Debug)

///|
/// Serialize to a JSON-RPC 2.0 compliant object.
/// Note: the MoonBit field `rpc_method` maps to the spec key `"method"`,
/// and `params` is omitted when `None` (per JSON-RPC 2.0 which allows
/// requests with no params member).
pub fn JsonRpcRequest::to_json(self : JsonRpcRequest) -> Json {
  let fields : Map[String, Json] = {
    "jsonrpc": self.jsonrpc.to_json(),
    "id": self.id.to_json(),
    "method": self.rpc_method.to_json(),
  }
  match self.params {
    Some(p) => fields["params"] = p
    None => ()
  }
  Json::object(fields)
}

///|
/// JSON-RPC 2.0 response structure.
pub(all) struct JsonRpcResponse {
  jsonrpc : String
  id : Int?
  result : Json?
  error : JsonRpcError?
} derive(Eq, Debug, ToJson)

///|
/// JSON-RPC 2.0 error object.
pub(all) struct JsonRpcError {
  code : Int
  message : String
  data : Json?
} derive(Eq, Debug, ToJson)

///|
/// Capabilities advertised by an MCP server.
pub(all) struct McpCapabilities {
  tools : Bool
  prompts : Bool
  resources : Bool
} derive(Eq, Debug, ToJson)

///|
/// Information about a connected MCP server.
pub(all) struct McpServerInfo {
  name : String
  version : String
  capabilities : McpCapabilities
} derive(Eq, Debug, ToJson)

///|
/// Error during transport-level operations.
pub(all) suberror TransportError {
  TransportError(String)
} derive(ToJson, Debug)

///|
/// Error during MCP protocol operations.
pub(all) suberror McpError {
  McpError(String)
} derive(ToJson, Debug)

///|
/// Create a default McpServerSpec for stdio transport.
pub fn McpServerSpec::stdio(
  name : String,
  command : String,
  args? : Array[String]? = None,
  env? : Map[String, String]? = None,
  cwd? : String? = None,
  description? : String? = None,
) -> McpServerSpec {
  {
    name,
    server_type: Stdio,
    command: Some(command),
    url: None,
    args,
    env,
    cwd,
    description,
    headers: None,
  }
}

///|
/// Create a default McpServerSpec for HTTP transport.
pub fn McpServerSpec::http(
  name : String,
  url : String,
  headers? : Map[String, String]? = None,
  description? : String? = None,
) -> McpServerSpec {
  {
    name,
    server_type: Http,
    command: None,
    url: Some(url),
    args: None,
    env: None,
    cwd: None,
    description,
    headers,
  }
}

///|
/// Parse a JsonRpcResponse from a Json value.
pub fn JsonRpcResponse::from_json(json : Json) -> JsonRpcResponse? {
  match json {
    { "jsonrpc": String(ver), .. } => {
      let id : Int? = match json {
        { "id": Number(n, ..), .. } => Some(n.to_int())
        _ => None
      }
      let result : Json? = match json {
        { "result": r, .. } => Some(r)
        _ => None
      }
      let error : JsonRpcError? = match json {
        {
          "error": { "code": Number(code, ..), "message": String(msg), .. } as err,
          ..
        } => {
          let data : Json? = match err {
            { "data": d, .. } => Some(d)
            _ => None
          }
          Some({ code: code.to_int(), message: msg, data })
        }
        _ => None
      }
      Some({ jsonrpc: ver, id, result, error })
    }
    _ => None
  }
}

///|
/// Parse an McpTool from a Json value.
pub fn McpTool::from_json(json : Json) -> McpTool? {
  match json {
    { "name": String(name), "description": String(desc), .. } => {
      let schema : Json = match json {
        { "inputSchema": s, .. } => s
        { "input_schema": s, .. } => s
        _ => Json::null()
      }
      Some({ name, description: desc, input_schema: schema })
    }
    _ => None
  }
}

///|
/// Parse McpServerInfo from a Json value (initialize response result).
pub fn McpServerInfo::from_json(json : Json) -> McpServerInfo? {
  match json {
    { "serverInfo": { "name": String(name), "version": String(ver), .. }, .. } => {
      let caps = match json {
        { "capabilities": c, .. } => parse_capabilities(c)
        _ => { tools: false, prompts: false, resources: false }
      }
      Some({ name, version: ver, capabilities: caps })
    }
    _ => None
  }
}

///|
/// Parse capabilities from a Json value.
fn parse_capabilities(json : Json) -> McpCapabilities {
  let tools = match json {
    { "tools": _, .. } => true
    _ => false
  }
  let prompts = match json {
    { "prompts": _, .. } => true
    _ => false
  }
  let resources = match json {
    { "resources": _, .. } => true
    _ => false
  }
  { tools, prompts, resources }
}

///|
/// Parse McpServerSpec from a Json value.
pub fn McpServerSpec::from_json(name : String, json : Json) -> McpServerSpec? {
  match json {
    { .. } as obj => {
      let server_type = match obj {
        { "url": String(_), .. } => Http
        _ => Stdio
      }
      let command : String? = match obj {
        { "command": String(cmd), .. } => Some(cmd)
        _ => None
      }
      let url : String? = match obj {
        { "url": String(u), .. } => Some(u)
        _ => None
      }
      let args : Array[String]? = match obj {
        { "args": Array(arr), .. } => {
          let result : Array[String] = []
          for item in arr {
            match item {
              String(s) => result.push(s)
              _ => ()
            }
          }
          Some(result)
        }
        _ => None
      }
      let env : Map[String, String]? = match obj {
        { "env": Object(entries), .. } => {
          let result : Map[String, String] = Map([])
          entries.each(fn(k, v) {
            match v {
              String(s) => result[k] = s
              _ => ()
            }
          })
          Some(result)
        }
        _ => None
      }
      let cwd : String? = match obj {
        { "cwd": String(c), .. } => Some(c)
        _ => None
      }
      let description : String? = match obj {
        { "description": String(d), .. } => Some(d)
        _ => None
      }
      let headers : Map[String, String]? = match obj {
        { "headers": Object(entries), .. } => {
          let result : Map[String, String] = Map([])
          entries.each(fn(k, v) {
            match v {
              String(s) => result[k] = s
              _ => ()
            }
          })
          Some(result)
        }
        _ => None
      }
      Some({
        name,
        server_type,
        command,
        url,
        args,
        env,
        cwd,
        description,
        headers,
      })
    }
    _ => None
  }
}
