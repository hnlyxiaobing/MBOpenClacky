///| stdio MCP server for the `mcp` subcommand.
///
/// Ruby's `clacky mcp` exposes this CLI as a stdio MCP server so external
/// toolchains (editors, orchestrators) can drive it over JSON-RPC on
/// stdin/stdout.
///
/// Spike result (plan #10): reading our own piped stdin IS possible without
/// FFI — `moonbitlang/async/stdio` exposes `stdin`/`stdout` as an
/// `@io.Reader`/`@io.Writer`, so this serves JSON-RPC directly instead of
/// reporting an unavailable capability.

///|
/// MCP protocol version advertised on `initialize`.
let mcp_protocol_version : String = "2024-11-05"

///|
/// JSON-RPC error object.
fn mcp_error(code : Int, message : String) -> Json {
  Json::object({
    "code": code.to_json(),
    "message": message.to_json(),
  })
}

///|
/// Extract the `id` of a request. Missing/null ids mark notifications, which
/// must not be answered.
fn mcp_request_id(req : Json) -> Json? {
  match req {
    Object(obj) =>
      match obj.get("id") {
        // A JSON null id marks a notification: answer nothing.
        Some(id) => if id.stringify() == "null" { None } else { Some(id) }
        None => None
      }
    _ => None
  }
}

///|
/// `initialize` — protocol version, tool capability, server identity.
fn mcp_initialize_result() -> Json {
  Json::object({
    "protocolVersion": mcp_protocol_version.to_json(),
    "capabilities": Json::object({
      "tools": Json::object({ "listChanged": false.to_json() }),
    }),
    "serverInfo": Json::object({
      "name": "mbopenclacky".to_json(),
      "version": VERSION.to_json(),
    }),
  })
}

///|
/// `tools/list` — every tool in the default registry, in MCP shape
/// (`inputSchema` is the same JSON-Schema object the model sees).
fn mcp_tools_list_result(registry : @tool.ToolRegistry) -> Json {
  let tools : Array[Json] = []
  for def in registry.all_definitions() {
    tools.push(
      Json::object({
        "name": def.function.name.to_json(),
        "description": def.function.description.to_json(),
        "inputSchema": def.function.parameters,
      }),
    )
  }
  Json::object({ "tools": Json::array(tools) })
}

///|
/// `tools/call` — execute a registered tool and wrap its result in the MCP
/// content envelope. Unknown tools and tool errors are reported as tool
/// results with `isError: true` (per the MCP spec), not as JSON-RPC errors.
async fn mcp_tools_call_result(
  registry : @tool.ToolRegistry,
  params : Json,
) -> Json {
  let (name, arguments) = match params {
    Object(obj) => {
      let name = match obj.get("name") {
        Some(String(n)) => n
        _ => ""
      }
      let args = match obj.get("arguments") {
        Some(Object(a)) => a
        _ => Map([])
      }
      (name, args)
    }
    _ => ("", Map([]))
  }
  if name.is_empty() {
    return mcp_tool_error("Missing required parameter: name")
  }
  match registry.get_resolved(name) {
    None => mcp_tool_error("Unknown tool: " + name)
    Some(tool) => {
      let result = tool.execute(arguments) catch {
        _ => @tool.ToolResult::{ content: "Tool execution failed", is_error: true }
      }
      Json::object({
        "content": Json::array([
          Json::object({
            "type": "text".to_json(),
            "text": result.content.to_json(),
          }),
        ]),
        "isError": result.is_error.to_json(),
      })
    }
  }
}

///|
/// A tool-level failure rendered as an MCP tool result.
fn mcp_tool_error(message : String) -> Json {
  Json::object({
    "content": Json::array([
      Json::object({ "type": "text".to_json(), "text": message.to_json() }),
    ]),
    "isError": true.to_json(),
  })
}

///|
/// Dispatch one JSON-RPC request. Returns the response object, or None for
/// notifications (no `id`) which must not be answered.
async fn mcp_dispatch(
  registry : @tool.ToolRegistry,
  req : Json,
) -> Json? {
  let id = mcp_request_id(req)
  let (method_name, params) = match req {
    Object(obj) => {
      let method_name = match obj.get("method") {
        Some(String(m)) => m
        _ => ""
      }
      let params = match obj.get("params") {
        Some(p) => p
        None => Json::object(Map([]))
      }
      (method_name, params)
    }
    _ => ("", Json::object(Map([])))
  }
  let response_id = match id {
    Some(v) => v
    None => return None
  }
  let base : Map[String, Json] = Map([])
  base.set("jsonrpc", "2.0".to_json())
  base.set("id", response_id)
  match method_name {
    "initialize" => {
      base.set("result", mcp_initialize_result())
      Some(Json::object(base))
    }
    "tools/list" => {
      base.set("result", mcp_tools_list_result(registry))
      Some(Json::object(base))
    }
    "tools/call" => {
      base.set("result", mcp_tools_call_result(registry, params))
      Some(Json::object(base))
    }
    "ping" => {
      base.set("result", Json::object(Map([])))
      Some(Json::object(base))
    }
    _ => {
      base.set("error", mcp_error(-32601, "Method not found: " + method_name))
      Some(Json::object(base))
    }
  }
}

///|
/// Serve JSON-RPC over stdin/stdout until stdin closes.
///
/// One JSON object per line in each direction; stdout carries only protocol
/// frames, so diagnostics must never be written there.
pub async fn handle_mcp_serve() -> Unit {
  let registry = @tool.make_default_registry()
  let stdin = @stdio.stdin
  let stdout = @stdio.stdout
  let mut serving = true
  while serving {
    let line = stdin.read_until("\n") catch { _ => None }
    match line {
      None => serving = false
      Some(raw) => {
        let text = raw.trim().to_owned()
        if text.is_empty() {
          continue
        }
        let mut parse_failed = false
        let req : Json = @json.parse(text) catch {
          _ => {
            parse_failed = true
            Json::object(Map([]))
          }
        }
        if parse_failed {
          stdout.write(
            Json::object({
              "jsonrpc": "2.0".to_json(),
              "id": Json::null(),
              "error": mcp_error(-32700, "Parse error"),
            }).stringify() + "\n",
          )
          continue
        }
        match mcp_dispatch(registry, req) {
          None => ()
          Some(resp) => stdout.write(resp.stringify() + "\n")
        }
      }
    }
  }
}