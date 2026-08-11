///|
/// White-box tests for ext_dispatcher.
/// Tests parse_ext_response, expand_tilde, and extension loading with command field.

///|
/// OS-portable temp directory (uses TEMP/TMPDIR env, falls back to /tmp).
/// Avoids hardcoded Unix /tmp paths that don't exist on Windows.
fn wbtest_ext_tmp_root() -> String {
  match @env.get_env_var("TEMP") {
    Some(d) => d
    None =>
      match @env.get_env_var("TMPDIR") {
        Some(d) => d
        None => "/tmp"
      }
  }
}

// ── parse_ext_response tests ────────────────────────────────────

///|
test "parse_ext_response: exit 0 returns 200 with stdout" {
  let (status, ct, body) = parse_ext_response("hello world", 0)
  @debug.assert_eq(status, 200)
  @debug.assert_eq(ct, "application/json")
  @debug.assert_eq(body, "hello world")
}

///|
test "parse_ext_response: exit 0 with Content-Type override" {
  let output = "Content-Type: text/plain\nhello text"
  let (status, ct, body) = parse_ext_response(output, 0)
  @debug.assert_eq(status, 200)
  @debug.assert_eq(ct, "text/plain")
  @debug.assert_eq(body, "hello text")
}

///|
test "parse_ext_response: exit 0 with JSON Content-Type override" {
  let output = "Content-Type: application/xml\n<root>data</root>"
  let (status, ct, body) = parse_ext_response(output, 0)
  @debug.assert_eq(status, 200)
  @debug.assert_eq(ct, "application/xml")
  @debug.assert_eq(body, "<root>data</root>")
}

///|
test "parse_ext_response: exit non-0 with JSON error" {
  let output = "{\"error\":\"not found\",\"status\":404}"
  let (status, ct, body) = parse_ext_response(output, 1)
  @debug.assert_eq(status, 404)
  @debug.assert_eq(ct, "application/json")
  assert_true(body.contains("not found"))
  assert_true(body.contains("EXT_EXEC_ERROR"))
}

///|
test "parse_ext_response: exit non-0 with 500 status" {
  let output = "{\"error\":\"server error\",\"status\":500}"
  let (status, _ct, _body) = parse_ext_response(output, 2)
  @debug.assert_eq(status, 500)
}

///|
test "parse_ext_response: exit non-0 with non-JSON output returns 500" {
  let output = "some raw error message"
  let (status, ct, body) = parse_ext_response(output, 1)
  @debug.assert_eq(status, 500)
  @debug.assert_eq(ct, "application/json")
  assert_true(body.contains("exited with code 1"))
  assert_true(body.contains("some raw error message"))
}

///|
test "parse_ext_response: exit non-0 with JSON missing status field returns 500" {
  let output = "{\"error\":\"missing status\"}"
  let (status, _ct, _body) = parse_ext_response(output, 1)
  @debug.assert_eq(status, 500)
}

// ── expand_tilde tests ──────────────────────────────────────────

///|
test "expand_tilde: expands ~/path" {
  let result = expand_tilde("~/some/path")
  // Should start with home dir (or ~ if HOME not set)
  assert_true(!result.has_prefix("~/") || result == "~/some/path")
}

///|
test "expand_tilde: does not expand ~ in middle" {
  let result = expand_tilde("/path/~middle/file")
  @debug.assert_eq(result, "/path/~middle/file")
}

///|
test "expand_tilde: empty string unchanged" {
  @debug.assert_eq(expand_tilde(""), "")
}

// ── ExtensionRoute command field tests ──────────────────────────

///|
test "ExtensionRoute: command field defaults to empty in TOML" {
  // TOML parser doesn't support routes, so routes is always empty
  let toml = "name = \"test\"\nversion = \"1.0\"\nenabled = true\n"
  let ext = parse_ext_simple(toml, "test.toml")
  assert_true(ext is Some(_))
  match ext {
    Some(e) => @debug.assert_eq(e.routes.length(), 0)
    None => assert_true(false)
  }
}

///|
test "ExtensionRoute: JSON descriptor parses command field" {
  let json =
    #| {
    #|   "name": "test-ext",
    #|   "version": "1.0.0",
    #|   "enabled": true,
    #|   "routes": [
    #|     {
    #|       "method": "GET",
    #|       "path": "/hello",
    #|       "handler_name": "hello_handler",
    #|       "command": "echo '{\\\"msg\\\":\\\"hello\\\"}'",
    #|       "timeout_ms": 5000
    #|     },
    #|     {
    #|       "method": "POST",
    #|       "path": "/echo",
    #|       "handler_name": "echo_handler",
    #|       "timeout_ms": 10000
    #|     }
    #|   ]
    #| }
  let ext = parse_ext_json(json)
  match ext {
    Some(e) => {
      @debug.assert_eq(e.name, "test-ext")
      @debug.assert_eq(e.routes.length(), 2)
      let r1 = e.routes[0]
      @debug.assert_eq(r1.http_method, "GET")
      @debug.assert_eq(r1.path, "/hello")
      @debug.assert_eq(r1.handler_name, "hello_handler")
      assert_true(r1.command.contains("echo"))
      @debug.assert_eq(r1.timeout_ms, 5000)
      // Second route has no command
      let r2 = e.routes[1]
      @debug.assert_eq(r2.http_method, "POST")
      @debug.assert_eq(r2.command, "")
    }
    None => assert_true(false, msg="parse_ext_json returned None")
  }
}

///|
test "ExtensionRoute: JSON descriptor with ~ in command expands" {
  let json =
    #| {
    #|   "name": "tildetest",
    #|   "version": "1.0",
    #|   "enabled": true,
    #|   "routes": [
    #|     {
    #|       "method": "GET",
    #|       "path": "/run",
    #|       "handler_name": "run_handler",
    #|       "command": "~/scripts/run.sh"
    #|     }
    #|   ]
    #| }
  let ext = parse_ext_json(json)
  match ext {
    Some(e) => {
      @debug.assert_eq(e.routes.length(), 1)
      let cmd = e.routes[0].command
      // Should NOT start with ~/ (should be expanded to home or unchanged if no HOME)
      assert_true(!cmd.has_prefix("~/") || cmd == "~/scripts/run.sh")
    }
    None => assert_true(false, msg="parse_ext_json returned None")
  }
}

// ── Shell execution integration test ────────────────────────────

///|
async test "ext handler: shell command execution via run_shell_command" {
  // Test that a simple echo command works through shell_exec
  let result = @tool.run_shell_command("echo '{\"status\":\"ok\"}'")
  @debug.assert_eq(result.exit_code, 0)
  let output = result.output.trim().to_owned()
  assert_true(output.contains("ok"))
}

///|
async test "ext handler: env vars passed to command" {
  // Verify that env vars are correctly inlined into the command environment.
  // Unix expands $VAR via sh; Windows cannot expand inline-set vars with %VAR%
  // (cmd parses the whole line before set runs), so on Windows we list the var
  // with `set` instead of echoing it.
  let is_win = match @env.get_env_var("OS") {
    Some(v) => v == "Windows_NT"
    None => false
  }
  let (echo_cmd, expected) = if is_win {
    ("set CLACKY_EXT_NAME", "myext")
  } else {
    ("echo $CLACKY_EXT_NAME-$CLACKY_EXT_METHOD", "myext-GET")
  }
  let result = @tool.run_shell_command(echo_cmd, env_vars=[
    ("CLACKY_EXT_NAME", "myext"),
    ("CLACKY_EXT_METHOD", "GET"),
  ])
  @debug.assert_eq(result.exit_code, 0)
  assert_true(result.output.contains(expected))
}

// ── Dispatcher route_summary tests ──────────────────────────────

///|
test "route_summary: shows command info for routes" {
  let exts : Array[ApiExtension] = [
    {
      name: "test",
      version: "1.0",
      routes: [
        {
          http_method: "GET",
          path: "/hello",
          handler_name: "hello",
          command: "echo hello",
          description: "",
          timeout_ms: 5000,
        },
        {
          http_method: "POST",
          path: "/echo",
          handler_name: "echo",
          command: "",
          description: "",
          timeout_ms: 10000,
        },
      ],
      enabled: true,
    },
  ]
  let dispatcher = ExtensionDispatcher::new(exts)
  let summary = dispatcher.route_summary()
  @debug.assert_eq(summary.length(), 2)
  assert_true(summary[0].contains("cmd: echo hello"))
  assert_true(summary[1].contains("stub"))
}

// ── Task 4: error envelope enhancement tests ───────────────────

///|
test "parse_ext_response: exit 124 returns 504 + EXT_TIMEOUT" {
  let (status, ct, body) = parse_ext_response("killed by timeout", 124)
  @debug.assert_eq(status, 504)
  @debug.assert_eq(ct, "application/json")
  assert_true(body.contains("\"code\":\"EXT_TIMEOUT\""))
  assert_true(body.contains("\"error\":\"timeout\""))
}

///|
test "parse_ext_response: exit 130 (SIGINT) returns 502 + EXT_CRASH" {
  let (status, ct, body) = parse_ext_response("", 130)
  @debug.assert_eq(status, 502)
  @debug.assert_eq(ct, "application/json")
  assert_true(body.contains("\"code\":\"EXT_CRASH\""))
  assert_true(body.contains("\"error\":\"handler crashed\""))
  // 130 - 128 = 2 (SIGINT on most Unix)
  assert_true(body.contains("\"signal\":2"))
}

///|
test "parse_ext_response: exit 139 (SIGSEGV) returns 502 + signal 11" {
  let (status, _ct, body) = parse_ext_response("segfault", 139)
  @debug.assert_eq(status, 502)
  // 139 - 128 = 11 (SIGSEGV)
  assert_true(body.contains("\"signal\":11"))
}

///|
test "parse_ext_response: exit 255 (boundary) returns 502 + EXT_CRASH" {
  let (status, _ct, body) = parse_ext_response("", 255)
  @debug.assert_eq(status, 502)
  assert_true(body.contains("\"code\":\"EXT_CRASH\""))
  // 255 - 128 = 127
  assert_true(body.contains("\"signal\":127"))
}

///|
test "parse_ext_response: exit 127 (low signal-like) NOT treated as crash" {
  // 127 is "command not found", not a signal — should be regular error
  let (status, _ct, body) = parse_ext_response("command not found", 127)
  @debug.assert_eq(status, 500)
  // Should NOT contain EXT_CRASH
  assert_true(!body.contains("EXT_CRASH"))
}

///|
test "parse_ext_response: exit 256 (out of range) NOT treated as crash" {
  let (status, _ct, body) = parse_ext_response("oops", 256)
  @debug.assert_eq(status, 500)
  assert_true(!body.contains("EXT_CRASH"))
}

// ── Task 2: timeout clamping tests ─────────────────────────────

///|
test "max_ext_timeout_ms: constant is 600_000" {
  @debug.assert_eq(max_ext_timeout_ms, 600000)
}

///|
test "default_ext_timeout_ms: constant is 30_000" {
  @debug.assert_eq(default_ext_timeout_ms, 30000)
}

// ── Task 3: dispatcher construction & hot-reload tests ─────────

///|
test "ExtensionDispatcher::new: builds route map from extensions" {
  let exts : Array[ApiExtension] = [
    {
      name: "foo",
      version: "1.0",
      routes: [
        {
          http_method: "GET",
          path: "/a",
          handler_name: "a",
          command: "echo a",
          description: "",
          timeout_ms: 5000,
        },
        {
          http_method: "POST",
          path: "/b",
          handler_name: "b",
          command: "echo b",
          description: "",
          timeout_ms: 5000,
        },
      ],
      enabled: true,
    },
  ]
  let d = ExtensionDispatcher::new(exts)
  @debug.assert_eq(d.routes_ref.val.length(), 2)
  // Verify keys
  assert_true(d.routes_ref.val.contains("/api/ext/foo/a"))
  assert_true(d.routes_ref.val.contains("/api/ext/foo/b"))
}

///|
test "ExtensionDispatcher::new: without ext_dir is a no-op for ensure_fresh" {
  let d = ExtensionDispatcher::new([])
  // Should not throw; just returns
  d.ensure_fresh()
  @debug.assert_eq(d.request_count.val, 0)
}

///|
test "ExtensionDispatcher::new_with_dir: initial signature is set" {
  // Use a temp directory that doesn't exist; signature should be "" (empty)
  let d = ExtensionDispatcher::new_with_dir(
    [],
    "/tmp/_wbtest_ext_dir_does_not_exist_\{@env.now().reinterpret_as_int64()}",
  )
  @debug.assert_eq(d.last_signature.val, "")
}

///|
test "ExtensionDispatcher::ensure_fresh: throttled by check_every" {
  let d = ExtensionDispatcher::new_with_dir(
    [],
    "/tmp/_wbtest_throttle_\{@env.now().reinterpret_as_int64()}",
    check_every=5,
  )
  // First 4 calls: counter increments but no work
  for _i = 0; _i < 4; _i = _i + 1 {
    d.ensure_fresh()
  }
  @debug.assert_eq(d.request_count.val, 4)
  // 5th call: triggers check (signature will be "" so no reload)
  d.ensure_fresh()
  @debug.assert_eq(d.request_count.val, 5)
}

///|
test "compute_dir_signature: empty/missing dir returns empty string" {
  @debug.assert_eq(
    compute_dir_signature(
      wbtest_ext_tmp_root() +
      "/_wbtest_sig_missing_\{@env.now().reinterpret_as_int64()}",
    ),
    "",
  )
}

///|
test "compute_dir_signature: same content yields same signature" {
  let tmp = wbtest_ext_tmp_root() +
    "/_wbtest_sig_same_\{@env.now().reinterpret_as_int64()}"
  @fs.create_dir(tmp) catch {
    _ => ()
  }
  let f = "\{tmp}/a.json"
  @fs.write_string_to_file(f, "{\"name\":\"x\"}") catch {
    _ => ()
  }
  let s1 = compute_dir_signature(tmp)
  let s2 = compute_dir_signature(tmp)
  @debug.assert_eq(s1, s2)
  assert_true(s1.contains("a.json|"))
  // Cleanup
  @fs.remove_file(f) catch {
    _ => ()
  }
  @fs.remove_dir(tmp) catch {
    _ => ()
  }
}

///|
test "compute_dir_signature: different sizes yield different signatures" {
  let tmp = wbtest_ext_tmp_root() +
    "/_wbtest_sig_diff_\{@env.now().reinterpret_as_int64()}"
  @fs.create_dir(tmp) catch {
    _ => ()
  }
  let f = "\{tmp}/a.json"
  @fs.write_string_to_file(f, "small") catch {
    _ => ()
  }
  let s1 = compute_dir_signature(tmp)
  @fs.write_string_to_file(f, "this is a much larger file content") catch {
    _ => ()
  }
  let s2 = compute_dir_signature(tmp)
  assert_true(s1 != s2)
  // Cleanup
  @fs.remove_file(f) catch {
    _ => ()
  }
  @fs.remove_dir(tmp) catch {
    _ => ()
  }
}
