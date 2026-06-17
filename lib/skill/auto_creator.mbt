///| Auto skill creator — detects repeated patterns in conversation and proposes new skills.

///|
/// Configuration for automatic skill creation.
pub(all) struct AutoCreator {
  iteration_threshold : Int // default 12 — min iterations before auto-creation triggers
  confidence_threshold : Int // default 80 — min confidence to create a skill
}

///|
/// A candidate skill detected from conversation patterns.
pub(all) struct CreationCandidate {
  name : String
  description : String
  pattern_count : Int // number of times the pattern was detected
  confidence : Int // 0-100 confidence score
} derive(Eq, Debug)

///|
/// Create an AutoCreator with default settings.
pub fn AutoCreator::new() -> AutoCreator {
  { iteration_threshold: 12, confidence_threshold: 80 }
}

///|
/// Create an AutoCreator with custom thresholds.
pub fn AutoCreator::with_thresholds(
  iteration_threshold : Int,
  confidence_threshold : Int,
) -> AutoCreator {
  { iteration_threshold, confidence_threshold }
}

///|
/// Detect candidate skills from conversation history.
///
/// Detection criteria:
/// 1. Repeated patterns (>=3 similar strings based on prefix matching)
/// 2. Sufficient length (pattern > 20 characters)
/// 3. Non-trivial (more than one word)
/// 4. Confidence above threshold
/// 5. Iteration count meets threshold
pub fn AutoCreator::detect_candidates(
  self : AutoCreator,
  history : Array[String],
  iteration_count : Int,
) -> Array[CreationCandidate] {
  let candidates : Array[CreationCandidate] = []
  // Early exit if history is too small or iterations below threshold
  if history.length() < 3 || iteration_count < self.iteration_threshold {
    return candidates
  }
  // Find repeated prefixes — group by prefix of length min(20, string_len)
  let prefix_groups : Map[String, Array[String]] = {}
  for msg in history {
    let trimmed = msg.trim().to_owned()
    // Skip short or trivial messages
    if trimmed.length() <= 20 {
      continue
    }
    // Skip single-word messages
    if !has_space(trimmed) {
      continue
    }
    let prefix = string_prefix(trimmed, 20)
    match prefix_groups.get(prefix) {
      Some(group) => group.push(trimmed)
      None => prefix_groups[prefix] = [trimmed]
    }
  }
  // Filter groups with >= 3 occurrences
  for prefix, group in prefix_groups {
    if group.length() >= 3 {
      let pattern_count = group.length()
      // Calculate confidence: base on pattern count and consistency
      let confidence = calculate_confidence(pattern_count, group)
      if confidence >= self.confidence_threshold {
        let name = generate_skill_name(prefix)
        let description = "Auto-detected pattern: \"" +
          prefix +
          "...\" (seen " +
          pattern_count.to_string() +
          " times)"
        candidates.push({ name, description, pattern_count, confidence })
      }
    }
  }
  candidates
}

///|
/// Create a skill from a candidate.
/// Currently a placeholder — real implementation would generate SKILL.md content.
pub fn AutoCreator::create_skill(
  self : AutoCreator,
  candidate : CreationCandidate,
) -> Result[String, String] {
  if candidate.confidence < self.confidence_threshold {
    return Err(
      "Confidence too low: " +
      candidate.confidence.to_string() +
      " < " +
      self.confidence_threshold.to_string(),
    )
  }
  if candidate.pattern_count < 3 {
    return Err(
      "Pattern count too low: " + candidate.pattern_count.to_string() + " < 3",
    )
  }
  // TODO: Generate actual SKILL.md file content and write to disk
  Ok(
    "Skill created: " +
    candidate.name +
    " — " +
    candidate.description +
    " (placeholder)",
  )
}

// ============================================================
// Internal helpers for AutoCreator
// ============================================================

///|
/// Check if a string contains at least one space.
fn has_space(s : String) -> Bool {
  s.find(" ") is Some(_)
}

///|
/// Get the first `n` characters of a string (or full string if shorter).
fn string_prefix(s : String, n : Int) -> String {
  let chars = s.to_array()
  let len = if chars.length() < n { chars.length() } else { n }
  let buf = StringBuilder::new()
  for i = 0; i < len; i = i + 1 {
    buf.write_char(chars[i])
  }
  buf.to_string()
}

///|
/// Calculate confidence score based on pattern count and group consistency.
/// More repetitions and more similar lengths increase confidence.
fn calculate_confidence(pattern_count : Int, group : Array[String]) -> Int {
  // Base confidence from repetition count: 50 + count * 10, capped at 100
  let mut confidence = 50 + pattern_count * 10
  // Bonus for consistent lengths (low variance)
  let avg_len = {
    let mut sum = 0
    for s in group {
      sum = sum + s.length()
    }
    sum / group.length()
  }
  let mut variance = 0
  for s in group {
    let diff = s.length() - avg_len
    variance = variance + (if diff < 0 { -diff } else { diff })
  }
  let avg_variance = variance / group.length()
  // Low variance (< 20) gives bonus, high variance penalizes
  if avg_variance < 20 {
    confidence = confidence + 10
  } else if avg_variance > 50 {
    confidence = confidence - 10
  }
  // Clamp to [0, 100]
  if confidence < 0 {
    confidence = 0
  }
  if confidence > 100 {
    confidence = 100
  }
  confidence
}

///|
/// Generate a skill name from a prefix pattern.
fn generate_skill_name(prefix : String) -> String {
  let buf = StringBuilder::new()
  buf.write_string("auto-")
  let chars = prefix.to_array()
  let mut count = 0
  for c in chars {
    if count >= 15 {
      break
    }
    if c == ' ' || c == '_' || c == '-' {
      buf.write_char('-')
      count = count + 1
    } else if c >= 'A' && c <= 'Z' {
      // Convert to lowercase
      let lower_code = c.to_int() + 32
      buf.write_char(lower_code.unsafe_to_char())
      count = count + 1
    } else if (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') {
      buf.write_char(c)
      count = count + 1
    }
    // Skip other characters
  }
  buf.to_string()
}
