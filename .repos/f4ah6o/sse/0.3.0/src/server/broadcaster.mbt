// Server-side SSE broadcaster for native target

///|
pub struct Broadcaster {
  connections_ref : Ref[Array[ServerConnection]]
}

///|
pub fn Broadcaster::new() -> Broadcaster {
  { connections_ref: { val: [] } }
}

///|
pub fn subscribe(b : Broadcaster, conn : ServerConnection) -> Unit {
  b.connections_ref.val.push(conn)
}

///|
pub fn get_connections(b : Broadcaster) -> Array[ServerConnection] {
  b.connections_ref.val
}

///|
pub fn remove_closed(b : Broadcaster) -> Unit {
  b.connections_ref.val = b.connections_ref.val.filter(fn(c) { is_alive(c) })
}
