///| White-box tests for workspace_rules.mbt pure functions.

///|
test "WorkspaceRules::has_rules: true when main_rule present" {
  let rules : WorkspaceRules = {
    main_rule: Some("Be productive."),
    main_rule_path: Some("/project/.clackyrules"),
    sub_rules: [],
  }
  assert_true(rules.has_rules())
}

///|
test "WorkspaceRules::has_rules: false when main_rule absent" {
  let rules : WorkspaceRules = {
    main_rule: None,
    main_rule_path: None,
    sub_rules: [],
  }
  assert_false(rules.has_rules())
}

///|
test "WorkspaceRules::to_prompt_section: none when empty" {
  let rules : WorkspaceRules = {
    main_rule: None,
    main_rule_path: None,
    sub_rules: [],
  }
  assert_eq(rules.to_prompt_section(), None)
}

///|
test "WorkspaceRules::to_prompt_section: main_rule only" {
  let rules : WorkspaceRules = {
    main_rule: Some("Always test your code."),
    main_rule_path: Some("/project/.clackyrules"),
    sub_rules: [],
  }
  let sep = "=".repeat(80)
  let result = rules.to_prompt_section()
  assert_true(result is Some(_))
  match result {
    Some(text) =>
      assert_eq(
        text,
        "\n" +
        sep +
        "\nPROJECT-SPECIFIC RULES (from .clackyrules)\n" +
        sep +
        "\nAlways test your code.\n" +
        sep +
        "\nIMPORTANT: Follow these project-specific rules at all times!\n" +
        sep,
      )
    None => assert_false(true)
  }
}

///|
test "WorkspaceRules::to_prompt_section: main_rule and sub_rules" {
  let rules : WorkspaceRules = {
    main_rule: Some("Main rule."),
    main_rule_path: Some("/project/AGENTS.md"),
    sub_rules: [("sub", "Sub rule summary.")],
  }
  let result = rules.to_prompt_section()
  match result {
    Some(text) => {
      assert_true(text.contains("PROJECT-SPECIFIC RULES (from AGENTS.md)"))
      assert_true(text.contains("Main rule."))
      assert_true(text.contains("## SUB-PROJECT AGENTS"))
      assert_true(text.contains("### Sub-project: sub/"))
      assert_true(
        text.contains(
          "Summary (first 5 lines of sub/.clackyrules):\nSub rule summary.",
        ),
      )
      assert_true(
        text.contains(
          "> IMPORTANT: Before working on any files under sub/, read the full rules file at `sub/.clackyrules` using file_reader.",
        ),
      )
    }
    None => assert_false(true)
  }
}

///|
test "WorkspaceRules::to_prompt_section: sub_rules only (no main)" {
  let rules : WorkspaceRules = {
    main_rule: None,
    main_rule_path: None,
    sub_rules: [("lib", "Lib rules."), ("cmd", "Cmd rules.")],
  }
  let result = rules.to_prompt_section()
  match result {
    Some(text) => {
      assert_true(text.contains("PROJECT-SPECIFIC RULES (from sub-projects)"))
      assert_true(text.contains("### Sub-project: lib/"))
      assert_true(text.contains("### Sub-project: cmd/"))
    }
    None => assert_false(true)
  }
}

///|
test "WorkspaceRules::to_prompt_section: multiple sub_rules formatting" {
  let rules : WorkspaceRules = {
    main_rule: Some("Top."),
    main_rule_path: None,
    sub_rules: [("a", "A."), ("b", "B."), ("c", "C.")],
  }
  let result = rules.to_prompt_section()
  match result {
    Some(text) => {
      assert_true(
        text.contains(
          "### Sub-project: a/\nSummary (first 5 lines of a/.clackyrules):\nA.",
        ),
      )
      assert_true(
        text.contains(
          "### Sub-project: b/\nSummary (first 5 lines of b/.clackyrules):\nB.",
        ),
      )
      assert_true(
        text.contains(
          "### Sub-project: c/\nSummary (first 5 lines of c/.clackyrules):\nC.",
        ),
      )
      assert_true(text.contains("## SUB-PROJECT AGENTS"))
      // main_rule_path absent → source falls back to the generic label.
      assert_true(text.contains("PROJECT-SPECIFIC RULES (from sub-projects)"))
    }
    None => assert_false(true)
  }
}

///|
test "WorkspaceRules: equality comparison" {
  let r1 : WorkspaceRules = {
    main_rule: Some("Rule"),
    main_rule_path: Some("/path"),
    sub_rules: [("sub", "content")],
  }
  let r2 : WorkspaceRules = {
    main_rule: Some("Rule"),
    main_rule_path: Some("/path"),
    sub_rules: [("sub", "content")],
  }
  let r3 : WorkspaceRules = {
    main_rule: Some("Different"),
    main_rule_path: Some("/path"),
    sub_rules: [("sub", "content")],
  }
  assert_eq(r1, r2)
  assert_not_eq(r1, r3)
}

///|
test "WorkspaceRules::leading_lines: caps at n and keeps order" {
  assert_eq(leading_lines("a\nb\nc\nd\ne\nf", 5), "a\nb\nc\nd\ne")
  assert_eq(leading_lines("a\nb", 5), "a\nb")
  assert_eq(leading_lines("only", 5), "only")
}

///|
test "WorkspaceRules::basename: last non-empty segment" {
  assert_eq(basename("/project/AGENTS.md"), "AGENTS.md")
  assert_eq(basename("/project/.clackyrules"), ".clackyrules")
  assert_eq(basename("AGENTS.md"), "AGENTS.md")
}

///|
test "WorkspaceRules::find_main: AGENTS.md is recognised and empty files are skipped" {
  let dir = probe_dir_name("wsrules")
  if !probe_make_dir(dir) {
    return
  }
  // An empty .clackyrules must not shadow AGENTS.md (Ruby skips blank files).
  @fs.write_string_to_file(
    @path.Path::join(@path.Path(dir), @path.Path(".clackyrules")).to_string(),
    "",
  ) catch {
    _ => ()
  }
  @fs.write_string_to_file(
    @path.Path::join(@path.Path(dir), @path.Path("AGENTS.md")).to_string(),
    "  AGENTS rules.  \n",
  ) catch {
    _ => ()
  }
  let rules = WorkspaceRules::find_main(dir)
  match rules.main_rule {
    Some(content) => assert_eq(content, "AGENTS rules.")
    None => assert_false(true)
  }
  match rules.main_rule_path {
    Some(path) => assert_true(path.has_suffix("AGENTS.md"))
    None => assert_false(true)
  }
  @fs.remove_dir(dir) catch {
    _ => ()
  }
}
