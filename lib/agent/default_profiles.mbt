///| Default Agent Profile specifications.
///
/// Defines built-in profile specs for coding and general agents,
/// including allowed tools, hooks, and configuration paths.

///|
/// A specification for a built-in agent profile.
/// Unlike AgentProfile (which holds loaded content), ProfileSpec
/// describes the static definition of a profile template.
pub(all) struct ProfileSpec {
  name : String // profile identifier
  display_name : String // human-readable name
  description : String // brief description
  system_prompt_path : String // relative path to system_prompt.md
  config_path : String // relative path to config.toml
  allowed_tools : Array[String] // tools this profile can use
  hooks : Array[String] // lifecycle hooks
  is_default : Bool // whether this is the fallback profile
} derive(Debug, Eq, ToJson, FromJson)

///|
pub extend ProfileSpec with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ProfileSpec with @moonbitlang/core/json.FromJson::{from_json}

///|
pub extend ProfileSpec with Eq::{not_equal, equal}

///|
pub extend ProfileSpec with ToJson::{to_json}

///|
/// Get all built-in profile specifications.
pub fn get_default_profiles() -> Array[ProfileSpec] {
  [coding_profile(), general_profile(), ext_developer_profile()]
}

///|
/// Look up a built-in profile spec by name.
/// Returns None if not found.
pub fn get_profile_spec(name : String) -> ProfileSpec? {
  let profiles = get_default_profiles()
  for profile in profiles {
    if profile.name == name {
      return Some(profile)
    }
  }
  None
}

///|
/// Get the default profile spec (general).
pub fn get_default_profile_spec() -> ProfileSpec {
  general_profile()
}

///|
/// Coding profile specification — optimized for software development.
fn coding_profile() -> ProfileSpec {
  {
    name: "coding",
    display_name: "Coding Assistant",
    description: "Specialized for code writing, debugging, and refactoring",
    system_prompt_path: "assets/agents/coding/system_prompt.md",
    config_path: "assets/agents/coding/config.toml",
    allowed_tools: [
      "FileReader", "Write", "Edit", "Grep", "Glob", "Terminal", "WebSearch", "WebFetch",
      "Browser",
    ],
    hooks: ["on_error_retry", "on_test_fail_analyze"],
    is_default: false,
  }
}

///|
/// General profile specification — versatile assistant for all tasks.
fn general_profile() -> ProfileSpec {
  {
    name: "general",
    display_name: "General Assistant",
    description: "Versatile assistant for all types of tasks",
    system_prompt_path: "assets/agents/general/system_prompt.md",
    config_path: "assets/agents/general/config.toml",
    allowed_tools: [
      "FileReader", "Write", "Edit", "Grep", "Glob", "Terminal", "WebSearch", "WebFetch",
      "Browser", "InvokeSkill", "MemoryTool", "TodoTool",
    ],
    hooks: ["on_idle_suggest", "on_error_explain"],
    is_default: true,
  }
}

///|
/// Ext-developer profile specification - for skill/extension development.
fn ext_developer_profile() -> ProfileSpec {
  {
    name: "ext-developer",
    display_name: "Extension Developer",
    description: "Specialized for creating and publishing skills and extensions",
    system_prompt_path: "assets/agents/ext-developer/system_prompt.md",
    config_path: "assets/agents/ext-developer/config.toml",
    allowed_tools: [
      "FileReader", "Write", "Edit", "Grep", "Glob", "Terminal", "WebSearch", "WebFetch",
    ],
    hooks: ["on_error_retry", "on_test_fail_analyze"],
    is_default: false,
  }
}

///|
/// Validate that a profile spec has all required fields populated.
pub fn validate_profile_spec(profile : ProfileSpec) -> Result[Unit, String] {
  if profile.name == "" {
    return Err("Profile name must not be empty")
  }
  if profile.display_name == "" {
    return Err("Profile display_name must not be empty")
  }
  if profile.system_prompt_path == "" {
    return Err("Profile system_prompt_path must not be empty")
  }
  if profile.config_path == "" {
    return Err("Profile config_path must not be empty")
  }
  if profile.allowed_tools.length() == 0 {
    return Err("Profile must have at least one allowed tool")
  }
  Ok(())
}

///|
/// Check if a given tool is allowed for a profile spec.
pub fn ProfileSpec::is_tool_allowed(
  self : ProfileSpec,
  tool_name : String,
) -> Bool {
  for t in self.allowed_tools {
    if t == tool_name {
      return true
    }
  }
  false
}

///|
/// Check if a given hook is registered for a profile spec.
pub fn ProfileSpec::has_hook(self : ProfileSpec, hook_name : String) -> Bool {
  for h in self.hooks {
    if h == hook_name {
      return true
    }
  }
  false
}

///|
/// Convert a ProfileSpec to the existing ProfileConfig for integration.
pub fn ProfileSpec::to_profile_config(self : ProfileSpec) -> ProfileConfig {
  {
    name: self.name,
    description: Some(self.description),
    skill_whitelist: Some(self.allowed_tools),
    default_model: None,
    system_prompt_path: Some(self.system_prompt_path),
  }
}

///|
/// Resolve a ProfileSpec to a full AgentProfile with loaded content placeholders.
/// Note: actual file loading deferred to runtime (Phase 5+ filesystem).
pub fn ProfileSpec::to_agent_profile(self : ProfileSpec) -> AgentProfile {
  {
    config: self.to_profile_config(),
    system_prompt: None,
    soul_content: None,
    user_content: None,
    base_prompt: None,
  }
}
