///|
/// A registry for managing skills.
pub(all) struct SkillRegistry {
  mut skills : Map[String, Skill]
  discovery_paths : Array[String]
}

///|
/// Create a new empty SkillRegistry.
pub fn SkillRegistry::new() -> SkillRegistry {
  { skills: Map([]), discovery_paths: [] }
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
/// Resolve a slash-command text ("/name optional arguments") to a
/// user-invocable skill and its argument string (Ruby skills_by_command).
///
/// Returns None when the text is not a single "/word" command or no
/// user-invocable skill matches the name. Callers decide the fallback
/// (regular input) — static slash commands must be checked BEFORE this
/// (priority: static commands > skill registry > regular input).
pub fn SkillRegistry::find_skill_command(
  self : SkillRegistry,
  text : String,
) -> (Skill, String)? {
  let trimmed = text.trim().to_owned()
  if !trimmed.has_prefix("/") {
    return None
  }
  let body = trimmed[1:].to_owned()
  if body.length() == 0 || body.contains("/") {
    return None
  }
  let (name, args) = match body.find(" ") {
    Some(i) => (body[0:i].to_owned(), body[i + 1:].trim().to_owned())
    None => (body, "")
  }
  match self.skills.get(name) {
    Some(skill) => if skill.user_invocable { Some((skill, args)) } else { None }
    None => None
  }
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
