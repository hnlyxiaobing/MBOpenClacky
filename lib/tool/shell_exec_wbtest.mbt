///|
/// White-box tests for shell_exec.
/// These tests run real shell commands via mb_system FFI (native-only).
async test "run_shell_command: basic echo" {
  let result = run_shell_command("echo hello_world")
  @debug.assert_eq(result.exit_code, 0)
  assert_true(result.output.trim().to_owned() == "hello_world")
}

///|
async test "run_shell_command: non-zero exit code" {
  let result = run_shell_command("exit 3")
  @debug.assert_eq(result.exit_code, 3)
}

///|
async test "run_shell_command: env vars inlined into command" {
  // Windows: use !VAR! (delayed expansion, enabled via cmd /v:on) so the
  // variable is expanded AFTER the inlined `set` prefix executes.
  let (cmd, expected) = if shell_is_windows() {
    ("echo VAL=!CLACKY_TEST_SHELLVAR!", "VAL=env_value_42")
  } else {
    ("echo VAL=$CLACKY_TEST_SHELLVAR", "VAL=env_value_42")
  }
  let result = run_shell_command(cmd, env_vars=[
    ("CLACKY_TEST_SHELLVAR", "env_value_42"),
  ])
  @debug.assert_eq(result.exit_code, 0)
  assert_true(result.output.trim().to_owned() == expected)
}

///|
async test "run_shell_command: two calls do not pollute env" {
  // First call sets CLACKY_TEST_A but not CLACKY_TEST_B
  // Second call sets CLACKY_TEST_B but not CLACKY_TEST_A
  // Windows: !VAR! delayed expansion — undefined vars expand to empty,
  // matching the Unix expectations below exactly.
  let cmd = if shell_is_windows() {
    "echo A=!CLACKY_TEST_A! B=!CLACKY_TEST_B!"
  } else {
    "echo A=$CLACKY_TEST_A B=$CLACKY_TEST_B"
  }
  let r1 = run_shell_command(cmd, env_vars=[("CLACKY_TEST_A", "aaa")])
  let r2 = run_shell_command(cmd, env_vars=[("CLACKY_TEST_B", "bbb")])
  @debug.assert_eq(r1.exit_code, 0)
  @debug.assert_eq(r2.exit_code, 0)
  let out1 = r1.output.trim().to_owned()
  let out2 = r2.output.trim().to_owned()
  if shell_is_windows() {
    // The command runs from a temp .bat under cmd.exe /v:on (see
    // terminal_exec.mbt); in batch context delayed expansion of an
    // UNDEFINED !VAR! yields empty text, so the expectations match the
    // Unix branch below. They still verify no cross-call pollution
    // (r1 has no bbb, r2 has no aaa).
    assert_true(out1 == "A=aaa B=")
    assert_true(out2 == "A= B=bbb")
  } else {
    // r1 should see A=aaa and B=empty (not polluted by r2)
    assert_true(out1 == "A=aaa B=")
    // r2 should see A=empty and B=bbb (not polluted by r1)
    assert_true(out2 == "A= B=bbb")
  }
}

///|
async test "run_shell_command: working directory" {
  if shell_is_windows() {
    let dir = shell_temp_dir()
    let result = run_shell_command("cd", working_dir=Some(dir))
    @debug.assert_eq(result.exit_code, 0)
    // `cd` with no args prints the current directory. Compare
    // case-insensitively: the filesystem may report different casing
    // than the TEMP variable.
    let out = result.output.trim().to_owned()
    assert_true(out.to_lower() == dir.to_lower())
  } else {
    let result = run_shell_command("pwd", working_dir=Some("/tmp"))
    @debug.assert_eq(result.exit_code, 0)
    assert_true(result.output.trim().to_owned() == "/tmp")
  }
}

///|
async test "run_shell_command: multi-line output" {
  // Windows: `&` is the cmd separator; a space before `&` would be echoed
  // literally, so no spaces around it. cmd emits CRLF — trim per line.
  let cmd = if shell_is_windows() {
    "echo line1&echo line2&echo line3"
  } else {
    "echo line1; echo line2; echo line3"
  }
  let result = run_shell_command(cmd)
  @debug.assert_eq(result.exit_code, 0)
  let lines = result.output.trim().to_owned().split("\n").to_array()
  @debug.assert_eq(lines.length(), 3)
  @debug.assert_eq(lines[0].trim().to_owned(), "line1")
  @debug.assert_eq(lines[1].trim().to_owned(), "line2")
  @debug.assert_eq(lines[2].trim().to_owned(), "line3")
}

///|
async test "run_shell_command: stderr captured" {
  let result = run_shell_command("echo to_stderr 1>&2; echo to_stdout")
  @debug.assert_eq(result.exit_code, 0)
  // Both stdout and stderr go to the same output file (2>&1)
  let out = result.output.trim().to_owned()
  assert_true(out.contains("to_stderr"))
  assert_true(out.contains("to_stdout"))
}

///|
async test "run_shell_command: env var with special chars" {
  // Windows: %VAR% would be expanded at parse time (before `set` runs), so
  // use !VAR! delayed expansion; cmd's echo needs no quoting here.
  let cmd = if shell_is_windows() {
    "echo !CLACKY_TEST_SPECIAL!"
  } else {
    "echo \"$CLACKY_TEST_SPECIAL\""
  }
  let result = run_shell_command(cmd, env_vars=[
    ("CLACKY_TEST_SPECIAL", "it's a test"),
  ])
  @debug.assert_eq(result.exit_code, 0)
  assert_true(result.output.trim().to_owned() == "it's a test")
}

///|
async test "run_shell_command: unrecognized command reports failure (exit-code regression)" {
  // Regression for %ERRORLEVEL% early expansion (#8): a command that fails
  // WITHOUT going through `exit N` must still report a non-zero exit code.
  // cmd.exe sets ERRORLEVEL=9009 for unrecognized commands; sh reports 127.
  let result = run_shell_command("clacky_definitely_not_a_command_xyz")
  if shell_is_windows() {
    @debug.assert_eq(result.exit_code, 9009)
  } else {
    @debug.assert_eq(result.exit_code, 127)
  }
}

///|
async test "run_shell_command: no env vars (empty default)" {
  let result = run_shell_command("echo no_env")
  @debug.assert_eq(result.exit_code, 0)
  assert_true(result.output.trim().to_owned() == "no_env")
}

///|
test "shell_escape_single: single quote escaped" {
  let escaped = shell_escape_single("hello'world")
  // Should produce: hello'\''world
  @debug.assert_eq(escaped, "hello'\\''world")
}

///|
test "build_env_prefix: empty env returns empty string" {
  let prefix = build_env_prefix([], false)
  @debug.assert_eq(prefix, "")
}

///|
test "build_env_prefix: unix format" {
  let prefix = build_env_prefix([("VAR1", "val1"), ("VAR2", "val2")], false)
  // Should be: export VAR1='val1' && export VAR2='val2' &&
  assert_true(prefix.contains("export VAR1='val1'"))
  assert_true(prefix.contains("export VAR2='val2'"))
  assert_true(prefix.has_suffix(" && "))
}
