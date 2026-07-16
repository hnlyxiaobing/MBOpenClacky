///|
using @cmd {type Cmd, trait Scheduler}

///|
#cfg(target="js")
priv struct SocketEntry {
  socket : @dom.WebSocket
  listeners : Map[String, @dom.Listener]
}

///|
#cfg(target="js")
let connections : Map[String, SocketEntry] = {}

///|
#cfg(target="js")
fn ready_state_from_dom(value : Int) -> ReadyState {
  match value {
    0 => Connecting
    1 => Open
    2 => Closing
    _ => Closed
  }
}

///|
#cfg(target="js")
fn snapshot_of(id : String, socket : @dom.WebSocket) -> Snapshot {
  {
    id,
    url: socket.get_url(),
    protocol: socket.get_protocol(),
    buffered_amount: socket.get_buffered_amount(),
    ready_state: ready_state_from_dom(socket.get_ready_state()),
  }
}

///|
#cfg(target="js")
fn not_found_message(id : String) -> String {
  "websocket connection not found: \{id}"
}

///|
#cfg(target="js")
fn report_failure(
  scheduler : &Scheduler,
  failed : @cmd.Emit[String]?,
  message : String,
) -> Unit {
  match failed {
    Some(failed) => scheduler.add(failed(message))
    None => ()
  }
}

///|
#cfg(target="js")
fn detach_socket(
  socket : @dom.WebSocket,
  listeners : Map[String, @dom.Listener],
) -> Unit {
  for event_name, listener in listeners {
    socket.remove_event_listener(event_name, listener)
  }
}

///|
#cfg(target="js")
fn detach_entry(entry : SocketEntry) -> Unit {
  detach_socket(entry.socket, entry.listeners)
}

///|
#cfg(target="js")
fn payload_to_string(payload : Payload) -> String {
  match payload {
    Text(text) => text
    Json(json) => json.stringify()
  }
}

///|
/// Open or replace a named browser WebSocket connection.
///
/// Reconnecting with the same `id` replaces the old socket after the new one
/// has been created and wired.
#cfg(target="js")
pub fn connect(
  id : String,
  url : String,
  protocols? : Array[String] = [],
  on_event~ : @cmd.Emit[Event],
  failed? : @cmd.Emit[String],
) -> Cmd {
  @cmd.custom_cmd(kind=Immediately, scheduler => {
    let listeners : Map[String, @dom.Listener] = {}
    match @dom.WebSocket::open(url, protocols~) {
      Ok(created) => {
        fn on_open(_) {
          scheduler.add(on_event(Opened))
        }
        listeners["open"] = on_open
        created.add_event_listener("open", on_open)

        fn on_message(event : @dom.Event) {
          guard event.to_message_event() is Some(event) else { return }
          guard event.get_data_string() is Some(text) else { return }
          scheduler.add(on_event(Message(text)))
        }
        listeners["message"] = on_message
        created.add_event_listener("message", on_message)

        fn on_close(event : @dom.Event) {
          guard event.to_close_event() is Some(event) else { return }
          let info : CloseInfo = {
            code: event.get_code(),
            reason: event.get_reason(),
            clean: event.get_was_clean(),
          }
          if connections.get(id) is Some(entry) {
            detach_entry(entry)
            connections.remove(id)
          }
          scheduler.add(on_event(Closed(info)))
        }
        listeners["close"] = on_close
        created.add_event_listener("close", on_close)

        fn on_error(_) {
          scheduler.add(on_event(Errored))
        }
        listeners["error"] = on_error
        created.add_event_listener("error", on_error)

        if connections.get(id) is Some(old_entry) {
          detach_entry(old_entry)
          old_entry.socket.close_quietly()
        }
        connections[id] = { socket: created, listeners }
      }
      Err(message) => report_failure(scheduler, failed, message)
    }
  })
}

///|
/// Send an outbound payload through a named WebSocket connection.
#cfg(target="js")
pub fn send(id : String, payload : Payload, failed? : @cmd.Emit[String]) -> Cmd {
  @cmd.custom_cmd(kind=Immediately, scheduler => {
    match connections.get(id) {
      Some(entry) =>
        match entry.socket.send_safe(payload_to_string(payload)) {
          Ok(_) => ()
          Err(message) => report_failure(scheduler, failed, message)
        }
      None => report_failure(scheduler, failed, not_found_message(id))
    }
  })
}

///|
/// Request closing a named WebSocket connection.
///
/// The registry entry remains until the real browser `close` event arrives.
#cfg(target="js")
pub fn close(
  id : String,
  code? : Int,
  reason? : String,
  failed? : @cmd.Emit[String],
) -> Cmd {
  @cmd.custom_cmd(kind=Immediately, scheduler => {
    match connections.get(id) {
      Some(entry) => {
        let result = match (code, reason) {
          (Some(code), Some(reason)) => entry.socket.close_safe(code~, reason~)
          (Some(code), None) => entry.socket.close_safe(code~)
          (None, Some(reason)) => entry.socket.close_safe(reason~)
          (None, None) => entry.socket.close_safe()
        }
        match result {
          Ok(_) => ()
          Err(message) => report_failure(scheduler, failed, message)
        }
      }
      None => report_failure(scheduler, failed, not_found_message(id))
    }
  })
}

///|
/// Read the current state of a named WebSocket connection.
#cfg(target="js")
pub fn state(id : String, reply~ : @cmd.Emit[Result[Snapshot, String]]) -> Cmd {
  @cmd.custom_cmd(kind=Immediately, scheduler => {
    match connections.get(id) {
      Some(entry) => scheduler.add(reply(Ok(snapshot_of(id, entry.socket))))
      None => scheduler.add(reply(Err(not_found_message(id))))
    }
  })
}
