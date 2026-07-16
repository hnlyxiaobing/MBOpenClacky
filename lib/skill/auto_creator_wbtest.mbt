///| White-box tests for AutoCreator skill file generation.

///|
test "auto_creator_create_skill_writes_valid_skill_md" {
  let ac = AutoCreator::new()
  let candidate : CreationCandidate = {
    name: "auto-wbtest-compile",
    description: "Compiles the MoonBit project with checks",
    pattern_count: 5,
    confidence: 90,
  }
  let test_dir = "./.test_auto_creator/skills"
  @utils.ensure_dir(test_dir)
  let skill_dir = test_dir + "/auto-wbtest-compile"
  let file_path = skill_dir + "/SKILL.md"
  @fs.remove_file(file_path) catch {
    _ => ()
  }
  let result = ac.create_skill(candidate, skills_dir=Some(test_dir))
  assert_true(result is Ok(_))
  let content = @fs.read_file_to_string(file_path)
  assert_true(content.contains("name: auto-wbtest-compile"))
  assert_true(content.contains("Compiles the MoonBit project with checks"))
  assert_true(content.contains("Trigger condition"))
  assert_true(content.contains("Suggested tool sequence"))
  match load_skill_from_content(content, file_path, Some(skill_dir)) {
    Some(skill) => @debug.assert_eq(skill.name, "auto-wbtest-compile")
    None => assert_true(false)
  }
}

///|
test "auto_creator_create_skill_low_confidence_fails" {
  let ac = AutoCreator::new() // confidence_threshold = 80
  let candidate : CreationCandidate = {
    name: "auto-wbtest-weak",
    description: "Weak pattern",
    pattern_count: 5,
    confidence: 50,
  }
  let result = ac.create_skill(
    candidate,
    skills_dir=Some("./.test_auto_creator/skills"),
  )
  assert_true(result is Err(_))
}

///|
test "auto_creator_create_skill_low_pattern_count_fails" {
  let ac = AutoCreator::with_thresholds(12, 50)
  let candidate : CreationCandidate = {
    name: "auto-wbtest-rare",
    description: "Rare pattern",
    pattern_count: 2,
    confidence: 90,
  }
  let result = ac.create_skill(
    candidate,
    skills_dir=Some("./.test_auto_creator/skills"),
  )
  assert_true(result is Err(_))
}
