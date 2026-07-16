///|
#cfg(target="js")
using @debug {trait Debug, type Repr}

///|
/// Close event information surfaced by `@websocket.connect(...)`.
#cfg(target="js")
pub struct CloseInfo {
  code : Int
  reason : String
  clean : Bool
} derive(Debug)

///|
pub impl Show for CloseInfo with fn output(self, buf) {
  self.to_repr().output(buf)
}

///|
/// Inbound events emitted by a managed WebSocket connection.
#cfg(target="js")
pub(all) enum Event {
  Opened
  Message(String)
  Closed(CloseInfo)
  Errored
} derive(Debug)

///|
pub impl Show for Event with fn output(self, buf) {
  self.to_repr().output(buf)
}

///|
/// Outbound payload for `send(...)`.
#cfg(target="js")
pub(all) enum Payload {
  Text(String)
  Json(Json)
}

///|
pub impl Show for Payload with fn output(self, buf) {
  match self {
    Text(text) => {
      buf.write_string("Text(")
      text.output(buf)
      buf.write_string(")")
    }
    Json(value) => {
      buf.write_string("Json(")
      buf.write_string(value.stringify())
      buf.write_string(")")
    }
  }
}

///|
#cfg(target="js")
pub impl Debug for Payload with fn to_repr(self) {
  Repr::literal(self.to_string())
}

///|
/// Browser `WebSocket.readyState` mapped to a MoonBit enum.
#cfg(target="js")
pub(all) enum ReadyState {
  Connecting
  Open
  Closing
  Closed
} derive(Debug)

///|
pub impl Show for ReadyState with fn output(self, buf) {
  self.to_repr().output(buf)
}

///|
/// Snapshot of the current connection state for a named socket.
#cfg(target="js")
pub struct Snapshot {
  id : String
  url : String
  protocol : String
  buffered_amount : Int
  ready_state : ReadyState
} derive(Debug)

///|
pub impl Show for Snapshot with fn output(self, buf) {
  self.to_repr().output(buf)
}
