///|
/// A registry for managing skills.
pub(all) struct SkillRegistry {
  mut skills : Map[String, Skill]
  discovery_paths : Array[String]
}

///|
/// Create a new empty SkillRegistry.
pub fn SkillRegistry::new() -> SkillRegistry {
  { skills: {}, discovery_paths: [] }
}

///|
/// Register a skill in the registry.
pub fn SkillRegistry::register(self : SkillRegistry, skill : Skill) -> Unit {
  self.skills[skill.name] = skill
}

///|
/// Get a skill by name.
pub fn SkillRegistry::get(self : SkillRegistry, name : String) -> Skill? {
  self.skills.get(name)
}

///|
/// List all skills that are user-invocable.
pub fn SkillRegistry::list_user_invocable(self : SkillRegistry) -> Array[Skill] {
  let result : Array[Skill] = []
  for _, skill in self.skills {
    if skill.user_invocable {
      result.push(skill)
    }
  }
  result
}

///|
/// List all skills filtered by agent_type.
pub fn SkillRegistry::list_by_agent_type(
  self : SkillRegistry,
  agent_type : String,
) -> Array[Skill] {
  let result : Array[Skill] = []
  for _, skill in self.skills {
    match skill.agent_type {
      Some(t) => if t == agent_type { result.push(skill) }
      None => ()
    }
  }
  result
}

///|
/// Return all skills as an array.
pub fn SkillRegistry::all(self : SkillRegistry) -> Array[Skill] {
  let result : Array[Skill] = []
  for _, skill in self.skills {
    result.push(skill)
  }
  result
}

///|
/// Check if a skill with the given name exists.
pub fn SkillRegistry::has(self : SkillRegistry, name : String) -> Bool {
  self.skills.contains(name)
}

///|
/// Return the number of registered skills.
pub fn SkillRegistry::size(self : SkillRegistry) -> Int {
  self.skills.length()
}

///|
/// Remove a skill by name. Returns true if it existed.
pub fn SkillRegistry::remove(self : SkillRegistry, name : String) -> Bool {
  if self.skills.contains(name) {
    self.skills.remove(name)
    true
  } else {
    false
  }
}
