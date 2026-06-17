///| MCP (Model Context Protocol) REST API handlers.

///|
pub(all) struct McpHandlers {}

// ── MCP Server Management ─────────────────────────────────────────

///|
/// GET /api/mcp/servers — List all registered MCP servers.
pub fn handle_mcp_list_servers(request : HttpRequest) -> HttpResponse {
  ignore(request)
  // TODO: Query MCP registry for all registered servers
  let body =
    #|{"servers":[],"total":0}
  HttpResponse::ok(body)
}

///|
/// POST /api/mcp/servers — Register a new MCP server.
pub fn handle_mcp_register_server(request : HttpRequest) -> HttpResponse {
  if request.body == "" {
    return HttpResponse::bad_request("Request body is required")
  }
  // TODO: Parse server config from body and register with MCP registry
  // Expected body: {"name":"...", "url":"...", "transport":"stdio|sse"}
  let body =
    #|{"id":"mcp-server-001","status":"registered","message":"Server registered successfully"}
  HttpResponse::created(body)
}

///|
/// DELETE /api/mcp/servers/:id — Remove a registered MCP server.
pub fn handle_mcp_remove_server(request : HttpRequest) -> HttpResponse {
  let id = match request.get_param("id") {
    Some(v) => v
    None => return HttpResponse::bad_request("Missing parameter: id")
  }
  // TODO: Remove server from MCP registry by id
  ignore(id)
  HttpResponse::no_content()
}

// ── MCP Tool Management ───────────────────────────────────────────

///|
/// GET /api/mcp/tools — List all available MCP tools across servers.
pub fn handle_mcp_list_tools(request : HttpRequest) -> HttpResponse {
  ignore(request)
  // TODO: Aggregate tools from all connected MCP servers
  let body =
    #|{"tools":[],"total":0}
  HttpResponse::ok(body)
}

///|
/// POST /api/mcp/tools/:name/execute — Execute an MCP tool by name.
pub fn handle_mcp_execute_tool(request : HttpRequest) -> HttpResponse {
  let name = match request.get_param("name") {
    Some(v) => v
    None => return HttpResponse::bad_request("Missing parameter: name")
  }
  if request.body == "" {
    return HttpResponse::bad_request(
      "Request body with tool arguments is required",
    )
  }
  // TODO: Find the tool by name across MCP servers and execute
  // Expected body: {"arguments":{...}}
  ignore(name)
  let body =
    #|{"result":null,"status":"executed","tool_name":"unknown"}
  HttpResponse::ok(body)
}
