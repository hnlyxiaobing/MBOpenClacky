///|
/// SkillProvider whitebox tests.

///|
test "SkillProvider new creates empty provider" {
  let provider = SkillProvider::new([])
  @debug.assert_eq(provider.registered_count(), 0)
  @debug.assert_eq(provider.list_registered().length(), 0)
}

///|
test "SkillProvider discover_from_contents with valid SKILL.md" {
  let provider = SkillProvider::new([])
  let contents : Map[String, String] = {
    "skills/test-skill/SKILL.md": "---\nname: test-skill\ndescription: A test skill\nversion: \"1.0.0\"\nuser_invocable: true\ncategory: development\nallowed_tools: [Write, Edit]\n---\n# Test Skill\nSome instructions here",
  }
  let skills = provider.discover_from_contents(contents)
  @debug.assert_eq(skills.length(), 1)
  let s = skills[0]
  @debug.assert_eq(s.name, "test-skill")
  @debug.assert_eq(s.description, "A test skill")
  @debug.assert_eq(s.version, "1.0.0")
  @debug.assert_eq(s.category, "development")
  assert_true(s.user_invocable)
  @debug.assert_eq(s.allowed_tools.length(), 2)
  @debug.assert_eq(s.allowed_tools[0], "Write")
  @debug.assert_eq(s.allowed_tools[1], "Edit")
  assert_true(s.instructions.contains("Test Skill"))
  assert_true(s.instructions.contains("Some instructions here"))
}

///|
test "SkillProvider discover_from_contents skips non-skill files" {
  let provider = SkillProvider::new([])
  let contents : Map[String, String] = {
    "readme.md": "# README",
    "config.json": "{}",
    "notes.txt": "some notes",
  }
  let skills = provider.discover_from_contents(contents)
  @debug.assert_eq(skills.length(), 0)
}

///|
test "SkillProvider discover_from_contents empty map" {
  let provider = SkillProvider::new([])
  let contents : Map[String, String] = {}
  let skills = provider.discover_from_contents(contents)
  @debug.assert_eq(skills.length(), 0)
}

///|
test "SkillProvider discover_from_contents missing name field" {
  let provider = SkillProvider::new([])
  let contents : Map[String, String] = {
    "skills/bad/SKILL.md": "---\ndescription: No name field\n---\nBody",
  }
  let skills = provider.discover_from_contents(contents)
  @debug.assert_eq(skills.length(), 0)
}

///|
test "SkillProvider discover_from_contents no frontmatter" {
  let provider = SkillProvider::new([])
  let contents : Map[String, String] = {
    "skills/plain/SKILL.md": "# Just a heading\nNo frontmatter here.",
  }
  let skills = provider.discover_from_contents(contents)
  @debug.assert_eq(skills.length(), 0)
}

///|
test "SkillProvider register_skill success" {
  let provider = SkillProvider::new([])
  let info : SkillInfo = {
    name: "my-skill",
    description: "My skill",
    version: "1.0.0",
    category: "utility",
    user_invocable: true,
    allowed_tools: [],
    file_path: "skills/my-skill/SKILL.md",
    instructions: "Do something",
  }
  let result = provider.register_skill(info)
  match result {
    Ok(_) => {
      @debug.assert_eq(provider.registered_count(), 1)
      assert_true(provider.has_skill("my-skill"))
    }
    Err(_e) => assert_true(false)
  }
}

///|
test "SkillProvider register_skill duplicate returns error" {
  let provider = SkillProvider::new([])
  let info : SkillInfo = {
    name: "dup-skill",
    description: "First",
    version: "1.0.0",
    category: "utility",
    user_invocable: true,
    allowed_tools: [],
    file_path: "a/SKILL.md",
    instructions: "",
  }
  let r1 = provider.register_skill(info)
  match r1 {
    Ok(_) => ()
    Err(_e) => assert_true(false)
  }
  let info2 : SkillInfo = {
    name: "dup-skill",
    description: "Second",
    version: "2.0.0",
    category: "utility",
    user_invocable: true,
    allowed_tools: [],
    file_path: "b/SKILL.md",
    instructions: "",
  }
  let r2 = provider.register_skill(info2)
  match r2 {
    Ok(_) => assert_true(false)
    Err(msg) => assert_true(msg.contains("already registered"))
  }
}

///|
test "SkillProvider has_skill returns false for unregistered" {
  let provider = SkillProvider::new([])
  assert_false(provider.has_skill("nonexistent"))
}

///|
test "SkillProvider list_registered returns all skills" {
  let provider = SkillProvider::new([])
  let s1 : SkillInfo = {
    name: "alpha",
    description: "A",
    version: "1.0.0",
    category: "utility",
    user_invocable: true,
    allowed_tools: [],
    file_path: "a/SKILL.md",
    instructions: "",
  }
  let s2 : SkillInfo = {
    name: "beta",
    description: "B",
    version: "1.0.0",
    category: "development",
    user_invocable: false,
    allowed_tools: ["Write"],
    file_path: "b/SKILL.md",
    instructions: "Build things",
  }
  provider.register_skill(s1) |> ignore
  provider.register_skill(s2) |> ignore
  let all = provider.list_registered()
  @debug.assert_eq(all.length(), 2)
  @debug.assert_eq(provider.registered_count(), 2)
}

///|
test "SkillProvider discover_skills returns empty without FFI" {
  let provider = SkillProvider::new(["some/dir", "another/dir"])
  let skills = provider.discover_skills()
  @debug.assert_eq(skills.length(), 0)
}

///|
test "parse_frontmatter_fields basic parsing" {
  let content = "---\nname: hello\ndescription: world\n---\n# Body"
  let (fields, body) = parse_frontmatter_fields(content)
  @debug.assert_eq(fields.get("name"), Some("hello"))
  @debug.assert_eq(fields.get("description"), Some("world"))
  assert_true(body.contains("Body"))
}

///|
test "parse_frontmatter_fields no frontmatter" {
  let content = "# Just a heading\nNo frontmatter."
  let (fields, body) = parse_frontmatter_fields(content)
  @debug.assert_eq(fields.length(), 0)
  assert_true(body.contains("Just a heading"))
}

///|
test "sp_strip_quotes removes double quotes" {
  @debug.assert_eq(sp_strip_quotes("\"hello\""), "hello")
  @debug.assert_eq(sp_strip_quotes("'world'"), "world")
  @debug.assert_eq(sp_strip_quotes("plain"), "plain")
  @debug.assert_eq(sp_strip_quotes(""), "")
}

///|
test "parse_yaml_list parses bracket notation" {
  let result = parse_yaml_list("[Write, Edit, Terminal]")
  @debug.assert_eq(result.length(), 3)
  @debug.assert_eq(result[0], "Write")
  @debug.assert_eq(result[1], "Edit")
  @debug.assert_eq(result[2], "Terminal")
  // Empty list
  let empty = parse_yaml_list("[]")
  @debug.assert_eq(empty.length(), 0)
}

///|
test "VirtualSkill from_skill_info creates correct skill" {
  let info : SkillInfo = {
    name: "my-ext",
    description: "My extension",
    version: "1.0.0",
    category: "development",
    user_invocable: true,
    allowed_tools: ["Write"],
    file_path: "skills/my-ext/SKILL.md",
    instructions: "Do stuff",
  }
  let vs = VirtualSkill::from_skill_info(info)
  @debug.assert_eq(vs.name, "my-ext")
  @debug.assert_eq(vs.description, "My extension")
  @debug.assert_eq(vs.mcp_server_name, "skill-provider")
  @debug.assert_eq(vs.mcp_tools.length(), 0)
  assert_true(vs.fork_agent)
}
