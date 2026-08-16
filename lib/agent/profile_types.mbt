///| Types for the Agent Profile feature.

///|
/// Agent profile configuration loaded from profile.yml.
pub(all) struct ProfileConfig {
  name : String
  description : String?
  skill_whitelist : Array[String]?
  default_model : String?
  system_prompt_path : String? // path to system_prompt.md
} derive(Eq, Debug, ToJson)

///|
pub extend ProfileConfig with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ProfileConfig with Eq::{not_equal, equal}

///|
pub extend ProfileConfig with ToJson::{to_json}

///|
/// Loaded agent profile with resolved content.
pub(all) struct AgentProfile {
  config : ProfileConfig
  system_prompt : String? // content of system_prompt.md
  soul_content : String? // content of SOUL.md
  user_content : String? // content of USER.md
  base_prompt : String? // content of base_prompt.md
} derive(Eq, Debug)

///|
pub extend AgentProfile with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend AgentProfile with Eq::{not_equal, equal}
