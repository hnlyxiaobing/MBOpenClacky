///|
/// WebSocket broadcast hub for multi-client fan-out.
/// Manages per-session subscriptions and global broadcast channels.
/// Built on top of crescent's WebSocketPeer pub/sub primitives.

///|
/// A registered WebSocket connection with its session binding.
pub(all) struct HubConnection {
  peer : @ws.WebSocketPeer
  mut session_ids : Array[String]
}

///|
/// Central hub for managing WebSocket subscriptions and broadcasting messages.
pub(all) struct Hub {
  /// All registered connections indexed by connection_id.
  mut connections : Map[String, HubConnection]
  /// Session ID -> array of connection_ids subscribed to that session.
  mut session_subs : Map[String, Array[String]]
  /// Connection IDs subscribed to global broadcast.
  mut global_subs : Array[String]
}

///|
/// Create a new empty Hub.
pub fn Hub::new() -> Hub {
  { connections: Map([]), session_subs: Map([]), global_subs: [] }
}

///|
/// Register a new WebSocket connection in the hub.
pub fn Hub::register(self : Hub, peer : @ws.WebSocketPeer) -> Unit {
  let conn_id = peer.connection_id()
  self.connections[conn_id] = { peer, session_ids: [] }
}

///|
/// Unregister a WebSocket connection and remove all its subscriptions.
pub fn Hub::unregister(self : Hub, conn_id : String) -> Unit {
  guard self.connections.contains(conn_id) else { return }
  let conn = self.connections[conn_id]
  // Remove from session subscriptions
  for sid in conn.session_ids {
    self.unsubscribe_session(conn_id, sid)
  }
  // Remove from global subscriptions
  let new_global : Array[String] = []
  for id in self.global_subs {
    if id != conn_id {
      new_global.push(id)
    }
  }
  self.global_subs = new_global
  // Remove connection record
  self.connections.remove(conn_id)
}

///|
/// Subscribe a connection to a specific session's events.
pub fn Hub::subscribe_session(
  self : Hub,
  conn_id : String,
  session_id : String,
) -> Unit {
  guard self.connections.contains(conn_id) else { return }
  let conn = self.connections[conn_id]
  // Avoid duplicate subscription
  for existing in conn.session_ids {
    if existing == session_id {
      return
    }
  }
  conn.session_ids.push(session_id)
  // Add to session_subs map
  if self.session_subs.contains(session_id) {
    self.session_subs[session_id].push(conn_id)
  } else {
    self.session_subs[session_id] = [conn_id]
  }
}

///|
/// Unsubscribe a connection from a specific session.
pub fn Hub::unsubscribe_session(
  self : Hub,
  conn_id : String,
  session_id : String,
) -> Unit {
  guard self.session_subs.contains(session_id) else { return }
  let subs = self.session_subs[session_id]
  let new_subs : Array[String] = []
  for id in subs {
    if id != conn_id {
      new_subs.push(id)
    }
  }
  self.session_subs[session_id] = new_subs
  // Also remove from connection's session list
  if self.connections.contains(conn_id) {
    let conn = self.connections[conn_id]
    let new_sessions : Array[String] = []
    for sid in conn.session_ids {
      if sid != session_id {
        new_sessions.push(sid)
      }
    }
    conn.session_ids = new_sessions
  }
}

///|
/// Subscribe a connection to global broadcast events.
pub fn Hub::subscribe_global(self : Hub, conn_id : String) -> Unit {
  guard self.connections.contains(conn_id) else { return }
  for existing in self.global_subs {
    if existing == conn_id {
      return
    }
  }
  self.global_subs.push(conn_id)
}

///|
/// Broadcast a text message to all connections subscribed to a session.
/// Delegates to broadcast_session_raw; see its doc for stale-connection
/// handling.
pub fn Hub::broadcast_session(
  self : Hub,
  session_id : String,
  message : String,
) -> Unit {
  self.broadcast_session_raw(session_id, message)
}

///|
/// Broadcast a text message to all globally-subscribed connections.
/// Stale connection IDs (present in the subs list but missing from the
/// connections map) are collected and unregistered after iteration to
/// avoid mutating the subscription list mid-loop.
pub fn Hub::broadcast_global(self : Hub, message : String) -> Unit {
  let stale : Array[String] = []
  for conn_id in self.global_subs {
    if self.connections.contains(conn_id) {
      self.connections[conn_id].peer.text(message)
    } else {
      stale.push(conn_id)
    }
  }
  for conn_id in stale {
    self.unregister(conn_id)
  }
}

///|
/// Broadcast a JSON event to all connections subscribed to a session.
pub fn Hub::broadcast_session_json(
  self : Hub,
  session_id : String,
  event_type : String,
  data : Json,
) -> Unit {
  let payload = Json::object({
    "type": event_type.to_json(),
    "session_id": session_id.to_json(),
    "data": data,
  }).stringify()
  self.broadcast_session(session_id, payload)
}

///|
/// Broadcast a JSON event to all globally-subscribed connections.
pub fn Hub::broadcast_global_json(
  self : Hub,
  event_type : String,
  data : Json,
) -> Unit {
  let payload = Json::object({ "type": event_type.to_json(), "data": data }).stringify()
  self.broadcast_global(payload)
}

///|
/// Broadcast a heartbeat ping to all globally-subscribed connections.
/// Used to keep idle WebSocket connections alive.
pub fn Hub::broadcast_heartbeat(self : Hub) -> Unit {
  let ts = @env.now().reinterpret_as_int64()
  self.broadcast_global_json(
    "heartbeat",
    Json::object({ "timestamp": ts.to_json() }),
  )
}

///|
/// Get the number of connections subscribed to a session.
pub fn Hub::session_connection_count(self : Hub, session_id : String) -> Int {
  guard self.session_subs.contains(session_id) else { return 0 }
  self.session_subs[session_id].length()
}

///|
/// Get the total number of registered connections.
pub fn Hub::connection_count(self : Hub) -> Int {
  self.connections.length()
}

///|
/// List all session IDs that have active subscriptions.
pub fn Hub::active_sessions(self : Hub) -> Array[String] {
  let result : Array[String] = []
  for entry in self.session_subs.iter() {
    if entry.1.length() > 0 {
      result.push(entry.0)
    }
  }
  result
}

///|
/// Switch a connection's session subscription.
/// Unsubscribes from all currently subscribed sessions and subscribes
/// to the new session. This supports the /ws model where a single
/// connection dynamically switches between sessions via subscribe messages.
/// Binding to a concrete session also drops the global subscription, so the
/// connection no longer receives global broadcasts after switching.
pub fn Hub::switch_session(
  self : Hub,
  conn_id : String,
  new_session_id : String,
) -> Unit {
  guard self.connections.contains(conn_id) else { return }
  let conn = self.connections[conn_id]
  // Unsubscribe from all existing session subscriptions.
  let old_sessions = conn.session_ids.copy()
  for sid in old_sessions {
    self.unsubscribe_session(conn_id, sid)
  }
  // Drop the global subscription: a connection bound to a specific session
  // must not keep receiving global broadcasts.
  let new_global : Array[String] = []
  for id in self.global_subs {
    if id != conn_id {
      new_global.push(id)
    }
  }
  self.global_subs = new_global
  // Subscribe to the new session.
  self.subscribe_session(conn_id, new_session_id)
}

///|
/// Get the peer for a given connection_id, if it exists.
pub fn Hub::get_peer(self : Hub, conn_id : String) -> @ws.WebSocketPeer? {
  match self.connections.get(conn_id) {
    Some(conn) => Some(conn.peer)
    None => None
  }
}

///|
/// Get the list of session IDs a connection is currently subscribed to.
pub fn Hub::get_connection_sessions(
  self : Hub,
  conn_id : String,
) -> Array[String] {
  match self.connections.get(conn_id) {
    Some(conn) => conn.session_ids.copy()
    None => []
  }
}

///|
/// Broadcast a raw (pre-built) JSON string to all connections subscribed to
/// a session. This is the single fan-out implementation for session-bound
/// broadcasts; broadcast_session delegates here.
/// Stale connection IDs (present in the subs list but missing from the
/// connections map) are collected and unregistered after iteration to
/// avoid mutating the subscription list mid-loop.
pub fn Hub::broadcast_session_raw(
  self : Hub,
  session_id : String,
  raw_json : String,
) -> Unit {
  guard self.session_subs.contains(session_id) else { return }
  let conn_ids = self.session_subs[session_id]
  let stale : Array[String] = []
  for conn_id in conn_ids {
    if self.connections.contains(conn_id) {
      self.connections[conn_id].peer.text(raw_json)
    } else {
      stale.push(conn_id)
    }
  }
  for conn_id in stale {
    self.unregister(conn_id)
  }
}
