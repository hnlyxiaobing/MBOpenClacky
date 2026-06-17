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
/// Loaded agent profile with resolved content.
pub(all) struct AgentProfile {
  config : ProfileConfig
  system_prompt : String? // content of system_prompt.md
  soul_content : String? // content of SOUL.md
  user_content : String? // content of USER.md
  base_prompt : String? // content of base_prompt.md
} derive(Eq, Debug)
