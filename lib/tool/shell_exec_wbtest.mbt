///|
/// White-box tests for shell_exec.
/// These tests run real shell commands via mb_system FFI (native-only).
test "run_shell_command: basic echo" {
  let result = run_shell_command("echo hello_world")
  @debug.assert_eq(result.exit_code, 0)
  assert_true(result.output.trim().to_owned() == "hello_world")
}

///|
test "run_shell_command: non-zero exit code" {
  let result = run_shell_command("exit 3")
  @debug.assert_eq(result.exit_code, 3)
}

///|
test "run_shell_command: env vars inlined into command" {
  let result = run_shell_command("echo VAL=$CLACKY_TEST_SHELLVAR", env_vars=[
    ("CLACKY_TEST_SHELLVAR", "env_value_42"),
  ])
  @debug.assert_eq(result.exit_code, 0)
  assert_true(result.output.trim().to_owned() == "VAL=env_value_42")
}

///|
test "run_shell_command: two calls do not pollute env" {
  // First call sets CLACKY_TEST_A but not CLACKY_TEST_B
  let r1 = run_shell_command("echo A=$CLACKY_TEST_A B=$CLACKY_TEST_B", env_vars=[
    ("CLACKY_TEST_A", "aaa"),
  ])
  // Second call sets CLACKY_TEST_B but not CLACKY_TEST_A
  let r2 = run_shell_command("echo A=$CLACKY_TEST_A B=$CLACKY_TEST_B", env_vars=[
    ("CLACKY_TEST_B", "bbb"),
  ])
  @debug.assert_eq(r1.exit_code, 0)
  @debug.assert_eq(r2.exit_code, 0)
  let out1 = r1.output.trim().to_owned()
  let out2 = r2.output.trim().to_owned()
  // r1 should see A=aaa and B=empty (not polluted by r2)
  assert_true(out1 == "A=aaa B=")
  // r2 should see A=empty and B=bbb (not polluted by r1)
  assert_true(out2 == "A= B=bbb")
}

///|
test "run_shell_command: working directory" {
  let result = run_shell_command("pwd", working_dir=Some("/tmp"))
  @debug.assert_eq(result.exit_code, 0)
  assert_true(result.output.trim().to_owned() == "/tmp")
}

///|
test "run_shell_command: multi-line output" {
  let result = run_shell_command("echo line1; echo line2; echo line3")
  @debug.assert_eq(result.exit_code, 0)
  let lines = result.output.trim().to_owned().split("\n").to_array()
  @debug.assert_eq(lines.length(), 3)
  @debug.assert_eq(lines[0].to_owned(), "line1")
  @debug.assert_eq(lines[1].to_owned(), "line2")
  @debug.assert_eq(lines[2].to_owned(), "line3")
}

///|
test "run_shell_command: stderr captured" {
  let result = run_shell_command("echo to_stderr 1>&2; echo to_stdout")
  @debug.assert_eq(result.exit_code, 0)
  // Both stdout and stderr go to the same output file (2>&1)
  let out = result.output.trim().to_owned()
  assert_true(out.contains("to_stderr"))
  assert_true(out.contains("to_stdout"))
}

///|
test "run_shell_command: env var with special chars" {
  let result = run_shell_command("echo \"$CLACKY_TEST_SPECIAL\"", env_vars=[
    ("CLACKY_TEST_SPECIAL", "it's a test"),
  ])
  @debug.assert_eq(result.exit_code, 0)
  assert_true(result.output.trim().to_owned() == "it's a test")
}

///|
test "run_shell_command: no env vars (empty default)" {
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
