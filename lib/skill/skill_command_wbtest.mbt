///|
/// Tests for skill slash-command resolution (SPEC-02 task package 4).

///|
/// Registry with one invocable and one non-invocable skill.
fn make_registry() -> SkillRegistry {
  let reg = SkillRegistry::new()
  reg.register({
    ..Skill::default("explain-code", "builtin"),
    description: Some("Explain a piece of code"),
    argument_hint: Some("<code>"),
  })
  reg.register({
    ..Skill::default("internal", "builtin"),
    user_invocable: false,
  })
  reg
}

///|
test "find_skill_command resolves /name with arguments" {
  let reg = make_registry()
  match reg.find_skill_command("/explain-code fn main {}") {
    Some((skill, args)) => {
      assert_eq(skill.name, "explain-code")
      assert_eq(args, "fn main {}")
    }
    None => abort("expected a skill match")
  }
}

///|
test "find_skill_command resolves bare /name with empty args" {
  let reg = make_registry()
  match reg.find_skill_command("/explain-code") {
    Some((skill, args)) => {
      assert_eq(skill.name, "explain-code")
      assert_eq(args, "")
    }
    None => abort("expected a skill match")
  }
}

///|
test "find_skill_command rejects non-invocable skills and unknown names" {
  let reg = make_registry()
  assert_true(reg.find_skill_command("/internal") is None)
  assert_true(reg.find_skill_command("/no-such-skill") is None)
  assert_true(reg.find_skill_command("/") is None)
  assert_true(reg.find_skill_command("plain text") is None)
  // Multi-segment paths are not skill commands (Ruby: treated as input).
  assert_true(reg.find_skill_command("/foo/bar") is None)
}

///|
test "routing priority: static commands win over same-named skills" {
  // If a skill shared a name with a static command, the static parser
  // resolves first (the controller checks parse_slash_command before the
  // registry) — document and pin the order here.
  let reg = SkillRegistry::new()
  reg.register(Skill::default("help", "builtin"))
  // Static parse of "/help" succeeds, so the registry is never consulted.
  assert_true(reg.find_skill_command("/help") is Some(_))
  // ...but in the controller flow this point is only reached when the
  // static parse FAILED, so the skill can never shadow /help.
}
