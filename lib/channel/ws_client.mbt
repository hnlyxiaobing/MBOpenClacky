///| WebSocket client thin wrapper for channel adapters (stubfix-07 decision 2).
/// Wraps @async.websocket.Conn with a simplified interface and mock injection point.

///|
/// WebSocket message received from server.
pub(all) enum WsMessage {
  Text(String)
  Closed(Int, String?)
} derive(Eq, Debug)

///|
pub extend WsMessage with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend WsMessage with Eq::{not_equal, equal}

///|
/// WebSocket client wrapper.
/// Provides connect/send/recv/close over @async.websocket.Conn.
pub(all) struct WsClient {
  mut conn : @websocket.Conn?
  mut is_connected : Bool
}

///|
/// Create a new disconnected WsClient.
pub fn WsClient::new() -> WsClient {
  { conn: None, is_connected: false }
}

///|
/// Connect to a WebSocket URL (ws:// or wss://).
pub async fn WsClient::connect(
  self : WsClient,
  url : String,
) -> Result[Unit, ChannelError] {
  let conn = @websocket.Conn::connect(url) catch {
    _ => return Err(ChannelError("WebSocket connection failed: " + url))
  }
  self.conn = Some(conn)
  self.is_connected = true
  Ok(())
}

///|
/// Send a text frame.
pub async fn WsClient::send_text(
  self : WsClient,
  text : String,
) -> Result[Unit, ChannelError] {
  match self.conn {
    Some(conn) => {
      conn.send_text(text) catch {
        _ => return Err(ChannelError("WebSocket send failed"))
      }
      Ok(())
    }
    None => Err(ChannelError("WebSocket not connected"))
  }
}

///|
/// Receive the next message (blocks until available).
/// Returns Closed variant on connection close.
pub async fn WsClient::recv(self : WsClient) -> WsMessage {
  match self.conn {
    Some(conn) => {
      let msg = conn.recv() catch {
        @websocket.WebSocketError::ConnectionClosed(code, reason) => {
          self.is_connected = false
          let code_int = match code {
            @websocket.CloseCode::Normal => 1000
            @websocket.CloseCode::GoingAway => 1001
            @websocket.CloseCode::ProtocolError => 1002
            @websocket.CloseCode::UnsupportedData => 1003
            @websocket.CloseCode::Abnormal => 1006
            @websocket.CloseCode::InvalidFramePayload => 1007
            @websocket.CloseCode::PolicyViolation => 1008
            @websocket.CloseCode::MessageTooBig => 1009
            @websocket.CloseCode::MissingExtension => 1010
            @websocket.CloseCode::InternalError => 1011
            @websocket.CloseCode::Other(n) => n.to_int()
          }
          return WsMessage::Closed(code_int, reason)
        }
        _ => {
          self.is_connected = false
          return WsMessage::Closed(1006, Some("connection error"))
        }
      }
      // Read message content based on kind
      let data = msg.read_all()
      match msg.kind {
        @websocket.MessageKind::Text => {
          let content = data.text() catch { _ => "" }
          WsMessage::Text(content)
        }
        @websocket.MessageKind::Binary => {
          // Treat binary as text for simplicity (Discord only sends text)
          let content = data.text() catch { _ => "" }
          WsMessage::Text(content)
        }
      }
    }
    None => WsMessage::Closed(1006, Some("not connected"))
  }
}

///|
/// Send a close frame and mark disconnected.
pub async fn WsClient::close(self : WsClient) -> Unit {
  match self.conn {
    Some(conn) => {
      conn.send_close() catch {
        _ => ()
      }
      // Drop the reference so a post-close send_text fails honestly with
      // "not connected" instead of writing into a closed connection.
      self.conn = None
      self.is_connected = false
    }
    None => ()
  }
}

///|
/// Check if the client is currently connected.
pub fn WsClient::connected(self : WsClient) -> Bool {
  self.is_connected
}
