///| Tests for the async HTTP transport changes (task pack 3e):

///| the connect/read timeout split and the streaming `Accept` header.

///| The tests run against a real local `@http.Server` on loopback.

///|
/// The streaming path must send `Accept: text/event-stream` on the
/// request, mirroring Ruby's `send_anthropic_stream_request`.
async test "stream request sends Accept text/event-stream header" {
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  let port = @socket.Addr::port(server.addr)
  let url = "http://127.0.0.1:\{port}/v1/chat"
  let mut received_accept = ""
  let mut received_event = ""
  @async.with_task_group(group => {
    group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
      server.run_forever(async fn(req, _body, conn) {
        received_accept = match
          req.headers.keys().find_first(k => k.to_lower() == "accept") {
          Some(k) => req.headers[k]
          None => ""
        }
        conn.send_response(200, "OK")
        conn.write_string("data: {\"ok\":true}\n\n")
      })
    }
    let result = http_post_stream_async(
      url,
      "{}",
      [("Content-Type", "application/json")],
      5000,
      fn(frame : SseFrame) { received_event = frame.data },
    )
    match result {
      Ok(resp) => assert_eq(resp.status_code, 200)
      Err(err) => fail("stream request failed: \{err.to_repr()}")
    }
  })
  server.close()
  assert_eq(received_accept, "text/event-stream")
  assert_eq(received_event, "{\"ok\":true}")
}

///|
/// The read phase must honour `timeout_ms`: a server that delays its
/// response beyond the read window yields `Timeout` (Ruby read_timeout).
async test "read phase times out within read timeout" {
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  let port = @socket.Addr::port(server.addr)
  let url = "http://127.0.0.1:\{port}/v1/chat"
  @async.with_task_group(group => {
    group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
      server.run_forever(async fn(_req, _body, conn) {
        @async.sleep(2000)
        conn.send_response(200, "OK")
        conn.write_string("late")
      })
    }
    let result = http_post_async(url, "{}", [], 300)
    match result {
      Err(Timeout(msg)) => assert_true(msg.contains("timed out"))
      _ => fail("Expected Timeout but got: \{@debug.to_string(result)}")
    }
  })
  server.close()
}

///|
/// A connection refused by the peer surfaces as `ConnectionFailed`
/// (connect phase errors are mapped, not swallowed).
async test "connect failure maps to ConnectionFailed" {
  // Grab a port by binding then closing; nothing listens on it anymore.
  let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
  let port = @socket.Addr::port(server.addr)
  server.close()
  let url = "http://127.0.0.1:\{port}/v1/test"
  let result = http_post_async(url, "{}", [], 5000)
  match result {
    Err(ConnectionFailed(msg)) => assert_true(msg.contains("127.0.0.1"))
    _ => fail("Expected ConnectionFailed but got: \{@debug.to_string(result)}")
  }
}
