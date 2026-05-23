///| Skill management methods for Agent.

///|
/// Load skills from a map of file path → file content.
/// Discovered skills are registered into the agent's skill registry.
pub fn Agent::load_skills(
  self : Agent,
  file_contents : Map[String, String],
) -> Unit {
  let skills = @skill.discover_skills(file_contents)
  for skill in skills {
    self.skill_registry.register(skill)
  }
}

///|
/// Get a skill by name from the agent's skill registry.
pub fn Agent::get_skill(self : Agent, name : String) -> @skill.Skill? {
  self.skill_registry.get(name)
}

///|
/// Return a human-readable summary of all available skills.
/// Suitable for injection into the system prompt.
pub fn Agent::available_skills_summary(self : Agent) -> String {
  let skills = self.skill_registry.all()
  @skill.build_skills_summary(skills)
}
