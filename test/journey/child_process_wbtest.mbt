///| Child process isolation smoke tests (env override + wait/kill).

///|
async test "spawn_isolated_child: env override reaches the child" {
  match
    @async.with_timeout_opt(20_000, () => {
      @async.with_task_group(async fn(group) {
        let ctx = create_journey_context(
          ".", "unused-bin", "env_probe", "wbtest", 1,
        )
        // Cross-platform "print the home env var" child. `OS=Windows_NT`
        // is set on Windows and absent on POSIX.
        let is_windows = match @env.get_env_var("OS") {
          Some(v) => v == "Windows_NT"
          None => false
        }
        let (cmd, args) = if is_windows {
          ("cmd", ["/c", "echo %USERPROFILE%"])
        } else {
          ("/bin/sh", ["-c", "echo $HOME"])
        }
        let child = spawn_isolated_child(group, ctx, "probe", cmd, args)
        match child.wait_collect(10_000) {
          Ok((code, stdout, _stderr)) => {
            @debug.assert_eq(code, 0)
            @debug.assert_eq(stdout.contains(ctx.home), true)
          }
          Err(msg) => {
            println("spawn error: \{msg}")
            @debug.assert_eq(true, false)
          }
        }
      })
    }) {
    Some(_) => ()
    None => @debug.assert_eq(true, false)
  }
}

///|
async test "spawn_isolated_child: wait_collect timeout kills the child" {
  match
    @async.with_timeout_opt(20_000, () => {
      @async.with_task_group(async fn(group) {
        let ctx = create_journey_context(
          ".", "unused-bin", "hang_probe", "wbtest", 1,
        )
        // A child that sleeps far longer than the timeout.
        let is_windows = match @env.get_env_var("OS") {
          Some(v) => v == "Windows_NT"
          None => false
        }
        let (cmd, args) = if is_windows {
          ("cmd", ["/c", "ping -n 30 127.0.0.1 > nul"])
        } else {
          ("/bin/sh", ["-c", "sleep 30"])
        }
        let child = spawn_isolated_child(group, ctx, "hanging", cmd, args)
        // Bounded wait must fail, not hang — the watchdog contract.
        match child.wait_collect(1000) {
          Err(msg) => @debug.assert_eq(msg.contains("did not exit"), true)
          Ok(_) => @debug.assert_eq(true, false)
        }
      })
    }) {
    Some(_) => ()
    None => @debug.assert_eq(true, false)
  }
}
