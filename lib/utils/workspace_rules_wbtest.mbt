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
  let result = rules.to_prompt_section()
  assert_true(result is Some(_))
  match result {
    Some(text) =>
      assert_eq(text, "## Workspace Rules\n\nAlways test your code.\n")
    None => assert_false(true)
  }
}

///|
test "WorkspaceRules::to_prompt_section: main_rule and sub_rules" {
  let rules : WorkspaceRules = {
    main_rule: Some("Main rule."),
    main_rule_path: Some("/project/.clackyrules"),
    sub_rules: [("/sub/.clackyrules", "Sub rule.")],
  }
  let result = rules.to_prompt_section()
  match result {
    Some(text) =>
      assert_eq(
        text, "## Workspace Rules\n\nMain rule.\n\n## Sub-project Rules\n\n### /sub/.clackyrules\nSub rule.\n",
      )
    None => assert_false(true)
  }
}

///|
test "WorkspaceRules::to_prompt_section: sub_rules only (no main)" {
  let rules : WorkspaceRules = {
    main_rule: None,
    main_rule_path: None,
    sub_rules: [
      ("/lib/.clackyrules", "Lib rules."),
      ("/cmd/.clackyrules", "Cmd rules."),
    ],
  }
  let result = rules.to_prompt_section()
  match result {
    Some(text) =>
      assert_eq(
        text, "\n## Sub-project Rules\n\n### /lib/.clackyrules\nLib rules.\n\n### /cmd/.clackyrules\nCmd rules.\n",
      )
    None => assert_false(true)
  }
}

///|
test "WorkspaceRules::to_prompt_section: multiple sub_rules formatting" {
  let rules : WorkspaceRules = {
    main_rule: Some("Top."),
    main_rule_path: None,
    sub_rules: [
      ("/a/.clackyrules", "A."),
      ("/b/.clackyrules", "B."),
      ("/c/.clackyrules", "C."),
    ],
  }
  let result = rules.to_prompt_section()
  match result {
    Some(text) => {
      assert_true(text.contains("### /a/.clackyrules\nA."))
      assert_true(text.contains("### /b/.clackyrules\nB."))
      assert_true(text.contains("### /c/.clackyrules\nC."))
      assert_true(text.contains("## Workspace Rules"))
      assert_true(text.contains("## Sub-project Rules"))
    }
    None => assert_false(true)
  }
}

///|
test "WorkspaceRules: equality comparison" {
  let r1 : WorkspaceRules = {
    main_rule: Some("Rule"),
    main_rule_path: Some("/path"),
    sub_rules: [("/sub", "content")],
  }
  let r2 : WorkspaceRules = {
    main_rule: Some("Rule"),
    main_rule_path: Some("/path"),
    sub_rules: [("/sub", "content")],
  }
  let r3 : WorkspaceRules = {
    main_rule: Some("Different"),
    main_rule_path: Some("/path"),
    sub_rules: [("/sub", "content")],
  }
  assert_eq(r1, r2)
  assert_not_eq(r1, r3)
}
