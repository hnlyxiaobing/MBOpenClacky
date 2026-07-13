///| Skill evolution engine — orchestrates self-improvement and auto-creation of skills.

///|
/// The evolution engine coordinates two sub-systems:
/// - SkillReflector: Post-execution analysis and improvement
/// - AutoCreator: Pattern-based automatic skill creation
pub(all) struct EvolutionEngine {
  reflector : SkillReflector
  auto_creator : AutoCreator
}

///|
/// Scenarios that trigger evolution.
pub(all) enum EvolutionScenario {
  /// After a skill finishes executing — reflect on its performance.
  PostExecution(skill_name~ : String, result~ : String, iterations~ : Int)
  /// During conversation — detect repeated patterns that could become skills.
  AutoDetect(conversation_history~ : Array[String], iteration_count~ : Int)
}

///|
/// The action taken by the evolution engine.
pub(all) enum EvolutionAction {
  Created
  Improved
  NoChange
} derive(Eq, Debug)

///|
/// Result of an evolution operation.
pub(all) struct EvolutionResult {
  action : EvolutionAction
  skill_name : String
  diff_summary : String
} derive(Eq, Debug)

///|
/// Create an EvolutionEngine with default settings.
pub fn EvolutionEngine::new() -> EvolutionEngine {
  { reflector: SkillReflector::new(), auto_creator: AutoCreator::new() }
}

///|
/// Create an EvolutionEngine with custom sub-components.
pub fn EvolutionEngine::with_components(
  reflector : SkillReflector,
  auto_creator : AutoCreator,
) -> EvolutionEngine {
  { reflector, auto_creator }
}

///|
/// Main entry point: dispatch to the appropriate evolution strategy based on scenario.
pub fn EvolutionEngine::evolve(
  self : EvolutionEngine,
  scenario : EvolutionScenario,
) -> Result[EvolutionResult, String] {
  match scenario {
    PostExecution(skill_name~, result~, iterations~) =>
      self.handle_post_execution(skill_name, result, iterations)
    AutoDetect(conversation_history~, iteration_count~) =>
      self.handle_auto_detect(conversation_history, iteration_count)
  }
}

///|
/// Handle post-execution reflection scenario.
fn EvolutionEngine::handle_post_execution(
  self : EvolutionEngine,
  skill_name : String,
  result : String,
  iterations : Int,
) -> Result[EvolutionResult, String] {
  let report = self.reflector.reflect(skill_name, result, iterations)
  if !report.should_improve {
    return Ok({
      action: NoChange,
      skill_name,
      diff_summary: "Score " +
      report.performance_score.to_string() +
      "/100 — no improvement needed",
    })
  }
  // Attempt to apply improvements
  match self.reflector.apply_improvements(report) {
    Ok(msg) => Ok({ action: Improved, skill_name, diff_summary: msg })
    Err(e) => Err("Failed to apply improvements: " + e)
  }
}

///|
/// Handle auto-detection scenario.
fn EvolutionEngine::handle_auto_detect(
  self : EvolutionEngine,
  conversation_history : Array[String],
  iteration_count : Int,
) -> Result[EvolutionResult, String] {
  let candidates = self.auto_creator.detect_candidates(
    conversation_history, iteration_count,
  )
  if candidates.is_empty() {
    return Ok({
      action: NoChange,
      skill_name: "",
      diff_summary: "No repeated patterns detected",
    })
  }
  // Pick the best candidate (highest confidence)
  let mut best = candidates[0]
  for i = 1; i < candidates.length(); i = i + 1 {
    if candidates[i].confidence > best.confidence {
      best = candidates[i]
    }
  }
  // Try to create the skill
  match self.auto_creator.create_skill(best) {
    Ok(msg) => Ok({ action: Created, skill_name: best.name, diff_summary: msg })
    Err(e) => Err("Failed to create skill: " + e)
  }
}
