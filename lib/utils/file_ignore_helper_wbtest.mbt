///| White-box tests for file_ignore_helper.mbt (P2-4 coverage expansion).
///
/// Gitignore-style ignore resolution. Tests use the always-on builtin rules
/// plus explicitly loaded custom/gitignore patterns; expectations follow the
/// standard "last matching rule wins" semantics implemented in the module.

///|
test "builtin_ignore_patterns: non-empty known set" {
  let pats = builtin_ignore_patterns()
  @debug.assert_eq(pats.length(), 16)
  assert_true(pats.contains(".git"))
  assert_true(pats.contains("node_modules"))
}

///|
test "ignore_config: new seeds builtin rules only" {
  let cfg = IgnoreConfig::new()
  let (g, c, b) = cfg.stats()
  @debug.assert_eq(g, 0)
  @debug.assert_eq(c, 0)
  @debug.assert_eq(b, 16)
}

///|
test "ignore_config: builtin .git is ignored" {
  let cfg = IgnoreConfig::new()
  assert_true(cfg.should_ignore(".git"))
}

///|
test "ignore_config: builtin glob *.pyc is ignored" {
  let cfg = IgnoreConfig::new()
  assert_true(cfg.should_ignore("foo.pyc"))
}

///|
test "ignore_config: builtin node_modules is ignored" {
  let cfg = IgnoreConfig::new()
  assert_true(cfg.should_ignore("node_modules"))
}

///|
test "ignore_config: ordinary source file is not ignored" {
  let cfg = IgnoreConfig::new()
  assert_false(cfg.should_ignore("src/main.mbt"))
}

///|
test "ignore_config: custom pattern is honored" {
  let cfg = IgnoreConfig::new().add_custom_pattern("secret.txt")
  assert_true(cfg.should_ignore("secret.txt"))
}

///|
test "ignore_config: filter_paths drops ignored entries" {
  let cfg = IgnoreConfig::new()
  let kept = cfg.filter_paths(["a.pyc", "b.txt", "c.md"])
  @debug.assert_eq(kept.length(), 2)
  @debug.assert_eq(kept[0], "b.txt")
  @debug.assert_eq(kept[1], "c.md")
}

///|
test "ignore_config: ignore_reason reports the matching pattern" {
  let cfg = IgnoreConfig::new()
  match cfg.ignore_reason("foo.pyc") {
    Some(p) => assert_true(p.contains("pyc"))
    None => fail("expected a reason")
  }
  assert_true(cfg.ignore_reason("keep.me") is None)
}

///|
test "ignore_config: loaded gitignore rules are applied" {
  let cfg = IgnoreConfig::new().load_gitignore("*.log\nbuild/\n")
  assert_true(cfg.should_ignore("debug.log"))
  assert_true(cfg.stats().0 >= 1)
}
