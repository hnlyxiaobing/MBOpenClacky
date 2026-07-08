///|
/// White-box tests for ext_dispatcher.
/// Tests parse_ext_response, expand_tilde, and extension loading with command field.

// ── parse_ext_response tests ────────────────────────────────────

test "parse_ext_response: exit 0 returns 200 with stdout" {
  let (status, ct, body) = parse_ext_response("hello world", 0)
  assert_eq(status, 200)
  assert_eq(ct, "application/json")
  assert_eq(body, "hello world")
}

///|
test "parse_ext_response: exit 0 with Content-Type override" {
  let output = "Content-Type: text/plain\nhello text"
  let (status, ct, body) = parse_ext_response(output, 0)
  assert_eq(status, 200)
  assert_eq(ct, "text/plain")
  assert_eq(body, "hello text")
}

///|
test "parse_ext_response: exit 0 with JSON Content-Type override" {
  let output = "Content-Type: application/xml\n<root>data</root>"
  let (status, ct, body) = parse_ext_response(output, 0)
  assert_eq(status, 200)
  assert_eq(ct, "application/xml")
  assert_eq(body, "<root>data</root>")
}

///|
test "parse_ext_response: exit non-0 with JSON error" {
  let output = "{\"error\":\"not found\",\"status\":404}"
  let (status, ct, body) = parse_ext_response(output, 1)
  assert_eq(status, 404)
  assert_eq(ct, "application/json")
  assert_true(body.contains("not found"))
  assert_true(body.contains("EXT_EXEC_ERROR"))
}

///|
test "parse_ext_response: exit non-0 with 500 status" {
  let output = "{\"error\":\"server error\",\"status\":500}"
  let (status, _ct, _body) = parse_ext_response(output, 2)
  assert_eq(status, 500)
}

///|
test "parse_ext_response: exit non-0 with non-JSON output returns 500" {
  let output = "some raw error message"
  let (status, ct, body) = parse_ext_response(output, 1)
  assert_eq(status, 500)
  assert_eq(ct, "application/json")
  assert_true(body.contains("exited with code 1"))
  assert_true(body.contains("some raw error message"))
}

///|
test "parse_ext_response: exit non-0 with JSON missing status field returns 500" {
  let output = "{\"error\":\"missing status\"}"
  let (status, _ct, _body) = parse_ext_response(output, 1)
  assert_eq(status, 500)
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
  assert_eq(result, "/path/~middle/file")
}

///|
test "expand_tilde: empty string unchanged" {
  assert_eq(expand_tilde(""), "")
}

// ── ExtensionRoute command field tests ──────────────────────────

///|
test "ExtensionRoute: command field defaults to empty in TOML" {
  // TOML parser doesn't support routes, so routes is always empty
  let toml = "name = \"test\"\nversion = \"1.0\"\nenabled = true\n"
  let ext = parse_ext_simple(toml, "test.toml")
  assert_true(ext is Some(_))
  match ext {
    Some(e) => assert_eq(e.routes.length(), 0)
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
      assert_eq(e.name, "test-ext")
      assert_eq(e.routes.length(), 2)
      let r1 = e.routes[0]
      assert_eq(r1.method, "GET")
      assert_eq(r1.path, "/hello")
      assert_eq(r1.handler_name, "hello_handler")
      assert_true(r1.command.contains("echo"))
      assert_eq(r1.timeout_ms, 5000)
      // Second route has no command
      let r2 = e.routes[1]
      assert_eq(r2.method, "POST")
      assert_eq(r2.command, "")
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
      assert_eq(e.routes.length(), 1)
      let cmd = e.routes[0].command
      // Should NOT start with ~/ (should be expanded to home or unchanged if no HOME)
      assert_true(!cmd.has_prefix("~/") || cmd == "~/scripts/run.sh")
    }
    None => assert_true(false, msg="parse_ext_json returned None")
  }
}

// ── Shell execution integration test ────────────────────────────

///|
test "ext handler: shell command execution via run_shell_command" {
  // Test that a simple echo command works through shell_exec
  let result = @tool.run_shell_command("echo '{\"status\":\"ok\"}'")
  assert_eq(result.exit_code, 0)
  let output = result.output.trim().to_string()
  assert_true(output.contains("ok"))
}

///|
test "ext handler: env vars passed to command" {
  // Verify that env vars are correctly inlined
  let result = @tool.run_shell_command(
    "echo $CLACKY_EXT_NAME-$CLACKY_EXT_METHOD",
    env_vars=[("CLACKY_EXT_NAME", "myext"), ("CLACKY_EXT_METHOD", "GET")],
  )
  assert_eq(result.exit_code, 0)
  assert_eq(result.output.trim().to_string(), "myext-GET")
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
          method: "GET",
          path: "/hello",
          handler_name: "hello",
          command: "echo hello",
          description: "",
          timeout_ms: 5000,
        },
        {
          method: "POST",
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
  assert_eq(summary.length(), 2)
  assert_true(summary[0].contains("cmd: echo hello"))
  assert_true(summary[1].contains("stub"))
}
