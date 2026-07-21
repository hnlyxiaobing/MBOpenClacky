///|
test "run_shell_command captures output and exit code" {
  let r = @tool.run_shell_command("echo hello")
  @debug.assert_eq(r.exit_code, 0)
  assert_true(r.output.contains("hello"))
}

///|
test "run_shell_command reports non-zero exit code" {
  let r = @tool.run_shell_command("exit 3")
  @debug.assert_eq(r.exit_code, 3)
}

///|
test "run_shell_command passes env vars to child process" {
  // Windows: !VAR! delayed expansion (cmd /v:on) — %VAR% would be expanded
  // at parse time, before the inlined `set` prefix executes.
  let cmd = if @tool.shell_is_windows() {
    "echo val=!CLACKY_TEST_VAR!"
  } else {
    "echo val=$CLACKY_TEST_VAR"
  }
  let r = @tool.run_shell_command(cmd, env_vars=[("CLACKY_TEST_VAR", "42")])
  @debug.assert_eq(r.exit_code, 0)
  assert_true(r.output.contains("val=42"))
}

///|
test "execute_hook runs command and succeeds" {
  // Windows has no `test` builtin; use an `if` comparison instead.
  let command = if @tool.shell_is_windows() {
    "if not \"!CLACKY_SESSION_ID!\"==\"sess-1\" exit 1"
  } else {
    "test \"$CLACKY_SESSION_ID\" = sess-1"
  }
  let hook : HookConfig = {
    name: "test-hook",
    event: "on_start",
    command,
    enabled: true,
  }
  let ctx : HookContext = {
    session_id: "sess-1",
    message: None,
    working_dir: ".",
  }
  match execute_hook(hook, ctx) {
    Ok(_) => ()
    Err(e) => fail("hook should succeed: \{e}")
  }
}

///|
test "execute_hook returns Err on non-zero exit" {
  let hook : HookConfig = {
    name: "failing-hook",
    event: "on_start",
    command: "exit 7",
    enabled: true,
  }
  let ctx : HookContext = { session_id: "s", message: None, working_dir: "." }
  match execute_hook(hook, ctx) {
    Ok(_) => fail("hook should fail")
    Err(e) => assert_true(e.contains("exit code 7"))
  }
}

///|
test "execute_hook skips disabled hooks" {
  let hook : HookConfig = {
    name: "disabled",
    event: "on_start",
    command: "exit 1",
    enabled: false,
  }
  let ctx : HookContext = { session_id: "s", message: None, working_dir: "." }
  assert_true(execute_hook(hook, ctx) is Ok(_))
}

///|
test "execute_hook rejects empty command" {
  let hook : HookConfig = {
    name: "empty",
    event: "on_start",
    command: "  ",
    enabled: true,
  }
  let ctx : HookContext = { session_id: "s", message: None, working_dir: "." }
  assert_true(execute_hook(hook, ctx) is Err(_))
}

///|
test "apply_patches executes commands and skips metadata-only patches" {
  let loader = PatchLoader::new("/nonexistent")
  let patches : Array[PatchInfo] = [
    {
      name: "meta-only",
      version: "1.0.0",
      description: "no command",
      target_module: "agent",
      command: "",
      enabled: true,
    },
    {
      name: "runs-ok",
      version: "1.0.0",
      description: "echo test",
      target_module: "agent",
      // Windows has no `test` builtin; use an `if` comparison instead.
      command: if @tool.shell_is_windows() {
        "if not \"!CLACKY_PATCH_NAME!\"==\"runs-ok\" exit 1"
      } else {
        "test \"$CLACKY_PATCH_NAME\" = runs-ok"
      },
      enabled: true,
    },
  ]
  match loader.apply_patches(patches) {
    Ok(_) => ()
    Err(e) => fail("patches should apply: \{e}")
  }
}

///|
test "apply_patches reports failing patch" {
  let loader = PatchLoader::new("/nonexistent")
  let patches : Array[PatchInfo] = [
    {
      name: "bad-patch",
      version: "0.1.0",
      description: "",
      target_module: "core",
      command: "exit 5",
      enabled: true,
    },
  ]
  match loader.apply_patches(patches) {
    Ok(_) => fail("should report failure")
    Err(e) => assert_true(e.contains("bad-patch"))
  }
}

///|
test "register_extensions rejects duplicate names and bad routes" {
  let mk_route = fn(
    http_method : String,
    path : String,
  ) -> @web.ExtensionRoute {
    {
      http_method,
      path,
      handler_name: "h",
      command: "",
      description: "",
      timeout_ms: 1000,
    }
  }
  // Duplicate extension name
  let dup : Array[@web.ApiExtension] = [
    { name: "a", version: "1", routes: [], enabled: true },
    { name: "a", version: "2", routes: [], enabled: true },
  ]
  assert_true(register_extensions(dup) is Err(_))
  // Duplicate route within one extension
  let dup_route : Array[@web.ApiExtension] = [
    {
      name: "b",
      version: "1",
      routes: [mk_route("GET", "/x"), mk_route("get", "/x")],
      enabled: true,
    },
  ]
  assert_true(register_extensions(dup_route) is Err(_))
  // Unsupported method
  let bad_method : Array[@web.ApiExtension] = [
    {
      name: "c",
      version: "1",
      routes: [mk_route("PATCH", "/y")],
      enabled: true,
    },
  ]
  assert_true(register_extensions(bad_method) is Err(_))
}

///|
test "register_extensions accepts valid extensions" {
  let ok : Array[@web.ApiExtension] = [
    {
      name: "good",
      version: "1.0",
      routes: [
        {
          http_method: "GET",
          path: "/status",
          handler_name: "status",
          command: "",
          description: "",
          timeout_ms: 5000,
        },
      ],
      enabled: true,
    },
  ]
  assert_true(register_extensions(ok) is Ok(_))
}
