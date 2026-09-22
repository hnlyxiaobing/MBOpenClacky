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
pub extend ReflectionReport with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ReflectionReport with Eq::{not_equal, equal}

///|
/// Create a SkillReflector with default settings.
pub fn SkillReflector::new() -> SkillReflector {
  { min_improvement_score: 70, }
}

///|
/// Create a SkillReflector with a custom threshold.
pub fn SkillReflector::with_threshold(threshold : Int) -> SkillReflector {
  { min_improvement_score: threshold, }
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
  { skill_name, performance_score: score, suggestions, should_improve, }
}

///|
/// A structured improvement proposal parsed from an LLM reflection response.
///
/// `revised_skill_md` is `None` when the model declined to produce a rewrite
/// (e.g. it judged the skill definition already adequate) or supplied an empty
/// string.
pub(all) struct ReflectionProposal {
  suggestions : Array[String]
  revised_skill_md : String?
} derive(Eq, Debug)

///|
pub extend ReflectionProposal with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ReflectionProposal with Eq::{not_equal, equal}

///|
/// Apply improvements to a skill based on its reflection report.
///
/// The proposal itself is produced by an LLM (see `build_reflection_prompt` /
/// `parse_reflection_response`); this function only decides whether a proposal
/// is warranted.
pub fn SkillReflector::needs_proposal(
  self : SkillReflector,
  report : ReflectionReport,
) -> Bool {
  ignore(self)
  report.should_improve
}

///|
/// Build the LLM prompt used to reflect on a skill after a real execution.
///
/// The model is asked for a strict JSON object so the caller can parse a
/// `ReflectionProposal` without heuristics (see `parse_reflection_response`).
/// The execution evidence is truncated by `truncate_evidence` to bound cost.
pub fn build_reflection_prompt(
  report : ReflectionReport,
  skill_content : String,
  transcript : String,
) -> String {
  let flags = if report.suggestions.is_empty() {
    "(none)"
  } else {
    report.suggestions.join("\n- ")
  }
  let prompt = "You are reviewing an agent skill definition after a real execution.\n" +
    "\n" +
    "## Skill under review\n" +
    "name: " +
    report.skill_name +
    "\n" +
    "<skill_definition>\n" +
    skill_content +
    "\n</skill_definition>\n" +
    "\n" +
    "## Execution evidence\n" +
    "<transcript>\n" +
    truncate_evidence(transcript) +
    "\n</transcript>\n" +
    "\n" +
    "## Automated pre-assessment\n" +
    "- score: " +
    report.performance_score.to_string() +
    "/100\n" +
    "- flags:\n- " +
    flags +
    "\n" +
    "\n" +
    "## Your task\n" +
    "1. Identify the concrete reasons the execution went the way it did, citing the evidence.\n" +
    "2. Propose specific, actionable improvements to the skill (missing steps, pitfalls to document, clearer instructions).\n" +
    "3. Produce a complete revised skill definition that preserves the existing YAML frontmatter keys.\n" +
    "\n" +
    "## Output format\n" +
    "Return ONLY a JSON object — no prose, no code fences:\n" +
    "{\"suggestions\": [\"...\"], \"revised_skill_md\": \"<full revised skill, or null>\"}"
  prompt
}

///|
/// Parse an LLM reflection response into a structured proposal.
///
/// Tolerates the shapes models actually emit: markdown code fences, leading or
/// trailing prose, and a `null`/absent `revised_skill_md`. Returns a
/// diagnosable `Err` when no usable JSON object is present.
pub fn parse_reflection_response(
  text : String,
) -> Result[ReflectionProposal, String] {
  let json_text = match extract_json_object(text) {
    Some(j) => j
    None => return Err("Reflection response contains no JSON object")
  }
  let parsed : Json = @json.parse(json_text) catch {
    e =>
      return Err(
        "Reflection response is not valid JSON: " + @debug.to_string(e),
      )
  }
  match parsed {
    Object(obj) => {
      let suggestions : Array[String] = match obj.get("suggestions") {
        Some(Array(arr)) => {
          let out : Array[String] = []
          for item in arr {
            match item {
              String(s) => if !s.trim().is_empty() { out.push(s) }
              _ => ()
            }
          }
          out
        }
        _ =>
          return Err("Reflection response is missing a \"suggestions\" array")
      }
      let revised : String? = match obj.get("revised_skill_md") {
        Some(String(s)) => if s.trim().is_empty() { None } else { Some(s) }
        _ => None
      }
      Ok({ suggestions, revised_skill_md: revised, })
    }
    _ => Err("Reflection response JSON is not an object")
  }
}

// ============================================================
// Internal helpers
// ============================================================

///|
/// Extract the first brace-balanced JSON object from free-form model output.
///
/// Works on the char array (not byte offsets) so multi-byte content cannot
/// split a character; quote and escape state are tracked so braces inside
/// string literals do not affect nesting depth.
fn extract_json_object(text : String) -> String? {
  let chars = text.to_array()
  let mut start = -1
  for i = 0; i < chars.length(); i = i + 1 {
    if chars[i] == '{' {
      start = i
      break
    }
  }
  if start < 0 {
    return None
  }
  let mut depth = 0
  let mut in_string = false
  let mut escaped = false
  for i = start; i < chars.length(); i = i + 1 {
    let c = chars[i]
    if in_string {
      if escaped {
        escaped = false
      } else if c == '\\' {
        escaped = true
      } else if c == '"' {
        in_string = false
      }
      continue
    }
    if c == '"' {
      in_string = true
    } else if c == '{' {
      depth = depth + 1
    } else if c == '}' {
      depth = depth - 1
      if depth == 0 {
        let slice : Array[Char] = []
        for k = start; k <= i; k = k + 1 {
          slice.push(chars[k])
        }
        return Some(String::from_array(slice))
      }
    }
  }
  None
}

///|
/// Bound the execution evidence embedded in the prompt, keeping both ends so
/// the failure is visible alongside the goal.
fn truncate_evidence(transcript : String) -> String {
  let limit = 12000
  let chars = transcript.to_array()
  if chars.length() <= limit {
    return transcript
  }
  let head_len = limit * 2 / 3
  let tail_len = limit - head_len
  let head : Array[Char] = []
  for i = 0; i < head_len; i = i + 1 {
    head.push(chars[i])
  }
  let tail : Array[Char] = []
  for i = chars.length() - tail_len; i < chars.length(); i = i + 1 {
    tail.push(chars[i])
  }
  String::from_array(head) +
  "\n... [evidence truncated: " +
  (chars.length() - limit).to_string() +
  " chars omitted] ...\n" +
  String::from_array(tail)
}

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
