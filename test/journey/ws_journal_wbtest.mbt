///| WS journal interop tests against an in-process WebSocket server.
/// Derisks the client↔server interop before the journey web driver
/// touches the product server (spec risk #1).

///|
async test "ws journal: echo server round-trip and event waiting" {
  match
    @async.with_timeout_opt(20_000, () => {
      @async.with_task_group(async fn(group) {
        let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
        let port = server.addr.port()
        // Echo server: greets with a valid `subscribed` event frame, echoes
        // text frames verbatim, and answers a "poke" with `task_finished`.
        group.spawn_bg(no_wait=true, async fn() {
          server.run_forever() <| ((request, _reader, conn) => {
            let ws = @websocket.from_http_server(request, conn)
            defer ws.close()
            ws.send_text("{\"type\":\"subscribed\",\"session_id\":\"s1\"}")
            for ;; {
              let msg = ws.recv() catch { _ => break }
              let text = msg.read_all().text() catch { _ => break }
              if text.length() == 0 {
                continue
              }
              if text.contains("\"poke\"") {
                ws.send_text(
                  "{\"type\":\"task_finished\",\"session_id\":\"s1\"}",
                )
              } else {
                ws.send_text(text)
              }
            }
          })
        })
        let journal = match WsJournal::connect("ws://127.0.0.1:\{port}/") {
          Ok(j) => j
          Err(msg) => {
            println("connect error: \{msg}")
            @debug.assert_eq(true, false)
            return
          }
        }
        journal.start_recv_loop(group)
        // The welcome frame classifies as a real Event.
        @debug.assert_eq(journal.wait_event("subscribed", 5000), true)
        @debug.assert_eq(journal.event_count("subscribed"), 1)
        // A non-event frame (client command echoed back) is journaled as a
        // raw frame but classified as "".
        journal.send_json(
          Json::object({
            "type": "message".to_json(),
            "session_id": "s1".to_json(),
            "content": "hello".to_json(),
          }),
        )
        journal.send_text("{\"type\":\"poke\"}")
        @debug.assert_eq(journal.wait_event("task_finished", 5000), true)
        // Raw frame log captured both directions.
        @debug.assert_eq(journal.frames_out.length(), 2)
        @debug.assert_eq(journal.frames_in.length() >= 3, true)
        let echoed = journal.frames_in.contains(
          "{\"type\":\"message\",\"session_id\":\"s1\",\"content\":\"hello\"}",
        )
        @debug.assert_eq(echoed, true)
        // Clean teardown: close does not hang the task group.
        journal.close()
      })
    }) {
    Some(_) => ()
    None => @debug.assert_eq(true, false)
  }
}

///|
async test "ws journal: wait_event timeout returns false" {
  match
    @async.with_timeout_opt(10_000, () => {
      @async.with_task_group(async fn(group) {
        let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
        let port = server.addr.port()
        // Server that never sends anything after the handshake.
        group.spawn_bg(no_wait=true, async fn() {
          server.run_forever() <| ((request, _reader, conn) => {
            let ws = @websocket.from_http_server(request, conn)
            defer ws.close()
            for ;; {
              let msg = ws.recv() catch { _ => break }
              ignore(msg.read_all().text() catch { _ => "" })
            }
          })
        })
        let journal = match WsJournal::connect("ws://127.0.0.1:\{port}/") {
          Ok(j) => j
          Err(_) => {
            @debug.assert_eq(true, false)
            return
          }
        }
        journal.start_recv_loop(group)
        // Bounded wait on a silent server must time out, not hang.
        @debug.assert_eq(journal.wait_event("task_finished", 300), false)
        journal.close()
      })
    }) {
    Some(_) => ()
    None => @debug.assert_eq(true, false)
  }
}
