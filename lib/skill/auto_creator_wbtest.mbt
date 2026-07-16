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

///|
test "auto_creator_new_defaults" {
  let ac = AutoCreator::new()
  @debug.assert_eq(ac.iteration_threshold, 12)
  @debug.assert_eq(ac.confidence_threshold, 80)
}

///|
test "auto_creator_with_thresholds_custom" {
  let ac = AutoCreator::with_thresholds(5, 60)
  @debug.assert_eq(ac.iteration_threshold, 5)
  @debug.assert_eq(ac.confidence_threshold, 60)
}

///|
test "detect_candidates: below iteration threshold returns empty" {
  let ac = AutoCreator::new()
  let history = [
    "Please compile the project with moon check", "Please compile the project with moon check",
    "Please compile the project with moon check",
  ]
  let candidates = ac.detect_candidates(history, 5)
  assert_eq(candidates.length(), 0)
}

///|
test "detect_candidates: history too short returns empty" {
  let ac = AutoCreator::new()
  let history = ["short message one", "short message two"]
  let candidates = ac.detect_candidates(history, 15)
  assert_eq(candidates.length(), 0)
}

///|
test "detect_candidates: detects repeated pattern" {
  let ac = AutoCreator::new()
  let history = [
    "Please compile the project with moon check before testing", "Please compile the project with moon check after editing",
    "Please compile the project with moon check for validation",
  ]
  let candidates = ac.detect_candidates(history, 15)
  assert_true(candidates.length() >= 1)
  let first = candidates[0]
  assert_true(first.name.has_prefix("auto-"))
  assert_eq(first.pattern_count, 3)
  assert_true(first.confidence >= 80)
}

///|
test "detect_candidates: skips short messages" {
  let ac = AutoCreator::new()
  let history = [
    "short", "short", "short", "this is a longer message with enough text to pass",
    "this is a longer message with enough text to pass", "this is a longer message with enough text to pass",
  ]
  let candidates = ac.detect_candidates(history, 15)
  assert_true(candidates.length() >= 1)
  assert_true(candidates[0].pattern_count == 3)
}

///|
test "detect_candidates: skips single-word messages" {
  let ac = AutoCreator::new()
  let history = [
    "compiletheprojectwithmooncheckbeforetesting", "compiletheprojectwithmooncheckbeforetesting",
    "compiletheprojectwithmooncheckbeforetesting",
  ]
  let candidates = ac.detect_candidates(history, 15)
  assert_eq(candidates.length(), 0)
}

///|
test "detect_candidates: below confidence threshold filtered" {
  let ac = AutoCreator::with_thresholds(1, 100)
  let history = [
    "Please compile the project with moon check and run tests", "Please compile the project with moon build and run tests",
    "Please compile the project with moon test and run tests",
  ]
  let candidates = ac.detect_candidates(history, 1)
  assert_eq(candidates.length(), 0)
}

///|
test "calculate_confidence: base confidence from count" {
  let group = ["msg one with text", "msg two with text", "msg three with text"]
  let conf = calculate_confidence(3, group)
  @debug.assert_eq(conf, 90) // 50 + 3*10 + 10(low variance) = 90
}

///|
test "calculate_confidence: high variance reduces confidence" {
  let group = [
    "x", "x", "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  ]
  let conf = calculate_confidence(3, group)
  assert_true(conf <= 80)
}

///|
test "calculate_confidence: clamped to 100" {
  let group = [
    "same length msg!!", "same length msg!!", "same length msg!!", "same length msg!!",
    "same length msg!!", "same length msg!!",
  ]
  let conf = calculate_confidence(6, group)
  @debug.assert_eq(conf, 100) // 50 + 6*10 = 110, clamped to 100
}

///|
test "calculate_confidence: zero count with low variance" {
  let group = ["x", "x", "x"]
  let conf = calculate_confidence(0, group)
  @debug.assert_eq(conf, 60) // 50 + 0*10 + 10(low variance) = 60
}

///|
test "generate_skill_name: lowercase conversion" {
  let name = generate_skill_name("Please Compile Project")
  assert_eq(name, "auto-please-compile-")
}

///|
test "generate_skill_name: handles special chars" {
  let name = generate_skill_name("Test@#$%Pattern")
  assert_eq(name, "auto-testpattern")
}

///|
test "generate_skill_name: max 15 chars" {
  let name = generate_skill_name("This is a very long prefix for testing")
  @debug.assert_eq(name.length(), 20) // "auto-" (5) + max 15 chars
  assert_true(name.has_prefix("auto-"))
}

///|
test "has_space: with space returns true" {
  assert_true(has_space("hello world"))
}

///|
test "has_space: without space returns false" {
  assert_false(has_space("helloworld"))
}

///|
test "has_space: empty string returns false" {
  assert_false(has_space(""))
}

///|
test "string_prefix: returns first n chars" {
  let result = string_prefix("hello world", 5)
  assert_eq(result, "hello")
}

///|
test "string_prefix: string shorter than n returns full" {
  let result = string_prefix("hi", 10)
  assert_eq(result, "hi")
}

///|
test "string_prefix: empty string returns empty" {
  let result = string_prefix("", 5)
  assert_eq(result, "")
}

///|
test "CreationCandidate: equality comparison" {
  let c1 : CreationCandidate = {
    name: "test-skill",
    description: "A test",
    pattern_count: 3,
    confidence: 80,
  }
  let c2 : CreationCandidate = {
    name: "test-skill",
    description: "A test",
    pattern_count: 3,
    confidence: 80,
  }
  let c3 : CreationCandidate = {
    name: "other-skill",
    description: "A test",
    pattern_count: 3,
    confidence: 80,
  }
  assert_eq(c1, c2)
  assert_not_eq(c1, c3)
}
