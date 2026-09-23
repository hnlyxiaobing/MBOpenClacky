///|
/// Env-isolated child process management for journey E2E.
///
/// Children are spawned via @process.spawn with no_wait=true inside the
/// journey's task group: when the group exits (normally or via watchdog
/// cancellation), surviving children are terminated automatically. stdout
/// and stderr are drained by background tasks so pipes never fill up and
/// the output is captured for evidence.

///|
/// Env override map that isolates the child from the real user home:
/// USERPROFILE/HOME point at the sandbox home, CLACKY_WORKSPACE_DIR at the
/// sandbox workspace. extra_env entries take precedence over inherited
/// values on both Windows and POSIX.
pub fn journey_child_env(ctx : JourneyContext) -> Map[String, String] {
  let env : Map[String, String] = Map([])
  env["USERPROFILE"] = ctx.home
  env["HOME"] = ctx.home
  env["CLACKY_WORKSPACE_DIR"] = ctx.workspace
  env
}

///|
/// Handle to a journey child process with captured output.
pub(all) struct ChildHandle {
  process : @process.Process
  /// What this child is ("server" / "cli" / ...).
  label : String
  /// Accumulated stdout (final after exit + drain).
  mut stdout : String
  /// Accumulated stderr (final after exit + drain).
  mut stderr : String
  /// Signaled when the stdout drain task reaches EOF.
  stdout_done : @aqueue.Queue[Unit]
  /// Signaled when the stderr drain task reaches EOF.
  stderr_done : @aqueue.Queue[Unit]
}

///|
/// Spawn an env-isolated child with captured stdout/stderr.
/// `hard_kill=true` terminates immediately on cancel (crash simulation);
/// `false` tries a graceful stop first (normal teardown).
pub async fn spawn_isolated_child(
  group : @async.TaskGroup[Unit],
  ctx : JourneyContext,
  label : String,
  cmd : String,
  args : Array[String],
  hard_kill? : Bool = true,
) -> ChildHandle {
  let (out_r, out_w) = @process.read_from_process()
  let (err_r, err_w) = @process.read_from_process()
  let cancel = if hard_kill {
    @process.hard_cancel()
  } else {
    @process.graceful_cancel(timeout=3000)
  }
  let process = @process.spawn(
    group,
    cmd,
    args,
    extra_env=journey_child_env(ctx),
    inherit_env=true,
    stdout=out_w,
    stderr=err_w,
    cwd=ctx.workspace,
    cancel_handler=cancel,
    no_wait=true,
  )
  let handle : ChildHandle = {
    process,
    label,
    stdout: "",
    stderr: "",
    stdout_done: @aqueue.Queue(kind=Unbounded),
    stderr_done: @aqueue.Queue(kind=Unbounded),
  }
  // Drain tasks are no_wait: the group cancels them at exit instead of
  // waiting for EOF (an orphaned grandchild can hold the pipe write end
  // after a hard kill, which would otherwise hang teardown forever).
  group.spawn_bg(no_wait=true, async fn() {
    let data = out_r.read_all()
    handle.stdout = data.text() catch { _ => "" }
    out_r.close()
    handle.stdout_done.put(())
  })
  group.spawn_bg(no_wait=true, async fn() {
    let data = err_r.read_all()
    handle.stderr = data.text() catch { _ => "" }
    err_r.close()
    handle.stderr_done.put(())
  })
  handle
}

///|
/// Wait for the drain tasks to finish so stdout/stderr are final.
/// Bounded so a broken pipe can never hang a teardown.
async fn ChildHandle::drain_output(self : ChildHandle) -> Unit {
  @async.with_timeout_opt(5000, () => self.stdout_done.get()) |> ignore
  @async.with_timeout_opt(5000, () => self.stderr_done.get()) |> ignore
}

///|
/// Wait for exit (with watchdog), then collect (exit_code, stdout, stderr).
/// On timeout the child is killed and an Err is returned — a hanging child
/// is a journey failure, never a runner hang.
pub async fn ChildHandle::wait_collect(
  self : ChildHandle,
  timeout_ms : Int,
) -> Result[(Int, String, String), String] {
  match @async.with_timeout_opt(timeout_ms, () => self.process.wait()) {
    Some(code) => {
      ChildHandle::drain_output(self)
      Ok((code, self.stdout, self.stderr))
    }
    None => {
      self.process.cancel()
      ignore(self.process.wait())
      Err("\{self.label}: child did not exit within \{timeout_ms}ms (killed)")
    }
  }
}

///|
/// Kill the child (per its cancel handler) and collect final output.
/// Safe on an already-exited child.
pub async fn ChildHandle::kill_and_collect(
  self : ChildHandle,
) -> (Int, String, String) {
  self.process.cancel()
  let code = self.process.wait()
  ChildHandle::drain_output(self)
  (code, self.stdout, self.stderr)
}

///|
/// Kill the child without collecting (fire-and-forget teardown).
pub async fn ChildHandle::kill(self : ChildHandle) -> Unit {
  self.process.cancel()
  ignore(self.process.wait())
}

// ── Port probing ────────────────────────────────────────────────────────────

///|
/// Whether anything is currently listening on a loopback port.
pub async fn port_is_listening(port : Int) -> Bool {
  let conn = @socket.Tcp::connect_to_host("127.0.0.1", port~) catch {
    _ => return false
  }
  conn.close()
  true
}

///|
/// Pick the first port at/after `base` with nothing listening
/// (bounded retries; returns the last candidate if all are busy).
pub async fn choose_free_port(base : Int, tries? : Int = 3) -> Int {
  let mut port = base
  for i = 0; i < tries; i = i + 1 {
    if !port_is_listening(port) {
      return port
    }
    port = port + 1
  }
  port
}
