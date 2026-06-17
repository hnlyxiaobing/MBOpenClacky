///|
test "parse_hook_event_before_tool_use" {
  let event = parse_hook_event("before_tool_use")
  assert_eq(event, Some(BeforeToolUse))
}

///|
test "parse_hook_event_after_tool_use" {
  let event = parse_hook_event("after_tool_use")
  assert_eq(event, Some(AfterToolUse))
}

///|
test "parse_hook_event_on_tool_error" {
  let event = parse_hook_event("on_tool_error")
  assert_eq(event, Some(OnToolError))
}

///|
test "parse_hook_event_on_start" {
  let event = parse_hook_event("on_start")
  assert_eq(event, Some(OnStart))
}

///|
test "parse_hook_event_on_iteration" {
  let event = parse_hook_event("on_iteration")
  assert_eq(event, Some(OnIteration))
}

///|
test "parse_hook_event_on_complete" {
  let event = parse_hook_event("on_complete")
  assert_eq(event, Some(OnComplete))
}

///|
test "parse_hook_event_session_rollback" {
  let event = parse_hook_event("session_rollback")
  assert_eq(event, Some(SessionRollback))
}

///|
test "parse_hook_event_invalid" {
  let event = parse_hook_event("unknown_event")
  assert_true(event is None)
}

///|
test "shell_hook_event_name_roundtrip" {
  let events = [
    BeforeToolUse,
    AfterToolUse,
    OnToolError,
    OnStart,
    OnIteration,
    OnComplete,
    SessionRollback,
  ]
  for event in events {
    let name = event.event_name()
    let parsed = parse_hook_event(name)
    assert_eq(parsed, Some(event))
  }
}

///|
test "shell_hook_loader_new" {
  let loader = ShellHookLoader::new("/home/user/.mbopenclacky")
  assert_eq(loader.config_path, "/home/user/.mbopenclacky/hooks.yml")
  assert_eq(loader.scripts_dir, "/home/user/.mbopenclacky/hook-scripts/")
}

///|
test "shell_hook_loader_load_ok" {
  let loader = ShellHookLoader::new("/tmp")
  let result = loader.load()
  assert_true(result is Ok(_))
}

///|
test "shell_hook_loader_hook_count_empty" {
  let loader = ShellHookLoader::new("/tmp")
  assert_eq(loader.hook_count(), 0)
}

///|
test "shell_hook_loader_has_hooks_false" {
  let loader = ShellHookLoader::new("/tmp")
  assert_false(loader.has_hooks_for(BeforeToolUse))
  assert_false(loader.has_hooks_for(OnComplete))
}

///|
test "shell_hook_loader_hooks_for_event_empty" {
  let loader = ShellHookLoader::new("/tmp")
  let hooks = loader.hooks_for_event(BeforeToolUse)
  assert_eq(hooks.length(), 0)
}

///|
test "shell_hook_loader_with_hooks" {
  let loader = ShellHookLoader::new("/tmp")
  let hook : ShellHook = {
    name: Some("guard"),
    command: "/usr/local/bin/guard.sh",
    timeout: 10,
    event: BeforeToolUse,
  }
  loader.config.hooks.set("before_tool_use", [hook])
  assert_true(loader.has_hooks_for(BeforeToolUse))
  assert_eq(loader.hook_count(), 1)
  let hooks = loader.hooks_for_event(BeforeToolUse)
  assert_eq(hooks.length(), 1)
}

///|
test "shell_hook_loader_execute_hook_returns_allow" {
  let loader = ShellHookLoader::new("/tmp")
  let hook : ShellHook = {
    name: Some("test"),
    command: "echo hello",
    timeout: 5,
    event: OnComplete,
  }
  let result = loader.execute_hook(hook, Json::null())
  assert_eq(result, Allow)
}

///|
test "shell_hook_loader_scaffold" {
  let result = ShellHookLoader::scaffold("/tmp/test")
  assert_true(result is Ok(_))
}

///|
test "default_hooks_yml_content" {
  let content = default_hooks_yml()
  assert_true(content.contains("MBOpenClacky Shell Hooks"))
  assert_true(content.contains("before_tool_use"))
}

///|
test "default_hook_timeout" {
  assert_eq(get_default_hook_timeout(), 10)
}

///|
test "hook_exec_result_variants" {
  let allow : HookExecResult = Allow
  let deny : HookExecResult = Deny("blocked")
  let err : HookExecResult = Error("timeout")
  assert_eq(allow, Allow)
  assert_eq(deny, Deny("blocked"))
  assert_eq(err, Error("timeout"))
}
