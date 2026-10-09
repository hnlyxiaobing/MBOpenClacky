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
  // `replace_all`: a name may carry several hyphens (`cron-task-creator`);
  // `String::replace` only rewrites the first occurrence, which would leave
  // the underscore spelling unresolvable.
  let underscored = lower.replace_all(old="-", new="_")
  underscored
}

///|
/// Create a new empty SkillRegistry.
pub fn SkillRegistry::new() -> SkillRegistry {
  { skills: Map([]), discovery_paths: [], }
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
///
/// BUG-0074 回归：注册键是 frontmatter 里的原始名字（`cron-task-creator`），
/// 只把**查询串**归一化不足以让下划线写法命中，因此先精确查，再按归一化键
/// 线性扫描（技能数量级很小）。
pub fn SkillRegistry::get(self : SkillRegistry, name : String) -> Skill? {
  match self.skills.get(name) {
    Some(skill) => Some(skill)
    None => {
      let target = normalize_skill_name(name)
      for key, skill in self.skills {
        if normalize_skill_name(key) == target {
          return Some(skill)
        }
      }
      None
    }
  }
}

///|
/// List all skills that are user-invocable for the given agent profile
/// (Ruby `user_invocable_skills(profile)`, skill_manager.rb:210 —— 有 profile
/// 时按 `agent:` 作用域过滤；profile_name 传空串表示不过滤).
pub fn SkillRegistry::list_user_invocable(
  self : SkillRegistry,
  profile_name : String,
) -> Array[Skill] {
  let result : Array[Skill] = []
  for _, skill in self.skills {
    if skill.user_invocable && skill.is_allowed_for_profile(profile_name) {
      result.push(skill)
    }
  }
  result
}

///|
/// Ruby `Skill#agents_scope` + `Skill#allowed_for_agent?`：
/// frontmatter 的 `agent:` 字段默认是 `all`（字段缺失，或 YAML 空值解析为空串，
/// 两种都算 all）；写明具体 profile 名时，只有这些 profile 能看到该技能。
/// 列表写法同时兼容 `agent: [a, b]`（MB 的 frontmatter 解析是扁平 Key-Value，
/// Ruby 走真 YAML，这里等价兼容）与逗号/空格分隔的标量。
/// profile_name 传空串时不过滤（Ruby 里 `user_invocable_skills(nil)` 的语义）。
pub fn Skill::is_allowed_for_profile(self : Skill, profile_name : String) -> Bool {
  let raw = match self.agent_type {
    None => return true
    Some(t) => t
  }
  let scope = raw.replace_all(old="[", new="").replace_all(old="]", new="").trim()
  if scope.length() == 0 {
    // YAML 里 `agent:` 空值 → Ruby 解析为 nil → agents_scope = ["all"]
    return true
  }
  if profile_name.length() == 0 {
    return true
  }
  for token in scope_tokens(scope.to_owned()) {
    if token == "all" || token == profile_name {
      return true
    }
  }
  false
}

///|
/// 把 `agent:` 作用域串切成 token（逗号或空白分隔，忽略空片段）。
fn scope_tokens(scope : String) -> Array[String] {
  let out : Array[String] = []
  for chunk in scope.split(",") {
    for token in chunk.split(" ") {
      for piece in token.split("\t") {
        let t = piece.trim()
        if t.length() > 0 {
          out.push(t.to_owned())
        }
      }
    }
  }
  out
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
/// Remove a skill by name (hyphen/underscore spellings equivalent).
pub fn SkillRegistry::remove(self : SkillRegistry, name : String) -> Bool {
  match self.get(name) {
    Some(skill) =>
      if self.skills.contains(skill.name) {
        self.skills.remove(skill.name)
        true
      } else {
        false
      }
    None => false
  }
}
