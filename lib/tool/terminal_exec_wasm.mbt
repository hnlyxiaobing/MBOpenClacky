///| Stub command execution for wasm/wasm-gc backends.

///|
/// On wasm targets, process spawning is not available. Returns -1 to
/// indicate failure (same contract as the native run_system_command).
async fn run_system_command(
  _command : String,
  _env : Map[String, String],
) -> Int {
  -1
}
