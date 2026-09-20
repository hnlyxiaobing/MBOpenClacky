///| White-box tests for the CLI contract probe engine (P0-3).
///
/// These cover the assertion helpers with synthetic inputs. The live CLI
/// contract itself is exercised by `mbopenclacky selftest` (which spawns the
/// built binary); keeping the engine unit-tested means a broken assertion
/// cannot silently pass there.

///|
test "check_stdout_shape: Empty" {
  @debug.assert_eq(check_stdout_shape(Empty, "  \n\t ").length(), 0)
  assert_true(check_stdout_shape(Empty, "x").length() > 0)
}

///|
test "check_stdout_shape: Text" {
  @debug.assert_eq(check_stdout_shape(Text, "hello").length(), 0)
  assert_true(check_stdout_shape(Text, "   ").length() > 0)
}

///|
test "check_stdout_shape: Json" {
  @debug.assert_eq(check_stdout_shape(Json, "{\"total\":0}").length(), 0)
  @debug.assert_eq(check_stdout_shape(Json, "[1,2,3]").length(), 0)
  assert_true(check_stdout_shape(Json, "not json").length() > 0)
  assert_true(check_stdout_shape(Json, "").length() > 0)
}

///|
test "check_stdout_shape: JsonLines" {
  let ok = "{\"a\":1}\n{\"b\":2}\n"
  @debug.assert_eq(check_stdout_shape(JsonLines, ok).length(), 0)
  // Blank lines are tolerated; a non-JSON line is not.
  @debug.assert_eq(check_stdout_shape(JsonLines, "{\"a\":1}\n\n").length(), 0)
  assert_true(check_stdout_shape(JsonLines, "{\"a\":1}\noops\n").length() > 0)
  assert_true(check_stdout_shape(JsonLines, "").length() > 0)
}

///|
test "check_exit: zero / non-zero / exact" {
  @debug.assert_eq(check_exit(Zero, 0).length(), 0)
  assert_true(check_exit(Zero, 1).length() > 0)
  @debug.assert_eq(check_exit(NonZero, 1).length(), 0)
  assert_true(check_exit(NonZero, 0).length() > 0)
  @debug.assert_eq(check_exit(Exact(3), 3).length(), 0)
  assert_true(check_exit(Exact(3), 0).length() > 0)
}

///|
test "check_stderr: Clean and Contains" {
  @debug.assert_eq(check_stderr(Clean, "  \n").length(), 0)
  assert_true(check_stderr(Clean, "boom").length() > 0)
  @debug.assert_eq(check_stderr(Contains(["boom"]), "big boom").length(), 0)
  assert_true(check_stderr(Contains(["boom", "bang"]), "quiet").length() > 0)
}

///|
test "check_content: required substrings and forbidden markers" {
  @debug.assert_eq(check_content(["hello"], "hello world", "").length(), 0)
  assert_true(check_content(["missing"], "hello world", "").length() > 0)
  // Panic / failure leakage must always be reported, on either stream.
  assert_true(check_content([], "Failure(internal)", "").length() > 0)
  assert_true(check_content([], "", "Panic(oops)").length() > 0)
  assert_true(check_content([], "Raised at foo.mbt", "").length() > 0)
}

///|
test "read_module_version: parses the manifest when reachable" {
  match read_module_version(".") {
    Some(version) => assert_true(version.length() > 0)
    // Tests may run from a directory without moon.mod; the probe degrades to
    // a format-only check in that case.
    None => ()
  }
}

///|
test "probe_set: names are unique and non-empty" {
  let probes = probe_set()
  assert_true(probes.length() >= 5)
  let seen : Map[String, Bool] = Map([])
  for probe in probes {
    assert_true(probe.name.length() > 0)
    assert_true(probe.args.length() > 0)
    assert_false(seen.contains(probe.name))
    seen[probe.name] = true
  }
}
