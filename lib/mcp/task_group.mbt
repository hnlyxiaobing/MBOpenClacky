///| MCP async task-group infrastructure.
///  The stdio transport runs persistent read loops; they must be spawned
///  into a long-lived TaskGroup. The web server registers its group at
///  startup (same pattern as handlers_ws.set_ws_task_group), and tests
///  register their own group inside `with_task_group`.

///|
let mcp_task_group : Ref[@async.TaskGroup[Unit]?] = Ref(None)

///|
/// Register the long-lived task group used to spawn MCP read loops and
/// process-cleanup tasks. Called by the web server at startup; tests call
/// it inside their own `@async.with_task_group` scope.
pub fn set_mcp_task_group(group : @async.TaskGroup[Unit]) -> Unit {
  mcp_task_group.val = Some(group)
}

///|
/// Clear the registered task group (used after a server/test scope ends).
pub fn clear_mcp_task_group() -> Unit {
  mcp_task_group.val = None
}

///|
/// Spawn a cancellable background task into the registered MCP task group.
/// Returns None when no group has been registered (caller decides how to
/// report the error).
fn spawn_mcp_task(body : async () -> Unit) -> @async.Task[Unit]? {
  match mcp_task_group.val {
    Some(group) => Some(group.spawn(no_wait=true, allow_failure=true, body))
    None => None
  }
}

///|
/// Fire-and-forget background spawn; returns false when no group is
/// registered.
fn spawn_mcp_bg(body : async () -> Unit) -> Bool {
  match mcp_task_group.val {
    Some(group) => {
      group.spawn_bg(no_wait=true, allow_failure=true, body)
      true
    }
    None => false
  }
}
