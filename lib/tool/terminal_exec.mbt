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
///
/// CI flakiness guard: transient spawn failures (thread-pool/posix_spawn
/// races under runner load) surface as raised errors → -1. A child exit
/// code can never be -1, so retrying on -1 is safe; up to 3 attempts with
/// a short backoff before reporting failure.
async fn spawn_and_wait(
  cmd : String,
  args : Array[String],
  env : Map[String, String],
) -> Int {
  let mut code = -1
  let mut attempt = 0
  while code == -1 && attempt <= 2 {
    if attempt > 0 {
      @async.sleep(20 * attempt)
    }
    code = @process.run(cmd, args, extra_env=env, no_console_window=true) catch {
      _ => -1
    }
    attempt = attempt + 1
  }
  code
}

///|
/// Execute a shell command string through the platform shell and return
/// the child's real exit code (no wait-status shifting — unlike system()).
///
/// Unix: `bash -c <command>` — argv passing needs no quoting. Bash (not
/// `sh`/dash) is required so the embedded safe_rm.sh wrapper (bash
/// syntax: `local -a`, `${a:0:1}`) can be sourced before every command
/// (Ruby spawns bash/zsh interactive shells for the same reason).
///
/// Windows: the command is written to a temporary .bat file which is then
/// run via `cmd.exe /v:on /c <bat>`. We cannot pass the command as an
/// argv element: @process applies MSVC-style argv escaping (\" for inner
/// quotes), which cmd.exe does not understand — the old system() path
/// worked only because cmd.exe received the command text raw. A batch
/// file carries the command verbatim, so quoting is a non-issue.
/// /v:on keeps cmd.exe delayed expansion enabled so that !ERRORLEVEL!
/// in the command (shell_exec.mbt) is expanded after execution.
async fn run_system_command(command : String, env : Map[String, String]) -> Int {
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
    let code = spawn_and_wait("cmd.exe", ["/v:on", "/c", bat_path], env)
    @fs.remove_file(bat_path) catch {
      _ => ()
    }
    code
  } else {
    spawn_and_wait("bash", ["-c", command], env)
  }
}
