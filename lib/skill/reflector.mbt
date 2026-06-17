///| Skill reflection engine — evaluates skill execution quality and suggests improvements.

///|
/// Configuration for skill post-execution reflection.
pub(all) struct SkillReflector {
  min_improvement_score : Int // default 70 — below this threshold, improvement is suggested
}

///|
/// Report generated after reflecting on a skill execution.
pub(all) struct ReflectionReport {
  skill_name : String
  performance_score : Int
  suggestions : Array[String]
  should_improve : Bool
} derive(Eq, Debug)

///|
/// Create a SkillReflector with default settings.
pub fn SkillReflector::new() -> SkillReflector {
  { min_improvement_score: 70 }
}

///|
/// Create a SkillReflector with a custom threshold.
pub fn SkillReflector::with_threshold(threshold : Int) -> SkillReflector {
  { min_improvement_score: threshold }
}

///|
/// Reflect on a skill execution and produce a performance report.
///
/// Scoring logic:
/// - Base score: 100
/// - Error keywords detected (error, fail, exception, panic): -30
/// - Warning keywords detected (warn, timeout, retry): -15
/// - Result too short (<10 chars): -20
/// - High iteration count (>5): -(iterations - 5) * 5
/// - Empty result: score = 10
pub fn SkillReflector::reflect(
  self : SkillReflector,
  skill_name : String,
  execution_result : String,
  iterations : Int,
) -> ReflectionReport {
  let suggestions : Array[String] = []
  // Empty result is a strong failure signal
  if execution_result.is_empty() {
    return {
      skill_name,
      performance_score: 10,
      suggestions: ["Execution produced no output — skill may be broken"],
      should_improve: true,
    }
  }
  let mut score = 100
  let lower_result = execution_result.to_lower()
  // Check error keywords
  let has_error = contains_any(lower_result, [
    "error", "fail", "exception", "panic",
  ])
  if has_error {
    score = score - 30
    suggestions.push("Execution result contains error indicators")
  }
  // Check warning keywords
  let has_warning = contains_any(lower_result, ["warn", "timeout", "retry"])
  if has_warning {
    score = score - 15
    suggestions.push("Execution result contains warning indicators")
  }
  // Result too short
  if execution_result.length() < 10 {
    score = score - 20
    suggestions.push(
      "Result is very short — may indicate incomplete execution",
    )
  }
  // High iteration penalty
  if iterations > 5 {
    let penalty = (iterations - 5) * 5
    score = score - penalty
    suggestions.push(
      "High iteration count (" +
      iterations.to_string() +
      ") — skill may need optimization",
    )
  }
  // Clamp score to [0, 100]
  if score < 0 {
    score = 0
  }
  if score > 100 {
    score = 100
  }
  let should_improve = score < self.min_improvement_score
  if should_improve && suggestions.is_empty() {
    suggestions.push("Score below threshold — consider reviewing skill logic")
  }
  { skill_name, performance_score: score, suggestions, should_improve }
}

///|
/// Apply improvements to a skill based on its reflection report.
/// Currently a placeholder — real implementation would invoke LLM or code modification.
pub fn SkillReflector::apply_improvements(
  self : SkillReflector,
  report : ReflectionReport,
) -> Result[String, String] {
  // TODO: Implement actual skill improvement logic (LLM-driven refactoring)
  ignore(self)
  if !report.should_improve {
    return Err("No improvement needed — score is above threshold")
  }
  Ok(
    "Improvement plan generated for skill: " +
    report.skill_name +
    " (placeholder)",
  )
}

// ============================================================
// Internal helpers
// ============================================================

///|
/// Check if a string contains any of the given keywords.
fn contains_any(text : String, keywords : Array[String]) -> Bool {
  for kw in keywords {
    if text.find(kw) is Some(_) {
      return true
    }
  }
  false
}
