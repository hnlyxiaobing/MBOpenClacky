///| MCP (Model Context Protocol) REST API handlers.
///  Real implementations backed by @mcp.McpRegistry.

// ── MCP Server Management (new spec endpoints) ──────────────────────

///|
/// GET /api/mcp — List all registered MCP servers.
/// Returns { configured, config_exists, config_path, servers: [...] }
pub fn handle_mcp_list_servers(
  registry : @mcp.McpRegistry,
  request : HttpRequest,
) -> HttpResponse {
  ignore(request)
  let configured = registry.spec_count() > 0
  let config_exists = registry.config_path is Some(_)
  let config_path = match registry.config_path {
    Some(p) => p
    None => ""
  }
  let servers_arr : Array[Json] = []
  registry.specs.each(fn(name, spec) {
    let type_str = match spec.server_type {
      Stdio => "stdio"
      Http => "http"
    }
    let status_str = match registry.clients.get(name) {
      Some(client) =>
        if client.is_connected() {
          "connected"
        } else {
          "disconnected"
        }
      None => "registered"
    }
    let disabled = not(registry.is_enabled(name))
    let fields : Map[String, Json] = {
      "name": name.to_json(),
      "type": type_str.to_json(),
      "disabled": disabled.to_json(),
      "status": status_str.to_json(),
      "tools": Json::array([]),
    }
    match spec.description {
      Some(d) => fields["description"] = d.to_json()
      None => ()
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
  let body = Json::object({
    "configured": configured.to_json(),
    "config_exists": config_exists.to_json(),
    "config_path": config_path.to_json(),
    "servers": Json::array(servers_arr),
  }).stringify()
  HttpResponse::ok(body)
}

///|
/// POST /api/mcp — Add a new MCP server.
pub fn handle_mcp_add_server(
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
    let headers : Map[String, String]? = match json {
      { "headers": Object(entries), .. } => {
        let result : Map[String, String] = {}
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
    let description : String? = match json {
      { "description": String(d), .. } => Some(d)
      _ => None
    }
    @mcp.McpServerSpec::http(name, url, headers~, description~)
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
    let env : Map[String, String]? = match json {
      { "env": Object(entries), .. } => {
        let result : Map[String, String] = {}
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
    let cwd : String? = match json {
      { "cwd": String(c), .. } => Some(c)
      _ => None
    }
    let description : String? = match json {
      { "description": String(d), .. } => Some(d)
      _ => None
    }
    @mcp.McpServerSpec::stdio(name, command, args~, env~, cwd~, description~)
  }
  registry.add_server(name, spec)
  let body = Json::object({
    "name": name.to_json(),
    "type": transport.to_json(),
    "status": "registered".to_json(),
    "ok": true.to_json(),
    "message": "Server registered successfully".to_json(),
  }).stringify()
  HttpResponse::created(body)
}

///|
/// POST /api/mcp/:name/probe — Probe server connectivity and return tools.
pub fn handle_mcp_probe_server(
  registry : @mcp.McpRegistry,
  request : HttpRequest,
) -> HttpResponse {
  let name = match request.get_param("name") {
    Some(v) => v
    None => return HttpResponse::bad_request("Missing parameter: name")
  }
  match registry.specs.get(name) {
    Some(_spec) => {
      // Validate spec completeness
      let _valid = match _spec.server_type {
        Stdio => _spec.command is Some(_)
        Http => _spec.url is Some(_)
      }
      // Try to create client and list tools
      match registry.get_client(name) {
        Some(client) =>
          match client.is_connected() {
            true => {
              // Check existing tools from client
              let tools_arr : Array[Json] = []
              for tool in client.tools {
                let fields : Map[String, Json] = {
                  "name": tool.name.to_json(),
                  "description": tool.description.to_json(),
                }
                tools_arr.push(Json::object(fields))
              }
              let body = Json::object({
                "ok": true.to_json(),
                "tools": Json::array(tools_arr),
              }).stringify()
              HttpResponse::ok(body)
            }
            false => {
              let body = Json::object({
                "ok": false.to_json(),
                "error": "Server not connected".to_json(),
              }).stringify()
              HttpResponse::ok(body)
            }
          }
        None => {
          let body = Json::object({
            "ok": false.to_json(),
            "error": "Failed to create client for server".to_json(),
          }).stringify()
          HttpResponse::ok(body)
        }
      }
    }
    None => HttpResponse::not_found("MCP server not found: " + name)
  }
}

///|
/// PATCH /api/mcp/:name/enabled — Enable or disable an MCP server.
pub fn handle_mcp_toggle_server(
  registry : @mcp.McpRegistry,
  request : HttpRequest,
) -> HttpResponse {
  let name = match request.get_param("name") {
    Some(v) => v
    None => return HttpResponse::bad_request("Missing parameter: name")
  }
  match registry.specs.get(name) {
    Some(_) => {
      if request.body == "" {
        return HttpResponse::bad_request(
          "Request body with enabled field is required",
        )
      }
      let json : Json = @json.parse(request.body) catch {
        _ => return HttpResponse::bad_request("Invalid JSON body")
      }
      let enabled : Bool = match json {
        { "enabled": True, .. } => true
        { "enabled": False, .. } => false
        _ =>
          return HttpResponse::bad_request(
            "Missing required field: enabled (boolean)",
          )
      }
      registry.set_enabled(name, enabled)
      let body = Json::object({ "ok": true.to_json() }).stringify()
      HttpResponse::ok(body)
    }
    None => HttpResponse::not_found("MCP server not found: " + name)
  }
}

///|
/// PUT /api/mcp/:name — Update an MCP server's configuration.
pub fn handle_mcp_update_server(
  registry : @mcp.McpRegistry,
  request : HttpRequest,
) -> HttpResponse {
  let name = match request.get_param("name") {
    Some(v) => v
    None => return HttpResponse::bad_request("Missing parameter: name")
  }
  match registry.specs.get(name) {
    Some(_existing) => {
      if request.body == "" {
        return HttpResponse::bad_request("Request body is required")
      }
      let json : Json = @json.parse(request.body) catch {
        _ => return HttpResponse::bad_request("Invalid JSON body")
      }
      match @mcp.McpServerSpec::from_json(name, json) {
        Some(spec) => {
          // Remove old client if exists
          match registry.clients.get(name) {
            Some(client) => client.disconnect()
            None => ()
          }
          registry.clients.remove(name) |> ignore
          // Update spec while preserving enabled state
          let was_enabled = registry.is_enabled(name)
          registry.specs[name] = spec
          registry.enabled[name] = was_enabled
          let body = Json::object({
            "ok": true.to_json(),
            "name": name.to_json(),
            "message": "Server updated successfully".to_json(),
          }).stringify()
          HttpResponse::ok(body)
        }
        None => HttpResponse::bad_request("Invalid server specification")
      }
    }
    None => HttpResponse::not_found("MCP server not found: " + name)
  }
}

///|
/// DELETE /api/mcp/:name — Remove a registered MCP server.
pub fn handle_mcp_remove_server(
  registry : @mcp.McpRegistry,
  request : HttpRequest,
) -> HttpResponse {
  let name = match request.get_param("name") {
    Some(v) => v
    None => return HttpResponse::bad_request("Missing parameter: name")
  }
  match registry.specs.get(name) {
    Some(_) => {
      registry.remove_server(name)
      let body = Json::object({ "ok": true.to_json() }).stringify()
      HttpResponse::ok(body)
    }
    None => HttpResponse::not_found("MCP server not found: " + name)
  }
}

///|
/// GET /api/mcp/:name/tools — List tools for a specific MCP server.
pub fn handle_mcp_list_server_tools(
  registry : @mcp.McpRegistry,
  request : HttpRequest,
) -> HttpResponse {
  let name = match request.get_param("name") {
    Some(v) => v
    None => return HttpResponse::bad_request("Missing parameter: name")
  }
  match registry.get_client(name) {
    Some(client) => {
      let tools_arr : Array[Json] = []
      for tool in client.tools {
        let fields : Map[String, Json] = {
          "name": tool.name.to_json(),
          "description": tool.description.to_json(),
          "server": name.to_json(),
        }
        tools_arr.push(Json::object(fields))
      }
      let body = Json::object({
        "server": name.to_json(),
        "tools": Json::array(tools_arr),
        "total": tools_arr.length().to_json(),
      }).stringify()
      HttpResponse::ok(body)
    }
    None => HttpResponse::not_found("MCP server not found: " + name)
  }
}

///|
/// POST /api/mcp/:name/call — Call a tool on a specific MCP server.
pub fn handle_mcp_call_server_tool(
  registry : @mcp.McpRegistry,
  request : HttpRequest,
) -> HttpResponse {
  let name = match request.get_param("name") {
    Some(v) => v
    None => return HttpResponse::bad_request("Missing parameter: name")
  }
  match registry.specs.get(name) {
    Some(_) => {
      if request.body == "" {
        return HttpResponse::bad_request(
          "Request body with tool_name and arguments is required",
        )
      }
      let body_json : Json = @json.parse(request.body) catch {
        _ => return HttpResponse::bad_request("Invalid JSON body")
      }
      let tool_name : String = match body_json {
        { "tool_name": String(t), .. } => t
        _ =>
          return HttpResponse::bad_request("Missing required field: tool_name")
      }
      let arguments : Json = match body_json {
        { "arguments": args, .. } => args
        _ => Json::object({})
      }
      let result = registry.call_tool(name, tool_name, arguments) catch {
        @mcp.McpError(msg) =>
          return HttpResponse::bad_request("Tool execution failed: " + msg)
      }
      let body = Json::object({
        "result": result,
        "server": name.to_json(),
        "tool_name": tool_name.to_json(),
      }).stringify()
      HttpResponse::ok(body)
    }
    None => HttpResponse::not_found("MCP server not found: " + name)
  }
}

// ── MCP Global Tool Management (legacy endpoints) ───────────────────

///|
/// GET /api/mcp/tools — List all available MCP tools across all servers.
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
/// POST /api/mcp/tools/:name/execute — Execute an MCP tool by name (across all servers).
pub fn handle_mcp_execute_tool(
  registry : @mcp.McpRegistry,
  request : HttpRequest,
) -> HttpResponse {
  let tool_name = match request.get_param("name") {
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
        let has_tool = client.tools.any(fn(t) { t.name == tool_name })
        if has_tool {
          let result = registry.call_tool(server_name, tool_name, arguments) catch {
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
        "tool_name": tool_name.to_json(),
      }).stringify()
      HttpResponse::ok(body)
    }
    None =>
      match error_msg {
        Some(msg) => HttpResponse::bad_request("Tool execution failed: " + msg)
        None => HttpResponse::not_found("Tool not found: " + tool_name)
      }
  }
}
