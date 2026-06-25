///| Native command execution via C's system() function.

///|

///|
/// FFI to C's system() for synchronous command execution.
#borrow(_cmd)
extern "C" fn c_system(_cmd : Bytes) -> Int = "system"

///|
/// Run a system command and return the exit code.
fn run_system_command(command : String) -> Int {
  let cmd_bytes = command.to_bytes()
  c_system(cmd_bytes)
}
