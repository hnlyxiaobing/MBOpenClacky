///| Process execution via moonbitlang/async's process API.
///
/// S-FFI-08 (specs/completed/2026-07-25_ffi-08-residual-ffi-pty.md):
/// the old C `system()` FFI (`mb_system` in tool_stubs.c) was replaced by
/// `@process.run`. The whole call stack (Tool::execute, hook/patch loaders,
/// web extension handlers) is async since S-06, so spawning through the
/// async event loop keeps the runtime responsive while the child runs.

///|
/// Counter for unique temp batch-file names (concurrent web requests).
let windows_bat_counter : Ref[Int] = Ref(0)

///|
/// Spawn `cmd` with `args` and wait for completion, returning the real
/// exit code. Returns -1 when the process cannot be spawned, mirroring
/// the old system() failure contract.
async fn spawn_and_wait(cmd : String, args : Array[String]) -> Int {
  @process.run(cmd, args, no_console_window=true) catch {
    _ => -1
  }
}

///|
/// Execute a shell command string through the platform shell and return
/// the child's real exit code (no wait-status shifting — unlike system()).
///
/// Unix: `sh -c <command>` — argv passing needs no quoting.
///
/// Windows: the command is written to a temporary .bat file which is then
/// run via `cmd.exe /v:on /c <bat>`. We cannot pass the command as an
/// argv element: @process applies MSVC-style argv escaping (\" for inner
/// quotes), which cmd.exe does not understand — the old system() path
/// worked only because cmd.exe received the command text raw. A batch
/// file carries the command verbatim, so quoting is a non-issue.
/// /v:on keeps cmd.exe delayed expansion enabled so that !ERRORLEVEL!
/// in the command (shell_exec.mbt) is expanded after execution.
async fn run_system_command(command : String) -> Int {
  if shell_is_windows() {
    windows_bat_counter.val = windows_bat_counter.val + 1
    let bat_path = @path.Path::join(
      shell_temp_dir(),
      @path.Path(
        "clacky_sh_\{@env.now().reinterpret_as_int64()}_\{windows_bat_counter.val}.bat",
      ),
    ).to_string()
    // CRLF line endings for the cmd.exe batch parser. `@echo off` is
    // required: batch echo would otherwise leak the command text into our
    // own stdout (the child inherits it), corrupting the test driver's
    // NDJSON protocol and any structured output of the parent process.
    @fs.write_string_to_file(bat_path, "@echo off\r\n" + command + "\r\n") catch {
      _ => return -1
    }
    let code = spawn_and_wait("cmd.exe", ["/v:on", "/c", bat_path])
    @fs.remove_file(bat_path) catch {
      _ => ()
    }
    code
  } else {
    spawn_and_wait("sh", ["-c", command])
  }
}
