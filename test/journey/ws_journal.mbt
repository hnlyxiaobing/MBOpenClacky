///|
/// WebSocket journal: a thin wrapper over @websocket.Conn that records
/// every frame in both directions, classifies inbound frames with the
/// production protocol parser (`@proto.Event::from_wire`), and lets steps
/// block until a specific event type arrives.

///|
pub(all) struct WsJournal {
  conn : @websocket.Conn
  /// Received frame texts in order.
  mut frames_in : Array[String]
  /// Sent frame texts in order.
  mut frames_out : Array[String]
  /// Inbound event classification ("" when a frame is not a known Event).
  mut events : Array[String]
  /// Wake queue signaled after each inbound frame.
  wake : @aqueue.Queue[Unit]
  mut closed : Bool
}

///|
/// Connect to a WebSocket URL (ws://host:port/path).
pub async fn WsJournal::connect(url : String) -> Result[WsJournal, String] {
  let conn = @websocket.Conn::connect(url) catch {
    _ => return Err("WebSocket connect failed: \{url}")
  }
  let journal : WsJournal = {
    conn,
    frames_in: [],
    frames_out: [],
    events: [],
    wake: @aqueue.Queue(kind=Unbounded),
    closed: false,
  }
  Ok(journal)
}

///|
/// Start the receive loop as a background task in the journey's task
/// group. The loop exits on connection close or error; both are treated
/// as normal teardown (journaling simply stops).
pub fn WsJournal::start_recv_loop(
  self : WsJournal,
  group : @async.TaskGroup[Unit],
) -> Unit {
  group.spawn_bg(no_wait=true, async fn() {
    while !self.closed {
      let msg = self.conn.recv() catch {
        _ => {
          self.closed = true
          break
        }
      }
      let text = msg.read_all().text() catch { _ => "" }
      if text.length() == 0 {
        continue
      }
      self.frames_in.push(text)
      match @proto.Event::from_wire(text) {
        Some(ev) => self.events.push(ev.type_name())
        None => self.events.push("")
      }
      self.wake.put(())
    }
  })
}

///|
/// Send a JSON frame (recorded in the journal).
pub async fn WsJournal::send_json(self : WsJournal, frame : Json) -> Unit {
  let text = frame.stringify()
  self.conn.send_text(text) catch {
    _ => ()
  }
  self.frames_out.push(text)
}

///|
/// Send a pre-serialized text frame (placeholders already expanded).
pub async fn WsJournal::send_text(self : WsJournal, text : String) -> Unit {
  self.conn.send_text(text) catch {
    _ => ()
  }
  self.frames_out.push(text)
}

///|
/// Block until an inbound event with the given `type_name()` arrives
/// (checks already-received events first). Returns false on timeout.
pub async fn WsJournal::wait_event(
  self : WsJournal,
  event : String,
  timeout_ms : Int,
) -> Bool {
  let deadline = @agent.current_time_ms() + timeout_ms.to_int64()
  for ;; {
    for i = 0; i < self.events.length(); i = i + 1 {
      if self.events[i] == event {
        return true
      }
    }
    let remaining_ms = (deadline - @agent.current_time_ms()).to_int()
    if remaining_ms <= 0 {
      return false
    }
    match @async.with_timeout_opt(remaining_ms, () => self.wake.get()) {
      Some(_) => ()
      None => return false
    }
  }
}

///|
/// Count inbound events with the given type name.
pub fn WsJournal::event_count(self : WsJournal, event : String) -> Int {
  let mut n = 0
  for e in self.events {
    if e == event {
      n = n + 1
    }
  }
  n
}

///|
/// Close the connection (teardown). The recv loop exits on the close
/// handshake or the resulting error.
pub async fn WsJournal::close(self : WsJournal) -> Unit {
  if self.closed {
    return
  }
  self.closed = true
  self.conn.send_close() catch {
    _ => ()
  }
}
