///| Agent Profile loading and resolution.

///|
/// Load agent profile by name.
/// Search order: ~/.mbopenclacky/agents/<name>/ -> built-in defaults.
pub fn AgentProfile::load_for_name(name : String) -> AgentProfile {
  // Try user directory first
  let profile_dir = resolve_profile_dir(name)
  match profile_dir {
    Some(dir) => {
      // TODO: actual filesystem implementation - parse profile.yml
      let config : ProfileConfig = {
        name,
        description: None,
        skill_whitelist: None,
        default_model: None,
        system_prompt_path: None,
      }
      let system_prompt = load_file_content(dir + "/system_prompt.md")
      let soul_content = load_global_file("SOUL.md")
      let user_content = load_global_file("USER.md")
      let base_prompt = load_global_file("base_prompt.md")
      { config, system_prompt, soul_content, user_content, base_prompt }
    }
    None => AgentProfile::default_profile()
  }
}

///|
/// Get the combined system prompt from profile.
pub fn AgentProfile::build_system_prompt_section(self : AgentProfile) -> String {
  let mut buf = ""
  // Combine: base_prompt + soul + user + profile-specific prompt
  match self.base_prompt {
    Some(bp) => buf = buf + bp + "\n\n"
    None => ()
  }
  match self.soul_content {
    Some(soul) => buf = buf + soul + "\n\n"
    None => ()
  }
  match self.user_content {
    Some(user) => buf = buf + user + "\n\n"
    None => ()
  }
  match self.system_prompt {
    Some(sp) => buf = buf + sp
    None => ()
  }
  buf
}

///|
/// Default profile (when no named profile found).
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
  // If whitelist is None, all skills allowed
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
/// Helper: resolve profile directory path.
fn resolve_profile_dir(name : String) -> String? {
  // Check ~/.mbopenclacky/agents/<name>/
  match @utils.config_dir() {
    Some(dir) => {
      let profile_path = @path.Path::join(dir, @path.Path("agents/" + name)).to_string()
      // TODO: actual filesystem check
      if @fs.path_exists(profile_path) {
        Some(profile_path)
      } else {
        None
      }
    }
    None => None
  }
}

///|
/// Helper: load file content safely.
fn load_file_content(path : String) -> String? {
  // TODO: actual filesystem implementation
  if @fs.path_exists(path) {
    Some(@fs.read_file_to_string(path)) catch {
      _ => None
    }
  } else {
    None
  }
}

///|
/// Helper: load global configuration file from ~/.mbopenclacky/.
fn load_global_file(filename : String) -> String? {
  match @utils.config_dir() {
    Some(dir) => {
      let path = @path.Path::join(dir, @path.Path(filename)).to_string()
      load_file_content(path)
    }
    None => None
  }
}
