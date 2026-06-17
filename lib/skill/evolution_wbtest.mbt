///| White-box tests for the skill evolution system (reflector, auto_creator, evolution engine).

// ============================================================
// SkillReflector tests
// ============================================================

///|
test "reflector_scoring_success_result" {
  let r = SkillReflector::new()
  let report = r.reflect(
    "my-skill", "Task completed successfully with output", 3,
  )
  assert_eq(report.performance_score, 100)
  assert_eq(report.should_improve, false)
  assert_eq(report.suggestions.length(), 0)
}

///|
test "reflector_scoring_error_result" {
  let r = SkillReflector::new()
  let report = r.reflect("buggy-skill", "An error occurred during execution", 2)
  // -30 for error keyword
  assert_eq(report.performance_score, 70)
  assert_eq(report.suggestions.length(), 1)
}

///|
test "reflector_scoring_warning_result" {
  let r = SkillReflector::new()
  let report = r.reflect(
    "warn-skill", "Warning: timeout detected in process", 1,
  )
  // "warn" and "timeout" are both warning keywords -> -15 (single check)
  assert_eq(report.performance_score, 85)
}

///|
test "reflector_scoring_error_and_warning" {
  let r = SkillReflector::new()
  let report = r.reflect(
    "bad-skill", "Error occurred and retry was attempted multiple times", 2,
  )
  // -30 for error, -15 for warning (retry)
  assert_eq(report.performance_score, 55)
  assert_eq(report.should_improve, true)
}

///|
test "reflector_scoring_high_iterations" {
  let r = SkillReflector::new()
  let report = r.reflect("slow-skill", "Task completed after many rounds", 10)
  // iterations 10 > 5 -> penalty = (10-5)*5 = 25
  assert_eq(report.performance_score, 75)
}

///|
test "reflector_scoring_very_high_iterations" {
  let r = SkillReflector::new()
  let report = r.reflect("very-slow", "Done with all operations complete", 20)
  // penalty = (20-5)*5 = 75, score = 100 - 75 = 25
  assert_eq(report.performance_score, 25)
  assert_eq(report.should_improve, true)
}

///|
test "reflector_scoring_short_result" {
  let r = SkillReflector::new()
  let report = r.reflect("terse-skill", "ok done", 1)
  // "ok done" = 7 chars < 10 -> -20
  assert_eq(report.performance_score, 80)
}

///|
test "reflector_scoring_empty_result" {
  let r = SkillReflector::new()
  let report = r.reflect("empty-skill", "", 1)
  assert_eq(report.performance_score, 10)
  assert_eq(report.should_improve, true)
  assert_eq(report.suggestions.length(), 1)
}

///|
test "reflector_should_improve_threshold" {
  let r = SkillReflector::with_threshold(90)
  let report = r.reflect("mid-skill", "Task completed with some output text", 6)
  // iterations 6 > 5 -> penalty = 5, score = 95
  assert_eq(report.performance_score, 95)
  assert_eq(report.should_improve, false)
  // Now with iterations = 8 -> penalty = 15, score = 85 < 90
  let report2 = r.reflect(
    "mid-skill", "Task completed with some output text", 8,
  )
  assert_eq(report2.performance_score, 85)
  assert_eq(report2.should_improve, true)
}

///|
test "reflector_apply_improvements_needed" {
  let r = SkillReflector::new()
  let report : ReflectionReport = {
    skill_name: "broken-skill",
    performance_score: 40,
    suggestions: ["Has errors"],
    should_improve: true,
  }
  let result = r.apply_improvements(report)
  assert_true(result is Ok(_))
}

///|
test "reflector_apply_improvements_not_needed" {
  let r = SkillReflector::new()
  let report : ReflectionReport = {
    skill_name: "good-skill",
    performance_score: 95,
    suggestions: [],
    should_improve: false,
  }
  let result = r.apply_improvements(report)
  assert_true(result is Err(_))
}

///|
test "reflector_score_clamped_to_zero" {
  let r = SkillReflector::new()
  // error(-30) + warning(-15) + short(-20) + iterations 25 => penalty=(25-5)*5=100
  // total: 100 - 30 - 15 - 20 - 100 = -65 -> clamped to 0
  let report = r.reflect("disaster", "err warn", 25)
  assert_eq(report.performance_score, 0)
}

// ============================================================
// AutoCreator tests
// ============================================================

///|
test "auto_creator_detect_no_history" {
  let ac = AutoCreator::new()
  let candidates = ac.detect_candidates([], 15)
  assert_eq(candidates.length(), 0)
}

///|
test "auto_creator_detect_below_iteration_threshold" {
  let ac = AutoCreator::new() // threshold = 12
  let history = [
    "Please run the build command now", "Please run the build command now", "Please run the build command now",
  ]
  // iteration_count = 5 < 12
  let candidates = ac.detect_candidates(history, 5)
  assert_eq(candidates.length(), 0)
}

///|
test "auto_creator_detect_short_messages_ignored" {
  let ac = AutoCreator::new()
  let history = ["short msg", "short msg", "short msg", "short msg"]
  let candidates = ac.detect_candidates(history, 15)
  assert_eq(candidates.length(), 0)
}

///|
test "auto_creator_detect_single_word_ignored" {
  let ac = AutoCreator::new()
  let history = [
    "abcdefghijklmnopqrstuvwxyz", "abcdefghijklmnopqrstuvwxyz", "abcdefghijklmnopqrstuvwxyz",
  ]
  let candidates = ac.detect_candidates(history, 15)
  assert_eq(candidates.length(), 0)
}

///|
test "auto_creator_detect_repeated_patterns" {
  let ac = AutoCreator::with_thresholds(1, 50) // low thresholds for testing
  let history = [
    "Please compile the MoonBit project with full checks", "Please compile the MoonBit project with test run",
    "Please compile the MoonBit project and deploy", "Please compile the MoonBit project for release",
  ]
  let candidates = ac.detect_candidates(history, 15)
  assert_true(candidates.length() > 0)
  assert_true(candidates[0].pattern_count >= 3)
}

///|
test "auto_creator_confidence_calculation" {
  let ac = AutoCreator::with_thresholds(1, 0) // no threshold filtering
  let history = [
    "Run the deployment script for production environment now", "Run the deployment script for staging environment now",
    "Run the deployment script for testing environment now", "Run the deployment script for development environment now",
    "Run the deployment script for integration environment now",
  ]
  let candidates = ac.detect_candidates(history, 15)
  assert_true(candidates.length() > 0)
  // 5 occurrences -> base confidence = 50 + 5*10 = 100, clamped to 100
  assert_true(candidates[0].confidence >= 80)
}

///|
test "auto_creator_create_skill_valid" {
  let ac = AutoCreator::new()
  let candidate : CreationCandidate = {
    name: "auto-compile",
    description: "Compiles project",
    pattern_count: 5,
    confidence: 90,
  }
  let result = ac.create_skill(candidate)
  assert_true(result is Ok(_))
}

///|
test "auto_creator_create_skill_low_confidence" {
  let ac = AutoCreator::new() // confidence_threshold = 80
  let candidate : CreationCandidate = {
    name: "auto-weak",
    description: "Weak pattern",
    pattern_count: 5,
    confidence: 50,
  }
  let result = ac.create_skill(candidate)
  assert_true(result is Err(_))
}

///|
test "auto_creator_create_skill_low_pattern_count" {
  let ac = AutoCreator::with_thresholds(12, 50)
  let candidate : CreationCandidate = {
    name: "auto-rare",
    description: "Rare pattern",
    pattern_count: 2,
    confidence: 90,
  }
  let result = ac.create_skill(candidate)
  assert_true(result is Err(_))
}

// ============================================================
// EvolutionEngine tests
// ============================================================

///|
test "evolution_engine_post_execution_high_score" {
  let engine = EvolutionEngine::new()
  let scenario = PostExecution(
    skill_name="good-skill",
    result="Successfully completed all operations with full output",
    iterations=2,
  )
  let result = engine.evolve(scenario)
  assert_true(result is Ok(_))
  let r = result.unwrap()
  assert_eq(r.action, NoChange)
  assert_eq(r.skill_name, "good-skill")
}

///|
test "evolution_engine_post_execution_low_score" {
  let engine = EvolutionEngine::new()
  let scenario = PostExecution(
    skill_name="bad-skill",
    result="error: compilation failed with panic",
    iterations=8,
  )
  let result = engine.evolve(scenario)
  assert_true(result is Ok(_))
  let r = result.unwrap()
  assert_eq(r.action, Improved)
  assert_eq(r.skill_name, "bad-skill")
}

///|
test "evolution_engine_auto_detect_no_patterns" {
  let engine = EvolutionEngine::new()
  let scenario = AutoDetect(
    conversation_history=["hello", "world", "short"],
    iteration_count=15,
  )
  let result = engine.evolve(scenario)
  assert_true(result is Ok(_))
  let r = result.unwrap()
  assert_eq(r.action, NoChange)
}

///|
test "evolution_engine_auto_detect_with_patterns" {
  let engine = EvolutionEngine::with_components(
    SkillReflector::new(),
    AutoCreator::with_thresholds(1, 50),
  )
  let scenario = AutoDetect(
    conversation_history=[
      "Please run the full test suite with coverage report", "Please run the full test suite with coverage report",
      "Please run the full test suite with coverage report", "Please run the full test suite with coverage report",
    ],
    iteration_count=15,
  )
  let result = engine.evolve(scenario)
  assert_true(result is Ok(_))
  let r = result.unwrap()
  assert_eq(r.action, Created)
}

///|
test "evolution_engine_auto_detect_below_iteration" {
  let engine = EvolutionEngine::new() // iteration_threshold = 12
  let scenario = AutoDetect(
    conversation_history=[
      "Please do the same thing again with different params", "Please do the same thing again with different params",
      "Please do the same thing again with different params",
    ],
    iteration_count=5, // below 12
  )
  let result = engine.evolve(scenario)
  assert_true(result is Ok(_))
  let r = result.unwrap()
  assert_eq(r.action, NoChange)
}

///|
test "evolution_engine_post_execution_empty_result" {
  let engine = EvolutionEngine::new()
  let scenario = PostExecution(
    skill_name="ghost-skill",
    result="",
    iterations=1,
  )
  let result = engine.evolve(scenario)
  assert_true(result is Ok(_))
  let r = result.unwrap()
  // Empty result -> score 10 -> should_improve -> Improved
  assert_eq(r.action, Improved)
}

// ============================================================
// Helper function tests
// ============================================================

///|
test "string_prefix_basic" {
  let p = string_prefix("Hello World Test String", 5)
  assert_eq(p, "Hello")
}

///|
test "string_prefix_shorter_than_n" {
  let p = string_prefix("Hi", 20)
  assert_eq(p, "Hi")
}

///|
test "has_space_true" {
  assert_true(has_space("hello world"))
}

///|
test "has_space_false" {
  assert_true(!has_space("helloworld"))
}

///|
test "generate_skill_name_basic" {
  let name = generate_skill_name("run the build proce")
  // Should produce: auto-run-the-build-pr (truncated to 15 chars after auto-)
  assert_true(name.find("auto-") is Some(_))
}

///|
test "contains_any_found" {
  assert_true(contains_any("this has an error in it", ["error", "fail"]))
}

///|
test "contains_any_not_found" {
  assert_true(!contains_any("everything is fine", ["error", "fail"]))
}
