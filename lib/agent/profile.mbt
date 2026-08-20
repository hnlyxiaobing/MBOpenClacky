///| Agent Profile loading and resolution.
///
/// Aligned with Ruby agent_profile.rb (spec 2026-08-18_20 decision 7):
///   - Lookup order: user dir `~/.mbopenclacky/agents/<name>/` → bundled
///     built-in `assets/agents/<name>/`.
///   - Missing profile raises an explicit error (no silent default).
///   - SOUL.md / USER.md read from the `agents/` level (shared across all
///     agents) with bundled `assets/agents/SOUL.md` / `USER.md` fallback.
///   - base.md read from `assets/prompts/base.md` (bundled, shared).

///|
/// Maximum characters loaded from each agent memory file (SOUL.md / USER.md),
/// matching Ruby SystemPromptBuilder::MAX_MEMORY_FILE_CHARS.
const MAX_MEMORY_FILE_CHARS : Int = 1000

///|
/// Load agent profile by name.
///
/// Search order: `~/.mbopenclacky/agents/<name>/` (user override) →
/// `assets/agents/<name>/` (bundled built-in). When neither exists an
/// explicit error is raised (Ruby `Agent profile '<name>' not found`).
pub fn AgentProfile::load_for_name(
  name : String,
) -> AgentProfile raise @errors.AgentError {
  match resolve_profile_dir(name) {
    Some(dir) => load_profile_from_dir(name, dir)
    None =>
      raise @errors.AgentError(
        "Agent profile '\{name}' not found. Looked in ~/.mbopenclacky/agents/\{name} and assets/agents/\{name}.",
      )
  }
}

///|
/// Load a profile from a resolved directory: parse profile.yml (falling
/// back to config.toml), load system_prompt.md, and resolve SOUL/USER/base
/// from the shared agents/prompts locations.
fn load_profile_from_dir(
  name : String,
  dir : String,
) -> AgentProfile raise @errors.AgentError {
  let config = parse_profile_config(name, dir)
  let system_prompt = load_agent_file(dir + "/system_prompt.md")
  let soul_content = load_shared_agent_file("SOUL.md")
  let user_content = load_shared_agent_file("USER.md")
  let base_prompt = load_file_content("assets/prompts/base.md")
  { config, system_prompt, soul_content, user_content, base_prompt }
}

///|
/// Parse the profile configuration from a directory.
///
/// Reads `profile.yml` when present (Ruby agent_profile.rb contract),
/// otherwise falls back to the MB-native `config.toml`. Both are parsed
/// with the shared YAML/TOML key-value subset. Missing/empty metadata
/// defaults sensibly.
fn parse_profile_config(name : String, dir : String) -> ProfileConfig {
  let profile_yml = dir + "/profile.yml"
  let fields : Map[String, String] = if @fs.path_exists(profile_yml) {
    let content = @fs.read_file_to_string(profile_yml) catch { _ => "" }
    let (fm, _body) = @skill.parse_frontmatter(content)
    fm
  } else {
    let config_toml = dir + "/config.toml"
    if @fs.path_exists(config_toml) {
      let content = @fs.read_file_to_string(config_toml) catch { _ => "" }
      parse_toml_kv(content)
    } else {
      Map([])
    }
  }
  let description = fields.get("description")
  let whitelist = match fields.get("skills") {
    Some(v) =>
      match @skill.parse_string_list(v) {
        Some(items) => Some(items)
        None => None
      }
    None => None
  }
  let default_model = fields.get("default_model")
  let system_prompt_path = fields.get("system_prompt_path")
  {
    name,
    description,
    skill_whitelist: whitelist,
    default_model,
    system_prompt_path,
  }
}

///|
/// Parse a minimal TOML `key = "value"` subset into a string map.
fn parse_toml_kv(content : String) -> Map[String, String] {
  let fields : Map[String, String] = Map([])
  for line in content.split("\n") {
    let trimmed = line.trim().to_owned()
    if trimmed.is_empty() || trimmed.has_prefix("#") || trimmed.has_prefix("[") {
      continue
    }
    match trimmed.find("=") {
      Some(eq) => {
        let key = trimmed[0:eq].trim().to_owned()
        let raw_val = trimmed[eq + 1:].trim().to_owned()
        let val = if raw_val.has_prefix("\"") &&
          raw_val.has_suffix("\"") &&
          raw_val.length() >= 2 {
          raw_val[1:raw_val.length() - 1].to_owned()
        } else {
          raw_val
        }
        if !key.is_empty() {
          fields[key] = val
        }
      }
      None => ()
    }
  }
  fields
}

///|
/// Get the combined system prompt section from profile.
///
/// Order (Ruby system_prompt_builder.rb): base.md → SOUL.md → USER.md →
/// agent-specific system_prompt.md, with SOUL/USER truncated to
/// MAX_MEMORY_FILE_CHARS.
pub fn AgentProfile::build_system_prompt_section(self : AgentProfile) -> String {
  let mut buf = ""
  match self.base_prompt {
    Some(bp) => buf = buf + bp.trim().to_owned() + "\n\n"
    None => ()
  }
  match self.soul_content {
    Some(soul) => buf = buf + truncate_memory(soul) + "\n\n"
    None => ()
  }
  match self.user_content {
    Some(user) => buf = buf + truncate_memory(user) + "\n\n"
    None => ()
  }
  match self.system_prompt {
    Some(sp) => buf = buf + sp.trim().to_owned()
    None => ()
  }
  buf
}

///|
/// Truncate a memory file to MAX_MEMORY_FILE_CHARS, appending a marker
/// (Ruby SystemPromptBuilder#truncate).
pub fn truncate_memory(text : String) -> String {
  if text.length() <= MAX_MEMORY_FILE_CHARS {
    text.trim().to_owned()
  } else {
    text[0:MAX_MEMORY_FILE_CHARS].to_owned() + "\n... [truncated]"
  }
}

///|
/// Default profile (used only when a profile genuinely cannot be resolved
/// by name; callers should prefer load_for_name which raises).
pub fn AgentProfile::default_profile() -> AgentProfile {
  let config : ProfileConfig = {
    name: "default",
    description: Some("Default agent profile"),
    skill_whitelist: None,
    default_model: None,
    system_prompt_path: None,
  }
  {
    config,
    system_prompt: None,
    soul_content: None,
    user_content: None,
    base_prompt: None,
  }
}

///|
/// Check if a skill is whitelisted for this profile.
pub fn AgentProfile::is_skill_allowed(
  self : AgentProfile,
  skill_name : String,
) -> Bool {
  match self.config.skill_whitelist {
    None => true
    Some(whitelist) => {
      for name in whitelist {
        if name == skill_name {
          return true
        }
      }
      false
    }
  }
}

///|
/// Resolve a profile directory: user override first, then bundled built-in.
fn resolve_profile_dir(name : String) -> String? {
  match @utils.config_dir() {
    Some(dir) => {
      let user_path = @path.Path::join(dir, @path.Path("agents/" + name)).to_string()
      if @fs.path_exists(user_path) {
        return Some(user_path)
      }
      let builtin_path = "assets/agents/" + name
      if @fs.path_exists(builtin_path) {
        return Some(builtin_path)
      }
      None
    }
    None => {
      let builtin_path = "assets/agents/" + name
      if @fs.path_exists(builtin_path) {
        Some(builtin_path)
      } else {
        None
      }
    }
  }
}

///|
/// Load file content safely, returning None when missing or unreadable.
fn load_file_content(path : String) -> String? {
  if @fs.path_exists(path) {
    let content = @fs.read_file_to_string(path) catch { _ => return None }
    Some(content)
  } else {
    None
  }
}

///|
/// Load an agent-specific file (system_prompt.md), returning None when
/// missing or empty.
fn load_agent_file(path : String) -> String? {
  match load_file_content(path) {
    Some(content) =>
      if content.trim().is_empty() {
        None
      } else {
        Some(content)
      }
    None => None
  }
}

///|
/// Load a shared agent-level file (SOUL.md / USER.md): user override at
/// `~/.mbopenclacky/agents/<file>` first, then bundled `assets/agents/<file>`.
fn load_shared_agent_file(filename : String) -> String? {
  match @utils.config_dir() {
    Some(dir) => {
      let user_path = @path.Path::join(dir, @path.Path("agents/" + filename)).to_string()
      match load_agent_file(user_path) {
        Some(content) => Some(content)
        None => load_agent_file("assets/agents/" + filename)
      }
    }
    None => load_agent_file("assets/agents/" + filename)
  }
}
