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
test "default_discovery_paths: user-global first, .clacky last" {
  let paths = default_discovery_paths("/home/user/project")
  // User-global dir (~/.mbopenclacky/skills) comes first when resolvable;
  // project dirs follow, with .clacky/skills (highest priority) last.
  let expected_tail = [
    "/home/user/project/.qoder/skills", "/home/user/project/skills", "/home/user/project/.skills",
    "/home/user/project/.clacky/skills",
  ]
  let tail : Array[String] = []
  for i = paths.length() - 4; i < paths.length(); i = i + 1 {
    tail.push(paths[i])
  }
  @debug.assert_eq(tail, expected_tail)
  match @utils.skills_dir() {
    Some(dir) => @debug.assert_eq(paths[0], dir)
    None => @debug.assert_eq(paths.length(), 4)
  }
}

///|
test "read_skill_files: walks nested skill directories" {
  let root = test_temp_dir("skill_discovery")
  let skill_dir = root + "/.clacky/skills/my-skill"
  @utils.ensure_dir(skill_dir)
  @fs.write_string_to_file(
    skill_dir + "/SKILL.md",
    "---\nname: my-skill\ndescription: A project skill\nuser_invocable: true\n---\nDo the thing.\n",
  )
  |> ignore
  // Non-skill files and deeper-than-limit nesting are ignored.
  @fs.write_string_to_file(root + "/.clacky/skills/README.md", "not a skill")
  |> ignore
  let files = read_skill_files([root + "/.clacky/skills", root + "/nonexistent"])
  @debug.assert_eq(files.length(), 1)
  let skills = discover_skills(files)
  @debug.assert_eq(skills.length(), 1)
  @debug.assert_eq(skills[0].name, "my-skill")
}

///|
fn test_temp_dir(name : String) -> String {
  let dir = match @utils.env_var("TEMP") {
    Some(d) => d
    None =>
      match @utils.env_var("TMPDIR") {
        Some(d) => d
        None => "/tmp"
      }
  }
  dir + "/" + name
}

///|
test "discover_skills: discovers from SKILL.md content" {
  let file_contents : Map[String, String] = Map([])
  let skill_md_content =
    #|---
    #|name: discovered-skill
    #|description: Discovered from file map
    #|---
    #|Context body.
  file_contents["/project/skills/discovered-skill/SKILL.md"] = skill_md_content
  let skills = discover_skills(file_contents)
  @debug.assert_eq(skills.length(), 1)
  @debug.assert_eq(skills[0].name, "discovered-skill")
}

///|
test "discover_skills: ignores unrelated files" {
  let file_contents : Map[String, String] = Map([])
  file_contents["/project/README.md"] = "# Project README"
  file_contents["/project/config.toml"] = "[settings]"
  let skills = discover_skills(file_contents)
  @debug.assert_eq(skills.length(), 0)
}

///|
test "discover_skills: strict SKILL.md filename, look-alikes rejected" {
  let file_contents : Map[String, String] = Map([])
  // Look-alike filenames must NOT be treated as skill files.
  file_contents["/p/my-skill/myskill.md"] = "---\nname: fake-1\n---\nbody"
  file_contents["/p/my-skill/skill.md"] = "---\nname: fake-2\n---\nbody"
  file_contents["/p/my-skill/skills.md"] = "---\nname: fake-3\n---\nbody"
  file_contents["/p/my-skill/skill.json"] = "{\"name\": \"fake-4\"}"
  file_contents["/p/my-skill/SKILL.md.bak"] = "---\nname: fake-5\n---\nbody"
  let skills = discover_skills(file_contents)
  @debug.assert_eq(skills.length(), 0)
  // Exact SKILL.md still discovered.
  file_contents["/p/real-skill/SKILL.md"] = "---\nname: real-skill\n---\nbody"
  let skills = discover_skills(file_contents)
  @debug.assert_eq(skills.length(), 1)
  @debug.assert_eq(skills[0].name, "real-skill")
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
  assert_true(summary.find("AVAILABLE SKILLS") is Some(_))
  assert_true(summary.find("skill-one") is Some(_))
  assert_true(summary.find("First skill") is Some(_))
  assert_true(summary.find("skill-two") is Some(_))
  assert_true(summary.find("Second skill") is Some(_))
}

///|
test "parse_frontmatter: literal block scalar (|) collects multiline value" {
  let content =
    #|---
    #|name: browser-setup
    #|description: |
    #|  Configure the browser tool. Guides setup,
    #|  verifies the connection, and writes config.
    #|  Subcommands: setup, doctor.
    #|argument_hint: "[setup | doctor]"
    #|---
    #|Body.
  let (fields, _body) = parse_frontmatter(content)
  @debug.assert_eq(fields.get("name"), Some("browser-setup"))
  let desc = match fields.get("description") {
    Some(d) => d
    None => panic()
  }
  assert_false(desc == "|")
  @debug.assert_eq(
    desc, "Configure the browser tool. Guides setup,\nverifies the connection, and writes config.\nSubcommands: setup, doctor.",
  )
  // The key following the block must still parse normally.
  @debug.assert_eq(fields.get("argument_hint"), Some("[setup | doctor]"))
}

///|
test "parse_frontmatter: folded block scalar (>) folds newlines" {
  let content =
    #|---
    #|name: folded
    #|description: >
    #|  First line of description.
    #|  Second line continues here.
    #|enabled: true
    #|---
    #|Body.
  let (fields, _body) = parse_frontmatter(content)
  let desc = match fields.get("description") {
    Some(d) => d
    None => panic()
  }
  @debug.assert_eq(
    desc, "First line of description. Second line continues here.",
  )
  @debug.assert_eq(fields.get("enabled"), Some("true"))
}

///|
test "parse_frontmatter: inline description unaffected by block scalar support" {
  let content =
    #|---
    #|name: code-explorer
    #|description: Use this skill when exploring code.
    #|---
    #|Body.
  let (fields, _body) = parse_frontmatter(content)
  @debug.assert_eq(
    fields.get("description"),
    Some("Use this skill when exploring code."),
  )
}

// ============================================================
// Block list / nested map parsing (spec 2026-08-18_20)
// ============================================================

///|
test "parse_frontmatter: block list of allowed_tools" {
  let content =
    #|---
    #|name: browser-setup
    #|description: Configure the browser tool.
    #|allowed_tools:
    #|  - Terminal
    #|  - WebFetch
    #|  - Read
    #|fork_agent: true
    #|---
    #|Body.
  let (fields, _body) = parse_frontmatter(content)
  @debug.assert_eq(fields.get("allowed_tools"), Some("Terminal,WebFetch,Read"))
  @debug.assert_eq(fields.get("fork_agent"), Some("true"))
}

///|
test "load_skill_from_content: block list tools parsed" {
  let content =
    #|---
    #|name: browser-setup
    #|description: Configure the browser tool.
    #|allowed_tools:
    #|  - Terminal
    #|  - WebFetch
    #|---
    #|Body.
  let skill = load_skill_from_content(content, "assets/skills", None)
  assert_true(skill is Some(_))
  let s = skill.unwrap()
  let tools = s.allowed_tools.unwrap()
  @debug.assert_eq(tools.length(), 2)
  @debug.assert_eq(tools[0], "Terminal")
  @debug.assert_eq(tools[1], "WebFetch")
}

///|
test "parse_frontmatter: one-level nested map flattened" {
  let content =
    #|---
    #|name: nested-skill
    #|hooks:
    #|  on_start: echo start
    #|  on_end: echo end
    #|---
    #|Body.
  let (fields, _body) = parse_frontmatter(content)
  @debug.assert_eq(fields.get("hooks.on_start"), Some("echo start"))
  @debug.assert_eq(fields.get("hooks.on_end"), Some("echo end"))
}

///|
test "parse_frontmatter: empty value then next top-level key" {
  let content =
    #|---
    #|name: gap-skill
    #|description:
    #|user_invocable: true
    #|---
  let (fields, _body) = parse_frontmatter(content)
  @debug.assert_eq(fields.get("description"), Some(""))
  @debug.assert_eq(fields.get("user_invocable"), Some("true"))
}

// ============================================================
// Name fallback / slug validation / description truncation
// ============================================================

///|
test "load_skill_from_content: name falls back to directory basename" {
  let content =
    #|---
    #|description: No name field here.
    #|user_invocable: true
    #|---
    #|Body.
  let skill = load_skill_from_content(
    content,
    "assets/skills",
    Some("assets/skills/anonymous-skill"),
  )
  assert_true(skill is Some(_))
  @debug.assert_eq(skill.unwrap().name, "anonymous-skill")
}

///|
test "load_skill_from_content: no name and no directory returns None" {
  let content =
    #|---
    #|description: No name, no directory.
    #|---
  let skill = load_skill_from_content(content, "src", None)
  assert_true(skill is None)
}

///|
test "is_valid_skill_slug: accepts lowercase slugs" {
  assert_true(is_valid_skill_slug("browser-setup"))
  assert_true(is_valid_skill_slug("deploy"))
  assert_true(is_valid_skill_slug("skill-2"))
  assert_false(is_valid_skill_slug(""))
  assert_false(is_valid_skill_slug("Browser_Setup"))
  assert_false(is_valid_skill_slug("my skill"))
  assert_false(is_valid_skill_slug("驼峰"))
}

///|
test "context_description: short description kept as-is" {
  @debug.assert_eq(
    context_description("A short description."),
    "A short description.",
  )
}

///|
test "context_description: long description truncated at 339 + ellipsis" {
  let long = "C".repeat(500)
  let rendered = context_description(long)
  @debug.assert_eq(rendered.length(), 340)
  @debug.assert_eq(rendered, "C".repeat(339) + "…")
}

///|
test "context_description: exactly 340 chars kept whole" {
  let exact = "D".repeat(340)
  let rendered = context_description(exact)
  @debug.assert_eq(rendered.length(), 340)
  @debug.assert_eq(rendered, exact)
}

///|
test "load_skill_from_content: auto_summarize defaults to true" {
  let content =
    #|---
    #|name: summarisable-skill
    #|description: desc
    #|---
  let skill = load_skill_from_content(content, "src", None)
  assert_true(skill is Some(_))
  assert_true(skill.unwrap().auto_summarize)
}

///|
test "load_skill_from_content: explicit auto_summarize false honoured" {
  let content =
    #|---
    #|name: no-summary-skill
    #|auto_summarize: false
    #|---
  let skill = load_skill_from_content(content, "src", None)
  assert_false(skill.unwrap().auto_summarize)
}

///|
test "load_skill_from_content: agent key aliases agent_type" {
  let content =
    #|---
    #|name: scoped-skill
    #|agent: coding
    #|---
  let skill = load_skill_from_content(content, "src", None)
  @debug.assert_eq(skill.unwrap().agent_type, Some("coding"))
}

///|
test "load_skill_from_content: yaml bool accepts yes and 1" {
  let content =
    #|---
    #|name: bool-skill
    #|fork_agent: yes
    #|user_invocable: 1
    #|disable_model_invocation: no
    #|---
  let skill = load_skill_from_content(content, "src", None)
  let s = skill.unwrap()
  assert_true(s.fork_agent)
  assert_true(s.user_invocable)
  assert_false(s.disable_model_invocation)
}

///|
test "directory_basename: various separators" {
  @debug.assert_eq(
    directory_basename("assets/skills/browser-setup"),
    "browser-setup",
  )
  @debug.assert_eq(
    directory_basename("D:\\home\\.clacky\\skills\\my-skill"),
    "my-skill",
  )
  @debug.assert_eq(directory_basename("trailing/"), "trailing")
}
