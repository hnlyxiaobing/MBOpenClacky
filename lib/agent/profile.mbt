///| Agent Profile loading and resolution.
///
/// Aligned with Ruby agent_profile.rb (spec 2026-08-18_20 decision 7):
///   - Lookup order: user dir `~/.mbopenclacky/agents/<name>/` → bundled
///     built-in `assets/agents/<name>/`.
///   - Missing profile raises an explicit error (no silent default).
///   - SOUL.md / USER.md read from the `agents/` level (shared across all
///     agents); a missing/blank file falls back to the built-in
///     DEFAULT_SOUL / DEFAULT_USER constants, never to the bundled assets.
///   - base.md read from `assets/prompts/base.md` (bundled, shared).

///|
/// Maximum characters loaded from each agent memory file (SOUL.md / USER.md),
/// matching Ruby SystemPromptBuilder::MAX_MEMORY_FILE_CHARS.
const MAX_MEMORY_FILE_CHARS : Int32 = 1000

///|
/// Built-in personality used when the user has no `~/.mbopenclacky/agents/SOUL.md`
/// (Ruby AgentProfile::DEFAULT_SOUL).
const DEFAULT_SOUL : String = "You are calm, precise, and helpful. You communicate clearly and concisely.\nYou are honest about uncertainty and ask for clarification when needed.\nYou take initiative but respect the user's preferences and decisions."

///|
/// Built-in user profile used when the user has no
/// `~/.mbopenclacky/agents/USER.md` (Ruby AgentProfile::DEFAULT_USER).
const DEFAULT_USER : String = "(No user profile configured yet. To personalize, create ~/.clacky/agents/USER.md)"

///|
/// Built-in SOUL.md body (Ruby AgentProfile::DEFAULT_SOUL), exposed so the
/// Web profile view shows exactly what the model receives.
pub fn default_soul_md() -> String {
  DEFAULT_SOUL
}

///|
/// Built-in USER.md body (Ruby AgentProfile::DEFAULT_USER).
pub fn default_user_md() -> String {
  DEFAULT_USER
}

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
    None => {
      let builtin = @utils.assets_path("agents/" + name)
      raise @errors.AgentError(
        "Agent profile '\{name}' not found. Looked in ~/.mbopenclacky/agents/\{name} and \{builtin}.",
      )
    }
  }
}

///|
/// Load a profile from a resolved directory: parse profile.yml (falling
/// back to config.toml), load system_prompt.md, and resolve SOUL/USER/base
/// from the shared agents/prompts locations.
fn load_profile_from_dir(name : String, dir : String) -> AgentProfile {
  let config = parse_profile_config(name, dir)
  // Ruby's AgentProfile#system_prompt / #base_prompt both `.strip` the file
  // body (agent_profile.rb: `load_agent_file` → `.strip`; `base_prompt` →
  // `File.read(...).strip`). Without this, a trailing newline in either file
  // adds a spurious blank line at the layer boundary in the assembled prompt
  // (diff-harness 015 req_0001 line 68 / 106).
  let system_prompt = strip_opt(load_agent_file(dir + "/system_prompt.md"))
  // User override only — the built-in fallback lives in computed_soul /
  // computed_user_profile so the bundled assets are never injected as a
  // personality the user never wrote (Ruby AgentProfile#soul).
  let soul_content = load_user_agent_override("SOUL.md")
  let user_content = load_user_agent_override("USER.md")
  let base_prompt = strip_opt(
    load_file_content(@utils.assets_path("prompts/base.md")),
  )
  { config, system_prompt, soul_content, user_content, base_prompt, }
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
/// Effective SOUL.md content: user override when present, else the built-in
/// DEFAULT_SOUL, truncated to MAX_MEMORY_FILE_CHARS
/// (Ruby AgentProfile#soul + SystemPromptBuilder#truncate).
pub fn AgentProfile::soul(self : AgentProfile) -> String {
  match self.soul_content {
    Some(content) => truncate_memory(content)
    None => truncate_memory(DEFAULT_SOUL)
  }
}

///|
/// Effective USER.md content: user override when present, else the built-in
/// DEFAULT_USER, truncated to MAX_MEMORY_FILE_CHARS
/// (Ruby AgentProfile#user_profile + SystemPromptBuilder#truncate).
pub fn AgentProfile::user_profile(self : AgentProfile) -> String {
  match self.user_content {
    Some(content) => truncate_memory(content)
    None => truncate_memory(DEFAULT_USER)
  }
}

///|
/// Truncate a memory file to MAX_MEMORY_FILE_CHARS, appending a marker
/// (Ruby SystemPromptBuilder#truncate). The content is stripped first —
/// Ruby's AgentProfile#soul / #user_profile already `.strip` the file body.
pub fn truncate_memory(text : String) -> String {
  let body = text.trim().to_owned()
  if body.length() <= MAX_MEMORY_FILE_CHARS {
    body
  } else {
    body[0:MAX_MEMORY_FILE_CHARS].to_owned() + "\n... [truncated]"
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
      let builtin_path = @utils.assets_path("agents/" + name)
      if @fs.path_exists(builtin_path) {
        return Some(builtin_path)
      }
      None
    }
    None => {
      let builtin_path = @utils.assets_path("agents/" + name)
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
/// Strip leading/trailing whitespace from an optional file body, mirroring
/// Ruby's `File.read(path).strip` in `AgentProfile#system_prompt` and
/// `#base_prompt`. `None` passes through untouched.
fn strip_opt(text : String?) -> String? {
  match text {
    Some(s) => Some(s.trim().to_owned())
    None => None
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
/// Load a user-level agent memory file (`~/.mbopenclacky/agents/<file>`),
/// returning None when absent or blank. Mirrors Ruby's `File.exist? &&
/// !File.zero?` gate — the bundled asset is deliberately NOT a fallback
/// here, because DEFAULT_SOUL / DEFAULT_USER are the built-in defaults.
fn load_user_agent_override(filename : String) -> String? {
  match @utils.config_dir() {
    Some(dir) => {
      let user_path = @path.Path::join(dir, @path.Path("agents/" + filename)).to_string()
      load_agent_file(user_path)
    }
    None => None
  }
}
