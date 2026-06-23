///|
test "parse_gitignore skips comments" {
  let rules = parse_gitignore("# this is a comment\n\n# another comment\n")
  assert_eq(rules.length(), 0)
}

///|
test "parse_gitignore handles negation" {
  let rules = parse_gitignore("*.log\n!important.log\n")
  assert_eq(rules.length(), 2)
  assert_false(rules[0].is_negation)
  assert_true(rules[1].is_negation)
}

///|
test "parse_gitignore handles directory marker" {
  let rules = parse_gitignore("build/\nlogs/\n")
  assert_eq(rules.length(), 2)
  assert_true(rules[0].is_directory)
  assert_true(rules[1].is_directory)
}

///|
test "parse_gitignore handles anchored paths" {
  let rules = parse_gitignore("/root_only\nsrc/build\n")
  assert_eq(rules.length(), 2)
  // /root_only -> after stripping leading /, pattern is "root_only" with no /
  assert_false(rules[0].is_anchored) // leading / stripped, no / remaining
  assert_true(rules[1].is_anchored) // contains / in pattern
}

///|
test "parse_rule empty line returns None" {
  assert_true(parse_rule("") is None)
  assert_true(parse_rule("   ") is None)
  assert_true(parse_rule("\t") is None)
  assert_true(parse_rule("# comment") is None)
}

///|
test "matches_rule simple pattern" {
  let rule = parse_rule("foo.txt").unwrap()
  assert_true(matches_rule("foo.txt", rule))
  assert_true(matches_rule("dir/foo.txt", rule))
  assert_false(matches_rule("foo.txt2", rule))
}

///|
test "matches_rule wildcard star" {
  let rule = parse_rule("*.log").unwrap()
  assert_true(matches_rule("app.log", rule))
  assert_true(matches_rule("dir/error.log", rule))
  assert_false(matches_rule("logfile", rule))
}

///|
test "matches_rule double star" {
  let rule = parse_rule("src/**/*.js").unwrap()
  assert_true(matches_rule("src/app.js", rule))
  assert_true(matches_rule("src/lib/util.js", rule))
  assert_false(matches_rule("lib/app.js", rule))
}

///|
test "matches_rule directory only" {
  let rule = parse_rule("build/").unwrap()
  assert_true(rule.is_directory)
  // Directory-only rules should match directory names
  assert_true(matches_rule("build", rule))
  assert_true(matches_rule("project/build", rule))
}

///|
test "is_ignored last rule wins" {
  let rules = parse_gitignore("*.log\n!error.log\n*.log\n")
  // Last *.log wins over the negation
  assert_true(is_ignored("error.log", rules))
}

///|
test "is_ignored negation overrides" {
  let rules = parse_gitignore("*.log\n!important.log\n")
  assert_true(is_ignored("debug.log", rules))
  assert_false(is_ignored("important.log", rules))
}

///|
test "builtin_ignore_patterns coverage" {
  let patterns = builtin_ignore_patterns()
  assert_true(patterns.length() > 0)
  // Check a few essential patterns
  assert_true(patterns.contains(".git"))
  assert_true(patterns.contains("node_modules"))
  assert_true(patterns.contains("_build"))
}

///|
test "should_ignore builtin rules" {
  let config = IgnoreConfig::new()
  assert_true(config.should_ignore(".git"))
  assert_true(config.should_ignore("node_modules"))
  assert_true(config.should_ignore("_build"))
  assert_false(config.should_ignore("src/main.mbt"))
}

///|
test "should_ignore gitignore rules" {
  let config = IgnoreConfig::new().load_gitignore("*.tmp\nbuild/\n")
  assert_true(config.should_ignore("cache.tmp"))
  assert_true(config.should_ignore("build", is_dir=true))
  assert_false(config.should_ignore("src/app.mbt"))
}

///|
test "should_ignore custom rules" {
  let config = IgnoreConfig::new().add_custom_pattern("*.bak")
  assert_true(config.should_ignore("file.bak"))
  assert_false(config.should_ignore("file.txt"))
}

///|
test "filter_paths removes ignored" {
  let config = IgnoreConfig::new().add_custom_pattern("*.log")
  let paths = ["src/main.mbt", "debug.log", "lib/util.mbt", "error.log"]
  let filtered = config.filter_paths(paths)
  assert_eq(filtered.length(), 2)
  assert_true(filtered.contains("src/main.mbt"))
  assert_true(filtered.contains("lib/util.mbt"))
}

///|
test "ignore_reason reports matching rule" {
  let config = IgnoreConfig::new()
  // .git is a builtin pattern
  match config.ignore_reason(".git") {
    Some(reason) => assert_eq(reason, ".git")
    None => fail("expected a reason for .git")
  }
  assert_true(config.ignore_reason("src/main.mbt") is None)
}

///|
test "IgnoreConfig new has builtins" {
  let config = IgnoreConfig::new()
  let (gi, cu, bu) = config.stats()
  assert_eq(gi, 0)
  assert_eq(cu, 0)
  assert_true(bu > 0)
}
