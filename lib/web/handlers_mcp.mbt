///| MCP (Model Context Protocol) REST API handlers.
///  Real implementations backed by @mcp.McpRegistry.

// ── MCP Server Management ─────────────────────────────────────────

///|
/// GET /api/mcp/servers — List all registered MCP servers.
pub fn handle_mcp_list_servers(
  registry : @mcp.McpRegistry,
  request : HttpRequest,
) -> HttpResponse {
  ignore(request)
  let servers_arr : Array[Json] = []
  registry.specs.each(fn(name, spec) {
    let transport_str = match spec.server_type {
      Stdio => "stdio"
      Http => "http"
    }
    let status = match registry.clients.get(name) {
      Some(client) =>
        if client.is_connected() {
          "connected"
        } else {
          "disconnected"
        }
      None => "registered"
    }
    let fields : Map[String, Json] = {
      "id": name.to_json(),
      "name": name.to_json(),
      "transport": transport_str.to_json(),
      "status": status.to_json(),
    }
    match spec.command {
      Some(cmd) => fields["command"] = cmd.to_json()
      None => ()
    }
    match spec.args {
      Some(args) => fields["args"] = args.to_json()
      None => ()
    }
    match spec.url {
      Some(url) => fields["url"] = url.to_json()
      None => ()
    }
    servers_arr.push(Json::object(fields))
  })
  let total = servers_arr.length()
  let body = Json::object({
    "servers": Json::array(servers_arr),
    "total": total.to_json(),
  }).stringify()
  HttpResponse::ok(body)
}

///|
/// POST /api/mcp/servers — Register a new MCP server.
pub fn handle_mcp_register_server(
  registry : @mcp.McpRegistry,
  request : HttpRequest,
) -> HttpResponse {
  if request.body == "" {
    return HttpResponse::bad_request("Request body is required")
  }
  let json : Json = @json.parse(request.body) catch {
    _ => return HttpResponse::bad_request("Invalid JSON body")
  }
  let name : String = match json {
    { "name": String(n), .. } => n
    _ => return HttpResponse::bad_request("Missing required field: name")
  }
  let transport : String = match json {
    { "transport": String(t), .. } => t
    _ => "stdio"
  }
  let spec : @mcp.McpServerSpec = if transport == "http" {
    let url : String = match json {
      { "url": String(u), .. } => u
      _ =>
        return HttpResponse::bad_request(
          "Missing required field: url for HTTP transport",
        )
    }
    @mcp.McpServerSpec::http(name, url)
  } else {
    let command : String = match json {
      { "command": String(c), .. } => c
      _ =>
        return HttpResponse::bad_request(
          "Missing required field: command for Stdio transport",
        )
    }
    let args : Array[String]? = match json {
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
    @mcp.McpServerSpec::stdio(name, command, args~)
  }
  registry.add_server(name, spec)
  let body = Json::object({
    "id": name.to_json(),
    "status": "registered".to_json(),
    "message": "Server registered successfully".to_json(),
  }).stringify()
  HttpResponse::created(body)
}

///|
/// DELETE /api/mcp/servers/:id — Remove a registered MCP server.
pub fn handle_mcp_remove_server(
  registry : @mcp.McpRegistry,
  request : HttpRequest,
) -> HttpResponse {
  let id = match request.get_param("id") {
    Some(v) => v
    None => return HttpResponse::bad_request("Missing parameter: id")
  }
  match registry.specs.get(id) {
    Some(_) => {
      registry.remove_server(id)
      HttpResponse::no_content()
    }
    None => HttpResponse::not_found("MCP server not found: " + id)
  }
}

// ── MCP Tool Management ───────────────────────────────────────────

///|
/// GET /api/mcp/tools — List all available MCP tools across servers.
pub fn handle_mcp_list_tools(
  registry : @mcp.McpRegistry,
  request : HttpRequest,
) -> HttpResponse {
  ignore(request)
  let tools_arr : Array[Json] = []
  registry.specs.each(fn(name, _spec) {
    match registry.get_client(name) {
      Some(client) =>
        for tool in client.tools {
          let fields : Map[String, Json] = {
            "name": tool.name.to_json(),
            "description": tool.description.to_json(),
            "server": name.to_json(),
          }
          tools_arr.push(Json::object(fields))
        }
      None => ()
    }
  })
  let total = tools_arr.length()
  let body = Json::object({
    "tools": Json::array(tools_arr),
    "total": total.to_json(),
  }).stringify()
  HttpResponse::ok(body)
}

///|
/// POST /api/mcp/tools/:name/execute — Execute an MCP tool by name.
pub fn handle_mcp_execute_tool(
  registry : @mcp.McpRegistry,
  request : HttpRequest,
) -> HttpResponse {
  let name = match request.get_param("name") {
    Some(v) => v
    None => return HttpResponse::bad_request("Missing parameter: name")
  }
  if request.body == "" {
    return HttpResponse::bad_request(
      "Request body with tool arguments is required",
    )
  }
  let body_json : Json = @json.parse(request.body) catch {
    _ => return HttpResponse::bad_request("Invalid JSON body")
  }
  let arguments : Json = match body_json {
    { "arguments": args, .. } => args
    _ => Json::object({})
  }
  // Find the server that provides this tool and execute it
  let mut result_json : Json? = None
  let mut error_msg : String? = None
  registry.specs.each(fn(server_name, _spec) {
    if result_json is Some(_) {
      return ()
    }
    match registry.get_client(server_name) {
      Some(client) => {
        let has_tool = client.tools.any(fn(t) { t.name == name })
        if has_tool {
          let result = registry.call_tool(server_name, name, arguments) catch {
            @mcp.McpError(msg) => {
              error_msg = Some(msg)
              Json::null()
            }
          }
          result_json = Some(result)
        }
      }
      None => ()
    }
  })
  match result_json {
    Some(result) => {
      let body = Json::object({
        "result": result,
        "status": "executed".to_json(),
        "tool_name": name.to_json(),
      }).stringify()
      HttpResponse::ok(body)
    }
    None =>
      match error_msg {
        Some(msg) => HttpResponse::bad_request("Tool execution failed: " + msg)
        None => HttpResponse::not_found("Tool not found: " + name)
      }
  }
}
