///|
/// Shell hook trigger: fires shell hooks at 7 lifecycle events.
///
/// Ruby HookManager trigger semantics:
/// - Each hook's command is run via `@tool.run_shell_command` with env vars.
/// - Exit code 0 = allow, non-zero = deny (for veto-capable events).
/// - Observation-only events (after_tool_use, on_tool_error, on_iteration,
///   on_complete, session_rollback) ignore the exit code.
/// - Hook exceptions are caught and logged; a broken hook cannot crash the agent.
///
/// Reference: openclacky/lib/clacky/agent/hook_manager.rb

///|
/// Trigger all shell hooks matching the given event.
///
/// For veto-capable events (BeforeToolUse, OnStart), returns Deny if any
/// hook exits non-zero. For observation-only events, always returns Allow.
async fn Agent::trigger_shell_hooks(
  self : Agent,
  event : @hook.ShellHookEvent,
  tool_name? : String? = None,
  tool_args? : String? = None,
) -> @hook.HookExecResult {
  let matching = self.shell_hooks.filter(fn(h) { h.event == event })
  if matching.is_empty() {
    return @hook.Allow
  }
  let is_veto = match event {
    @hook.BeforeToolUse | @hook.OnStart => true
    _ => false
  }
  for h in matching {
    let env_vars : Array[(String, String)] = [
      ("CLACKY_HOOK_EVENT", event.event_name()),
      ("CLACKY_SESSION_ID", self.session_id),
      ("CLACKY_WORKING_DIR", self.working_dir),
    ]
    match h.name {
      Some(n) => env_vars.push(("CLACKY_HOOK_NAME", n))
      None => ()
    }
    match tool_name {
      Some(name) => env_vars.push(("CLACKY_HOOK_TOOL_NAME", name))
      None => ()
    }
    match tool_args {
      Some(args) => env_vars.push(("CLACKY_HOOK_TOOL_ARGS", args))
      None => ()
    }
    let result = @tool.run_shell_command(h.command, env_vars=env_vars)
    if result.exit_code != 0 {
      if is_veto {
        let reason = result.output.trim().to_owned()
        return @hook.Deny(
          if reason.is_empty() {
            "denied by hook"
          } else {
            reason
          },
        )
      }
    }
  }
  @hook.Allow
}
