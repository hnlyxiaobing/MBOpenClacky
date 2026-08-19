///|
/// pty_session_wasm.mbt — wasm fallback for command execution.
///
/// PTY is native-only (moonbit-community/pty supports only native targets);
/// on wasm there is no process spawning either, so this delegates to the
/// wasm stub of execute_command_sync, which reports failure (-1).

///|
/// Execute a command. On wasm there is no PTY — go straight to the
/// (stubbed) synchronous executor.
async fn execute_command(
  user_command : String,
  cwd : String,
  timeout_ms : Int,
  session_id : Int,
  env : Map[String, String],
) -> (String, Int, String) {
  execute_command_sync(user_command, cwd, timeout_ms, session_id, env)
}
