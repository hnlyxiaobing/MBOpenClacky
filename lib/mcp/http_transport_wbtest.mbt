///|
/// White-box tests for the HTTP (Streamable HTTP / SSE) MCP transport.
///
/// Every round-trip test runs against a real HTTP server bound to an
/// ephemeral loopback port in the same task group: the transport is exercised
/// over actual sockets, without touching the network.

///|
/// What the mock server saw, shared between the server task and the test.
struct MockMcpLog {
  paths : Array[String]
  accepts : Array[String]
  session_ids : Array[String]
  bodies : Array[String]
}

///|
fn mock_log() -> MockMcpLog {
  { paths: [], accepts: [], session_ids: [], bodies: [] }
}

///|
/// Record one request: method path, the `Accept` header (Streamable HTTP
/// requires both JSON and SSE to be advertised) and the session id, if any.
async fn MockMcpLog::record(
  self : MockMcpLog,
  request : @http.Request,
  body : &@io.Reader,
) -> Unit {
  self.paths.push(request.path)
  self.accepts.push(request.headers.get("accept").unwrap_or(""))
  self.session_ids.push(request.headers.get("mcp-session-id").unwrap_or(""))
  self.bodies.push(body.read_all().text())
}

///|
/// A mock server answering with a fixed JSON-RPC reply for `id`.
fn mock_json_handler(
  id : Int,
  code : Int,
  session_id : String,
) -> (MockMcpLog) -> async (@http.Request, &@io.Reader, @http.ServerConnection) -> Unit {
  log => (request, body, conn) => {
    log.record(request, body)
    conn.send_response(code, "OK", extra_headers={
      "Content-Type": "application/json",
      "Mcp-Session-Id": session_id,
    })
    conn.write_string(
      "{\"jsonrpc\":\"2.0\",\"id\":\{id},\"result\":\"pong\"}",
    )
    conn.end_response()
  }
}

///|
/// An SSE handler: a notification, a stale reply for another id, then the
/// reply for `id`. The transport must return only the last one and forward
/// the first two.
fn mock_sse_handler(
  id : Int,
) -> (MockMcpLog) -> async (@http.Request, &@io.Reader, @http.ServerConnection) -> Unit {
  log => (request, body, conn) => {
    log.record(request, body)
    conn.send_response(200, "OK", extra_headers={
      "Content-Type": "text/event-stream",
    })
    conn.write_string(
      "event: message\ndata: {\"jsonrpc\":\"2.0\",\"method\":\"notifications/message\",\"params\":{\"level\":\"info\"}}\n\n",
    )
    conn.write_string("data: {\"jsonrpc\":\"2.0\",\"id\":9999,\"result\":\"stale\"}\n\n")
    conn.write_string(
      "data: {\"jsonrpc\":\"2.0\",\"id\":\{id},\"result\":\"pong\"}\n\n",
    )
    conn.end_response()
  }
}

///|
/// Start a mock server and hand back its base URL and the mock log.
async fn with_mock_server(
  handler : (MockMcpLog) -> async (@http.Request, &@io.Reader, @http.ServerConnection) -> Unit,
  run : async (String, MockMcpLog) -> Unit,
) -> Unit {
  let log = mock_log()
  let on_request = handler(log)
  @async.with_task_group() <| group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    let url = "http://127.0.0.1:\{server.addr.port()}/mcp"
    group.spawn_bg(no_wait=true) <| () => {
      server.run_forever() <| ((request, body, conn) => {
        on_request(request, body, conn)
      })
    }
    run(url, log)
  }
}

// ── start / stop ────────────────────────────────────────────────────────────

///|
async test "HttpTransport start validates the url and is idempotent" {
  let empty = HttpTransport::new(McpServerSpec::http("bad", ""))
  match empty.start() {
    Ok(_) => assert_true(false)
    Err(e) => assert_true(e.contains("http(s)"))
  }
  assert_false(empty.alive())

  let wrong_scheme = HttpTransport::new(
    McpServerSpec::http("bad", "ftp://example.invalid/mcp"),
  )
  match wrong_scheme.start() {
    Ok(_) => assert_true(false)
    Err(e) => assert_true(e.contains("http(s)"))
  }
  assert_false(wrong_scheme.alive())

  let no_host = HttpTransport::new(McpServerSpec::http("bad", "http:///mcp"))
  match no_host.start() {
    Ok(_) => assert_true(false)
    Err(e) => assert_true(e.contains("host"))
  }

  let good = HttpTransport::new(
    McpServerSpec::http("good", "http://127.0.0.1:9/mcp"),
  )
  match good.start() {
    Ok(_) => assert_true(good.alive())
    Err(e) => fail("a valid url must start: " + e)
  }
  // Starting twice is a no-op, and stop is idempotent.
  match good.start() {
    Ok(_) => assert_true(true)
    Err(e) => fail("second start must be a no-op: " + e)
  }
  good.stop()
  assert_false(good.alive())
  good.stop()
  assert_false(good.alive())
}

// ── JSON replies ────────────────────────────────────────────────────────────

///|
async test "HttpTransport POSTs the message and correlates the JSON reply" {
  with_mock_server(
    mock_json_handler(1, 200, "sess-42"),
    (url, _log) => {
      let transport = HttpTransport::new(McpServerSpec::http("mock", url))
      match transport.start() {
        Ok(_) => ()
        Err(e) => fail("start failed: " + e)
      }
      let sent = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"ping\"}"
      let reply = match transport.send_request(1, sent, 5) {
        Ok(text) => text
        Err(e) => fail("send_request failed: " + e)
      }
      assert_true(reply.contains("\"result\":\"pong\""))
      // The server-assigned session id is captured for later requests.
      @debug.assert_eq(transport.get_session_id(), Some("sess-42"))
    },
  )
}

///|
/// The request carries the JSON-RPC message, the request path from the
/// configured url, the SSE-capable `Accept` header, and the session id once
/// the server has assigned one.
async test "HttpTransport sends path, accept header and session id" {
  with_mock_server(
    mock_json_handler(1, 200, "sess-7"),
    (url, log) => {
      let transport = HttpTransport::new(McpServerSpec::http("mock", url))
      let _ = transport.start()
      let _ = transport.send_request(1, "{\"jsonrpc\":\"2.0\",\"id\":1}", 5)
      let _ = transport.send_request(1, "{\"jsonrpc\":\"2.0\",\"id\":1}", 5)
      @debug.assert_eq(log.paths.length(), 2)
      @debug.assert_eq(log.paths[0], "/mcp")
      assert_true(log.accepts[0].contains("text/event-stream"))
      assert_true(log.accepts[0].contains("application/json"))
      assert_true(log.bodies[0].contains("\"method\"") || log.bodies[0].contains("\"id\""))
      // First request has no session yet; the second echoes what the server sent.
      @debug.assert_eq(log.session_ids[0], "")
      @debug.assert_eq(log.session_ids[1], "sess-7")
    },
  )
}

// ── SSE replies ─────────────────────────────────────────────────────────────

///|
/// An SSE reply is read frame by frame: the notification and the stale reply
/// for another id go to the message handler, and only the frame carrying our
/// id is returned.
async test "HttpTransport reads an SSE reply and forwards other frames" {
  with_mock_server(
    mock_sse_handler(7),
    (url, _log) => {
      let transport = HttpTransport::new(McpServerSpec::http("mock", url))
      let forwarded : Array[String] = []
      transport.on_message(fn(payload) { forwarded.push(payload) })
      let _ = transport.start()
      let reply = match
        transport.send_request(7, "{\"jsonrpc\":\"2.0\",\"id\":7}", 5) {
        Ok(text) => text
        Err(e) => fail("send_request failed: " + e)
      }
      assert_true(reply.contains("\"result\":\"pong\""))
      assert_true(reply.contains("\"id\":7"))
      @debug.assert_eq(forwarded.length(), 2)
      assert_true(forwarded[0].contains("notifications/message"))
      assert_true(forwarded[1].contains("\"id\":9999"))
    },
  )
}

///|
/// An SSE stream that closes before the reply arrives is an honest error, not
/// an empty success.
async test "HttpTransport reports an SSE stream closing without the reply" {
  with_mock_server(
    _log => (_request, _body, conn) => {
      conn.send_response(200, "OK", extra_headers={
        "Content-Type": "text/event-stream",
      })
      conn.write_string("data: {\"jsonrpc\":\"2.0\",\"id\":9999,\"result\":\"other\"}\n\n")
      conn.end_response()
    },
    (url, _log) => {
      let transport = HttpTransport::new(McpServerSpec::http("mock", url))
      let _ = transport.start()
      match transport.send_request(3, "{\"jsonrpc\":\"2.0\",\"id\":3}", 5) {
        Ok(text) => fail("expected an error, got: " + text)
        Err(e) => assert_true(e.contains("SSE"))
      }
    },
  )
}

// ── Failure surfaces ────────────────────────────────────────────────────────

///|
/// A reply for a different id must not be accepted as ours.
async test "HttpTransport rejects a JSON reply for another id" {
  with_mock_server(
    mock_json_handler(4242, 200, ""),
    (url, _log) => {
      let transport = HttpTransport::new(McpServerSpec::http("mock", url))
      let _ = transport.start()
      match transport.send_request(5, "{\"jsonrpc\":\"2.0\",\"id\":5}", 5) {
        Ok(text) => fail("expected an error, got: " + text)
        Err(e) => assert_true(e.contains("no reply for id"))
      }
    },
  )
}

///|
/// A refused connection is reported, never silently treated as success.
async test "HttpTransport reports a refused connection" {
  let closed = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  let port = closed.addr.port()
  closed.close()
  let transport = HttpTransport::new(
    McpServerSpec::http("dead", "http://127.0.0.1:\{port}/mcp"),
  )
  // start only validates configuration: Streamable HTTP has no connection to
  // establish, so reachability is reported by the first request.
  match transport.start() {
    Ok(_) => ()
    Err(e) => fail("start must not need a live server: " + e)
  }
  match transport.send_request(1, "{\"jsonrpc\":\"2.0\",\"id\":1}", 5) {
    Ok(text) => fail("expected a connection error, got: " + text)
    Err(e) => assert_true(e.contains("Failed to"))
  }
}

///|
/// A server error status is surfaced with its code.
async test "HttpTransport reports a server error status" {
  with_mock_server(
    mock_json_handler(1, 503, ""),
    (url, _log) => {
      let transport = HttpTransport::new(McpServerSpec::http("mock", url))
      let _ = transport.start()
      match transport.send_request(1, "{\"jsonrpc\":\"2.0\",\"id\":1}", 5) {
        Ok(text) => fail("expected an HTTP error, got: " + text)
        Err(e) => assert_true(e.contains("503"))
      }
    },
  )
}

///|
/// Notifications expect no body: a 202 with an empty body is a success.
async test "HttpTransport accepts an empty notification response" {
  with_mock_server(
    _log => (_request, _body, conn) => {
      conn.send_response(202, "Accepted", extra_headers={
        "Mcp-Session-Id": "sess-9",
      })
      conn.end_response()
    },
    (url, _log) => {
      let transport = HttpTransport::new(McpServerSpec::http("mock", url))
      let _ = transport.start()
      match
        transport.send_message("{\"jsonrpc\":\"2.0\",\"method\":\"notifications/initialized\"}") {
        Ok(_) => assert_true(true)
        Err(e) => fail("notification must be accepted: " + e)
      }
      @debug.assert_eq(transport.get_session_id(), Some("sess-9"))
    },
  )
}

///|
/// A notification rejected by the server is an error, not a silent success.
async test "HttpTransport reports a rejected notification" {
  with_mock_server(
    _log => (_request, _body, conn) => {
      conn.send_response(500, "Server Error")
      conn.end_response()
    },
    (url, _log) => {
      let transport = HttpTransport::new(McpServerSpec::http("mock", url))
      let _ = transport.start()
      match transport.send_message("{\"jsonrpc\":\"2.0\",\"method\":\"x\"}") {
        Ok(_) => assert_true(false)
        Err(e) => assert_true(e.contains("500"))
      }
      // A never-started transport refuses to send at all.
      let stopped = HttpTransport::new(McpServerSpec::http("mock", url))
      match stopped.send_request(1, "{}", 1) {
        Ok(_) => assert_true(false)
        Err(e) => assert_true(e.contains("not started"))
      }
    },
  )
}

// ── End-to-end: the MCP client over the HTTP transport ──────────────────────

///|
/// The real consumer path: `McpClient` performs the Streamable HTTP
/// handshake (`initialize` request, `notifications/initialized` notification)
/// and lists tools, all over sockets against a mock MCP server.
async test "McpClient completes the HTTP handshake and lists tools" {
  with_mock_server(
    log => (request, body, conn) => {
      log.record(request, body)
      let text = log.bodies[log.bodies.length() - 1]
      let parsed = parse_json_opt(text)
      let rpc_method = match parsed {
        Some({ "method": String(m), .. }) => m
        _ => ""
      }
      let id = match parsed {
        Some({ "id": Number(n, ..), .. }) => n.to_int()
        _ => 0
      }
      match rpc_method {
        "initialize" => {
          conn.send_response(200, "OK", extra_headers={
            "Content-Type": "application/json",
            "Mcp-Session-Id": "sess-e2e",
          })
          conn.write_string(
            "{\"jsonrpc\":\"2.0\",\"id\":\{id},\"result\":{\"protocolVersion\":\"2024-11-05\",\"capabilities\":{},\"serverInfo\":{\"name\":\"mock-mcp\",\"version\":\"1.0\"}}}",
          )
          conn.end_response()
        }
        "notifications/initialized" => {
          conn.send_response(202, "Accepted")
          conn.end_response()
        }
        "tools/list" => {
          conn.send_response(200, "OK", extra_headers={
            "Content-Type": "application/json",
          })
          conn.write_string(
            "{\"jsonrpc\":\"2.0\",\"id\":\{id},\"result\":{\"tools\":[{\"name\":\"echo\",\"description\":\"echoes back\",\"inputSchema\":{\"type\":\"object\"}}]}}",
          )
          conn.end_response()
        }
        _ => {
          conn.send_response(404, "Not Found")
          conn.end_response()
        }
      }
    },
    (url, log) => {
      let client = McpClient::from_spec(McpServerSpec::http("mock", url))
      let info = client.initialize() catch {
        McpError(m) => fail("initialize over HTTP failed: " + m)
      }
      @debug.assert_eq(info.name, "mock-mcp")
      let tools = client.tools_list() catch {
        McpError(m) => fail("tools_list over HTTP failed: " + m)
      }
      @debug.assert_eq(tools.length(), 1)
      @debug.assert_eq(tools[0].name, "echo")
      // Handshake + list = three POSTs; the notification carries no id.
      assert_true(log.bodies.length() >= 3)
      @debug.assert_eq(
        log.session_ids[2],
        "sess-e2e",
      )
      client.disconnect()
    },
  )
}

// ── Reply extraction unit cases ─────────────────────────────────────────────

///|
test "extract_reply picks our frame out of a batch payload" {
  let batch =
    #|[{"jsonrpc":"2.0","id":1,"result":"a"},{"jsonrpc":"2.0","id":2,"result":"b"}]
  @debug.assert_eq(
    extract_reply(batch, 2),
    Some("{\"jsonrpc\":\"2.0\",\"id\":2,\"result\":\"b\"}"),
  )
  assert_true(extract_reply(batch, 3) is None)
  assert_true(extract_reply("not json", 1) is None)
  // A notification (no id) never matches a pending request.
  assert_true(
    extract_reply("{\"jsonrpc\":\"2.0\",\"method\":\"notifications/x\"}", 1) is
      None,
  )
}

///|
test "split_server_url separates origin from request path" {
  @debug.assert_eq(
    split_server_url("https://api.example.com/mcp"),
    Ok(("https://api.example.com", "/mcp")),
  )
  @debug.assert_eq(
    split_server_url("http://127.0.0.1:8080"),
    Ok(("http://127.0.0.1:8080", "/")),
  )
  @debug.assert_eq(
    split_server_url("http://host/a/b?c=1"),
    Ok(("http://host", "/a/b?c=1")),
  )
  match split_server_url("ws://host/mcp") {
    Ok(_) => assert_true(false)
    Err(e) => assert_true(e.contains("http(s)"))
  }
}