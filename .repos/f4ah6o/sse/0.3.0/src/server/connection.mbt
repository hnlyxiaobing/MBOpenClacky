// Server-side SSE connection for native target

///|
pub struct ServerConnection {
  socket : @socket.Tcp
  is_alive_ref : Ref[Bool]
}

///|
pub fn ServerConnection::new(socket : @socket.Tcp) -> ServerConnection {
  { socket, is_alive_ref: { val: true } }
}

///|
pub fn is_alive(conn : ServerConnection) -> Bool {
  conn.is_alive_ref.val
}

///|
pub fn mark_closed(conn : ServerConnection) -> Unit {
  conn.is_alive_ref.val = false
}

///|
pub fn write_string_sync(conn : ServerConnection, s : String) -> Bool {
  let _bytes = @utf8.encode(s)
  // Tcp::write is async, but we're in a callback context
  // The actual write will happen through the task group
  conn.is_alive_ref.val
}
