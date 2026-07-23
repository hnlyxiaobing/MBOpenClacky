///| Tests for lib/skill package

// ============================================================
// Frontmatter parsing tests
// ============================================================

///|
test "parse_frontmatter: normal frontmatter" {
  let content =
    #|---
    #|name: moonbit-orientation
    #|description: MoonBit language guidance
    #|user_invocable: true
    #|---
    #|Skill body here.
  let (fields, body) = parse_frontmatter(content)
  @debug.debug_inspect(
    fields.get("name"),
    content=(
      #|Some("moonbit-orientation")
    ),
  )
  @debug.debug_inspect(
    fields.get("description"),
    content=(
      #|Some("MoonBit language guidance")
    ),
  )
  @debug.debug_inspect(
    fields.get("user_invocable"),
    content=(
      #|Some("true")
    ),
  )
  @debug.debug_inspect(
    body.trim().to_owned(),
    content=(
      #|"Skill body here."
    ),
  )
}

///|
test "parse_frontmatter: empty frontmatter" {
  let content =
    #|---
    #|---
    #|Body content.
  let (fields, body) = parse_frontmatter(content)
  @debug.debug_inspect(fields.length(), content="0")
  @debug.debug_inspect(
    body.trim().to_owned(),
    content=(
      #|"Body content."
    ),
  )
}

///|
test "parse_frontmatter: no frontmatter delimiter" {
  let content = "Just plain content without frontmatter."
  let (fields, body) = parse_frontmatter(content)
  @debug.debug_inspect(fields.length(), content="0")
  @debug.debug_inspect(
    body,
    content=(
      #|"Just plain content without frontmatter."
    ),
  )
}

///|
test "parse_frontmatter: quoted values" {
  let content =
    #|---
    #|name: "my-skill"
    #|description: 'a quoted description'
    #|---
  let (fields, _) = parse_frontmatter(content)
  @debug.debug_inspect(
    fields.get("name"),
    content=(
      #|Some("my-skill")
    ),
  )
  @debug.debug_inspect(
    fields.get("description"),
    content=(
      #|Some("a quoted description")
    ),
  )
}

///|
test "parse_frontmatter: multiple fields" {
  let content =
    #|---
    #|name: test-skill
    #|fork_agent: true
    #|auto_summarize: false
    #|disable_model_invocation: false
    #|---
  let (fields, _) = parse_frontmatter(content)
  @debug.debug_inspect(
    fields.get("fork_agent"),
    content=(
      #|Some("true")
    ),
  )
  @debug.debug_inspect(
    fields.get("auto_summarize"),
    content=(
      #|Some("false")
    ),
  )
  @debug.debug_inspect(
    fields.get("disable_model_invocation"),
    content=(
      #|Some("false")
    ),
  )
}

// ============================================================
// load_skill_from_content tests
// ============================================================

///|
test "load_skill_from_content: valid skill" {
  let content =
    #|---
    #|name: moonbit-orientation
    #|description: MoonBit language guidance
    #|user_invocable: true
    #|disable_model_invocation: false
    #|fork_agent: false
    #|auto_summarize: false
    #|---
    #|Skill context content here.
  let skill = load_skill_from_content(content, "test_source", None)
  assert_true(skill is Some(_))
  let s = skill.unwrap()
  @debug.debug_inspect(
    s.name,
    content=(
      #|"moonbit-orientation"
    ),
  )
  @debug.debug_inspect(
    s.description,
    content=(
      #|Some("MoonBit language guidance")
    ),
  )
  assert_true(s.user_invocable)
  assert_false(s.fork_agent)
  @debug.debug_inspect(
    s.source,
    content=(
      #|"test_source"
    ),
  )
}

///|
test "load_skill_from_content: missing name returns None" {
  let content =
    #|---
    #|description: No name here
    #|---
    #|Body.
  let skill = load_skill_from_content(content, "src", None)
  assert_true(skill is None)
}

///|
test "load_skill_from_content: with directory" {
  let content =
    #|---
    #|name: my-skill
    #|---
  let skill = load_skill_from_content(
    content,
    "path/to/SKILL.md",
    Some("/path/to"),
  )
  assert_true(skill is Some(_))
  @debug.debug_inspect(
    skill.unwrap().directory,
    content=(
      #|Some("/path/to")
    ),
  )
}

///|
test "load_skill_from_content: allowed_tools parsed" {
  let content =
    #|---
    #|name: restricted-skill
    #|allowed_tools: [read_file, write_file, grep_code]
    #|---
  let skill = load_skill_from_content(content, "src", None)
  assert_true(skill is Some(_))
  let tools = skill.unwrap().allowed_tools
  assert_true(tools is Some(_))
  @debug.debug_inspect(tools.unwrap().length(), content="3")
}

// ============================================================
// load_skill_from_json_value tests
// ============================================================

///|
test "load_skill_from_json_value: valid JSON" {
  let json : Json = {
    "name": "json-skill",
    "description": "A JSON-loaded skill",
    "user_invocable": true,
    "fork_agent": false,
    "auto_summarize": false,
    "disable_model_invocation": false,
  }
  let skill = load_skill_from_json_value(json, "json_source")
  assert_true(skill is Some(_))
  let s = skill.unwrap()
  @debug.debug_inspect(
    s.name,
    content=(
      #|"json-skill"
    ),
  )
  @debug.debug_inspect(
    s.description,
    content=(
      #|Some("A JSON-loaded skill")
    ),
  )
  @debug.debug_inspect(
    s.source,
    content=(
      #|"json_source"
    ),
  )
}

///|
test "load_skill_from_json_value: missing name returns None" {
  let json : Json = { "description": "no name" }
  let skill = load_skill_from_json_value(json, "src")
  assert_true(skill is None)
}

///|
test "load_skill_from_json_value: non-object returns None" {
  let json : Json = "not an object"
  let skill = load_skill_from_json_value(json, "src")
  assert_true(skill is None)
}

// ============================================================
// SkillRegistry tests
// ============================================================

///|
test "SkillRegistry: register and get" {
  let reg = SkillRegistry::new()
  let skill = Skill::default("test-skill", "src")
  reg.register(skill)
  assert_true(reg.has("test-skill"))
  @debug.debug_inspect(reg.size(), content="1")
  let got = reg.get("test-skill")
  assert_true(got is Some(_))
  @debug.debug_inspect(
    got.unwrap().name,
    content=(
      #|"test-skill"
    ),
  )
}

///|
test "SkillRegistry: get nonexistent returns None" {
  let reg = SkillRegistry::new()
  assert_true(reg.get("nonexistent") is None)
}

///|
test "SkillRegistry: list_user_invocable" {
  let reg = SkillRegistry::new()
  let s1 = { ..Skill::default("skill-a", "src"), user_invocable: true }
  let s2 = { ..Skill::default("skill-b", "src"), user_invocable: false }
  reg.register(s1)
  reg.register(s2)
  let invocable = reg.list_user_invocable()
  @debug.debug_inspect(invocable.length(), content="1")
  @debug.debug_inspect(
    invocable[0].name,
    content=(
      #|"skill-a"
    ),
  )
}

///|
test "SkillRegistry: list_by_agent_type" {
  let reg = SkillRegistry::new()
  let s1 = { ..Skill::default("skill-x", "src"), agent_type: Some("coder") }
  let s2 = { ..Skill::default("skill-y", "src"), agent_type: Some("reviewer") }
  let s3 = { ..Skill::default("skill-z", "src"), agent_type: None }
  reg.register(s1)
  reg.register(s2)
  reg.register(s3)
  let coders = reg.list_by_agent_type("coder")
  @debug.debug_inspect(coders.length(), content="1")
  @debug.debug_inspect(
    coders[0].name,
    content=(
      #|"skill-x"
    ),
  )
}

///|
test "SkillRegistry: remove skill" {
  let reg = SkillRegistry::new()
  reg.register(Skill::default("to-remove", "src"))
  assert_true(reg.has("to-remove"))
  assert_true(reg.remove("to-remove"))
  assert_false(reg.has("to-remove"))
  @debug.debug_inspect(reg.size(), content="0")
}

///|
test "SkillRegistry: remove nonexistent returns false" {
  let reg = SkillRegistry::new()
  assert_false(reg.remove("ghost"))
}

///|
test "SkillRegistry: all returns all skills" {
  let reg = SkillRegistry::new()
  reg.register(Skill::default("a", "src"))
  reg.register(Skill::default("b", "src"))
  reg.register(Skill::default("c", "src"))
  @debug.debug_inspect(reg.all().length(), content="3")
}

// ============================================================
// discovery tests
// ============================================================

///|
test "default_discovery_paths: returns 3 paths" {
  let paths = default_discovery_paths("/home/user/project")
  @debug.debug_inspect(paths.length(), content="3")
  @debug.debug_inspect(
    paths[0],
    content=(
      #|"/home/user/project/.qoder/skills"
    ),
  )
  @debug.debug_inspect(
    paths[1],
    content=(
      #|"/home/user/project/skills"
    ),
  )
  @debug.debug_inspect(
    paths[2],
    content=(
      #|"/home/user/project/.skills"
    ),
  )
}

///|
test "discover_skills: discovers from skill.md content" {
  let file_contents : Map[String, String] = Map([])
  let skill_md_content =
    #|---
    #|name: discovered-skill
    #|description: Discovered from file map
    #|---
    #|Context body.
  file_contents["/project/skills/skill.md"] = skill_md_content
  let skills = discover_skills(file_contents)
  @debug.debug_inspect(skills.length(), content="1")
  @debug.debug_inspect(
    skills[0].name,
    content=(
      #|"discovered-skill"
    ),
  )
}

///|
test "discover_skills: ignores unrelated files" {
  let file_contents : Map[String, String] = Map([])
  file_contents["/project/README.md"] = "# Project README"
  file_contents["/project/config.toml"] = "[settings]"
  let skills = discover_skills(file_contents)
  @debug.debug_inspect(skills.length(), content="0")
}

// ============================================================
// executor tests
// ============================================================

///|
test "build_skill_context: basic skill" {
  let skill = {
    ..Skill::default("my-skill", "src"),
    description: Some("Does something useful"),
  }
  let ctx = build_skill_context(skill, "")
  assert_true(ctx.find("my-skill") is Some(_))
  assert_true(ctx.find("Does something useful") is Some(_))
}

///|
test "build_skill_context: with args" {
  let skill = Skill::default("arg-skill", "src")
  let ctx = build_skill_context(skill, "some argument value")
  assert_true(ctx.find("some argument value") is Some(_))
}

///|
test "build_skill_context: with context body" {
  let skill = {
    ..Skill::default("ctx-skill", "src"),
    context: Some("You are a helpful assistant."),
  }
  let ctx = build_skill_context(skill, "")
  assert_true(ctx.find("You are a helpful assistant.") is Some(_))
}

///|
test "build_skills_summary: empty list" {
  let skills : Array[Skill] = []
  @debug.debug_inspect(
    build_skills_summary(skills),
    content=(
      #|""
    ),
  )
}

///|
test "build_skills_summary: multiple skills" {
  let skills = [
    {
      ..Skill::default("skill-one", "src"),
      description: Some("First skill"),
      argument_hint: Some("<topic>"),
    },
    { ..Skill::default("skill-two", "src"), description: Some("Second skill") },
  ]
  let summary = build_skills_summary(skills)
  assert_true(summary.find("skill-one") is Some(_))
  assert_true(summary.find("First skill") is Some(_))
  assert_true(summary.find("<topic>") is Some(_))
  assert_true(summary.find("skill-two") is Some(_))
  assert_true(summary.find("Second skill") is Some(_))
}
