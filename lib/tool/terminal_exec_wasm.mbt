///| Stub command execution for wasm/wasm-gc backends.

///|

///|
/// On wasm targets, system() is not available. Returns -1 to indicate failure.
fn run_system_command(_command : String) -> Int {
  -1
}
