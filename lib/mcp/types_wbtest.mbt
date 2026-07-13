///|
/// MCP module tests: JSON-RPC, types, and transport helpers.
test "JsonRpcRequest construction" {
  let req : JsonRpcRequest = {
    jsonrpc: "2.0",
    id: 1,
    rpc_method: "tools/list",
    params: None,
  }
  @debug.assert_eq(req.jsonrpc, "2.0")
  @debug.assert_eq(req.id, 1)
  @debug.assert_eq(req.rpc_method, "tools/list")
  assert_true(req.params is None)
}

///|
test "JsonRpcRequest with params" {
  let params = Json::object({ "name": "test_tool".to_json() })
  let req : JsonRpcRequest = {
    jsonrpc: "2.0",
    id: 42,
    rpc_method: "tools/call",
    params: Some(params),
  }
  @debug.assert_eq(req.id, 42)
  assert_true(req.params is Some(_))
}

///|
test "JsonRpcResponse success parsing" {
  let json_str = "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"tools\":[]}}"
  let json : Json = @json.parse(json_str) catch { _ => return }
  let resp = JsonRpcResponse::from_json(json)
  match resp {
    Some(response) => {
      @debug.assert_eq(response.jsonrpc, "2.0")
      @debug.assert_eq(response.id, Some(1))
      assert_true(response.result is Some(_))
      assert_true(response.error is None)
    }
    None => assert_true(false)
  }
}

///|
test "JsonRpcResponse error parsing" {
  let json_str = "{\"jsonrpc\":\"2.0\",\"id\":2,\"error\":{\"code\":-32601,\"message\":\"Method not found\"}}"
  let json : Json = @json.parse(json_str) catch { _ => return }
  let resp = JsonRpcResponse::from_json(json)
  match resp {
    Some(response) => {
      @debug.assert_eq(response.id, Some(2))
      assert_true(response.result is None)
      match response.error {
        Some(err) => {
          @debug.assert_eq(err.code, -32601)
          @debug.assert_eq(err.message, "Method not found")
        }
        None => assert_true(false)
      }
    }
    None => assert_true(false)
  }
}

///|
test "JsonRpcResponse with data field" {
  let json_str = "{\"jsonrpc\":\"2.0\",\"id\":3,\"error\":{\"code\":-32603,\"message\":\"Internal error\",\"data\":{\"detail\":\"timeout\"}}}"
  let json : Json = @json.parse(json_str) catch { _ => return }
  let resp = JsonRpcResponse::from_json(json)
  match resp {
    Some(response) =>
      match response.error {
        Some(err) => {
          @debug.assert_eq(err.code, -32603)
          assert_true(err.data is Some(_))
        }
        None => assert_true(false)
      }
    None => assert_true(false)
  }
}

///|
test "McpTool parsing" {
  let json_str = "{\"name\":\"read_file\",\"description\":\"Reads a file\",\"inputSchema\":{\"type\":\"object\"}}"
  let json : Json = @json.parse(json_str) catch { _ => return }
  let tool = McpTool::from_json(json)
  match tool {
    Some(t) => {
      @debug.assert_eq(t.name, "read_file")
      @debug.assert_eq(t.description, "Reads a file")
    }
    None => assert_true(false)
  }
}

///|
test "McpTool parsing with input_schema variant" {
  let json_str = "{\"name\":\"search\",\"description\":\"Search web\",\"input_schema\":{\"type\":\"object\"}}"
  let json : Json = @json.parse(json_str) catch { _ => return }
  let tool = McpTool::from_json(json)
  match tool {
    Some(t) => @debug.assert_eq(t.name, "search")
    None => assert_true(false)
  }
}

///|
test "McpServerSpec stdio construction" {
  let spec = McpServerSpec::stdio(
    "test-server",
    "node",
    args=Some(["server.js"]),
    description=Some("Test MCP server"),
  )
  @debug.assert_eq(spec.name, "test-server")
  assert_true(spec.server_type == Stdio)
  match spec.command {
    Some(cmd) => @debug.assert_eq(cmd, "node")
    None => assert_true(false)
  }
  assert_true(spec.url is None)
}

///|
test "McpServerSpec http construction" {
  let spec = McpServerSpec::http(
    "api-server",
    "http://localhost:3000",
    description=Some("HTTP MCP server"),
  )
  @debug.assert_eq(spec.name, "api-server")
  assert_true(spec.server_type == Http)
  assert_true(spec.command is None)
  match spec.url {
    Some(u) => @debug.assert_eq(u, "http://localhost:3000")
    None => assert_true(false)
  }
}

///|
test "McpServerSpec from_json stdio" {
  let json_str = "{\"command\":\"python\",\"args\":[\"-m\",\"server\"],\"env\":{\"DEBUG\":\"1\"}}"
  let json : Json = @json.parse(json_str) catch { _ => return }
  let spec = McpServerSpec::from_json("my-server", json)
  match spec {
    Some(s) => {
      @debug.assert_eq(s.name, "my-server")
      assert_true(s.server_type == Stdio)
      match s.command {
        Some(cmd) => @debug.assert_eq(cmd, "python")
        None => assert_true(false)
      }
    }
    None => assert_true(false)
  }
}

///|
test "McpServerSpec from_json http" {
  let json_str = "{\"url\":\"http://localhost:8080\",\"headers\":{\"Authorization\":\"Bearer token\"}}"
  let json : Json = @json.parse(json_str) catch { _ => return }
  let spec = McpServerSpec::from_json("remote", json)
  match spec {
    Some(s) => {
      assert_true(s.server_type == Http)
      match s.url {
        Some(u) => @debug.assert_eq(u, "http://localhost:8080")
        None => assert_true(false)
      }
    }
    None => assert_true(false)
  }
}

///|
test "McpCapabilities default" {
  let caps : McpCapabilities = { tools: true, prompts: false, resources: false }
  assert_true(caps.tools)
  assert_false(caps.prompts)
  assert_false(caps.resources)
}

///|
test "TransportType equality" {
  let stdio1 = Stdio
  let stdio2 = Stdio
  let http1 = Http
  assert_true(stdio1 == stdio2)
  assert_true(http1 == Http)
  assert_true(stdio1 != http1)
}

///|
test "build_jsonrpc_request without params" {
  let req_str = build_jsonrpc_request(1, "initialize", None)
  let json : Json = @json.parse(req_str) catch { _ => return }
  match json {
    { "jsonrpc": String(ver), "id": Number(id, ..), "method": String(m), .. } => {
      @debug.assert_eq(ver, "2.0")
      @debug.assert_eq(id.to_int(), 1)
      @debug.assert_eq(m, "initialize")
    }
    _ => assert_true(false)
  }
}

///|
test "build_jsonrpc_request with params" {
  let params = Json::object({
    "protocolVersion": "2024-11-05".to_json(),
    "clientInfo": Json::object({
      "name": "test-client".to_json(),
      "version": "1.0.0".to_json(),
    }),
  })
  let req_str = build_jsonrpc_request(2, "initialize", Some(params))
  let json : Json = @json.parse(req_str) catch { _ => return }
  match json {
    {
      "jsonrpc": String(ver),
      "method": String(m),
      "params": { "protocolVersion": String(pv), .. },
      ..
    } => {
      @debug.assert_eq(ver, "2.0")
      @debug.assert_eq(m, "initialize")
      @debug.assert_eq(pv, "2024-11-05")
    }
    _ => assert_true(false)
  }
}

///|
test "parse_jsonrpc_response success" {
  let text = "{\"jsonrpc\":\"2.0\",\"id\":5,\"result\":{\"serverInfo\":{\"name\":\"test\",\"version\":\"1.0\"}}}"
  let resp = parse_jsonrpc_response(text)
  match resp {
    Some(r) => {
      @debug.assert_eq(r.jsonrpc, "2.0")
      @debug.assert_eq(r.id, Some(5))
      assert_true(r.result is Some(_))
    }
    None => assert_true(false)
  }
}

///|
test "parse_jsonrpc_response error" {
  let text = "{\"jsonrpc\":\"2.0\",\"id\":6,\"error\":{\"code\":-32600,\"message\":\"Invalid Request\"}}"
  let resp = parse_jsonrpc_response(text)
  match resp {
    Some(r) => {
      assert_true(r.error is Some(_))
      match r.error {
        Some(err) => @debug.assert_eq(err.code, -32600)
        None => assert_true(false)
      }
    }
    None => assert_true(false)
  }
}

///|
test "parse_jsonrpc_response empty string" {
  let resp = parse_jsonrpc_response("")
  assert_true(resp is None)
}

///|
test "parse_jsonrpc_response invalid json" {
  let resp = parse_jsonrpc_response("not valid json")
  assert_true(resp is None)
}

///|
test "JsonRpcRequest to_json" {
  let req : JsonRpcRequest = {
    jsonrpc: "2.0",
    id: 10,
    rpc_method: "tools/list",
    params: None,
  }
  let json = req.to_json()
  match json {
    { "jsonrpc": String(ver), "id": Number(id, ..), "method": String(m), .. } => {
      @debug.assert_eq(ver, "2.0")
      @debug.assert_eq(id.to_int(), 10)
      @debug.assert_eq(m, "tools/list")
    }
    _ => assert_true(false)
  }
}

///|
test "McpTool to_json roundtrip" {
  let tool : McpTool = {
    name: "test_tool",
    description: "A test tool",
    input_schema: Json::object({ "type": "object".to_json() }),
  }
  let json = tool.to_json()
  match json {
    { "name": String(name), "description": String(desc), .. } => {
      @debug.assert_eq(name, "test_tool")
      @debug.assert_eq(desc, "A test tool")
    }
    _ => assert_true(false)
  }
}

///|
test "TransportError construction" {
  let err : TransportError = TransportError("connection lost")
  match err {
    TransportError(msg) => @debug.assert_eq(msg, "connection lost")
  }
}

///|
test "McpError construction" {
  let err : McpError = McpError("invalid protocol")
  match err {
    McpError(msg) => @debug.assert_eq(msg, "invalid protocol")
  }
}

///|
test "McpServerInfo from_json" {
  let json_str = "{\"serverInfo\":{\"name\":\"test-server\",\"version\":\"2.0\"},\"capabilities\":{\"tools\":{},\"prompts\":{},\"resources\":{}}}"
  let json : Json = @json.parse(json_str) catch { _ => return }
  let info = McpServerInfo::from_json(json)
  match info {
    Some(i) => {
      @debug.assert_eq(i.name, "test-server")
      @debug.assert_eq(i.version, "2.0")
      assert_true(i.capabilities.tools)
      assert_true(i.capabilities.prompts)
      assert_true(i.capabilities.resources)
    }
    None => assert_true(false)
  }
}
