///|
/// A registry for managing skills.
pub(all) struct SkillRegistry {
  mut skills : Map[String, Skill]
  discovery_paths : Array[String]
}

///|
/// Normalise a skill name for lookup: hyphens and underscores are
/// equivalent, lowercase (Ruby ecosystem convention; spec 2026-08-18_20
/// decision 1). Loading stores skills under their canonical frontmatter
/// name, but lookups accept both spellings so a `browser_setup` reference
/// still resolves the on-disk `browser-setup` skill.
pub fn normalize_skill_name(name : String) -> String {
  let lower = name.to_lower()
  let underscored = lower.replace(old="-", new="_")
  underscored
}

///|
/// Create a new empty SkillRegistry.
pub fn SkillRegistry::new() -> SkillRegistry {
  { skills: Map([]), discovery_paths: [] }
}

///|
/// Register a skill in the registry.
///
/// Later registrations override same-named skills (skill_loader.rb
/// semantics: default < global < project priority order).
pub fn SkillRegistry::register(self : SkillRegistry, skill : Skill) -> Unit {
  self.skills[skill.name] = skill
}

///|
/// Get a skill by name (hyphen/underscore spellings equivalent).
pub fn SkillRegistry::get(self : SkillRegistry, name : String) -> Skill? {
  match self.skills.get(name) {
    Some(skill) => Some(skill)
    None => self.skills.get(normalize_skill_name(name))
  }
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
/// Check if a skill with the given name exists (hyphen/underscore
/// spellings equivalent).
pub fn SkillRegistry::has(self : SkillRegistry, name : String) -> Bool {
  self.get(name) is Some(_)
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
  if body.length() == 0 || body.contains("/") || body.contains("\\") {
    return None
  }
  let (name, args) = match body.find(" ") {
    Some(i) => (body[0:i].to_owned(), body[i + 1:].trim().to_owned())
    None => (body, "")
  }
  // Reject path-shaped tokens (spec 2026-08-18_20 decision 5).
  if name.contains("..") || name.contains("/") || name.contains("\\") {
    return None
  }
  match self.get(name) {
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
