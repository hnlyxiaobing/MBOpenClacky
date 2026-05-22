///|
/// Agent configuration, loaded from TOML config file and environment variables.
pub(all) struct AgentConfig {
  permission_mode : PermissionMode
  max_tokens : Int
  verbose : Bool
  enable_compression : Bool
  enable_prompt_caching : Bool
  models : Array[ModelConfig]
  current_model_id : String?
  memory_update_enabled : Bool
  skill_evolution : Json?
  max_running_agents : Int
  max_idle_agents : Int
} derive(Eq, Debug, ToJson)

///|
/// Create an AgentConfig with sensible defaults.
pub fn AgentConfig::default() -> AgentConfig {
  {
    permission_mode: ConfirmSafes,
    max_tokens: 16384,
    verbose: false,
    enable_compression: true,
    enable_prompt_caching: true,
    models: [],
    current_model_id: None,
    memory_update_enabled: false,
    skill_evolution: None,
    max_running_agents: 10,
    max_idle_agents: 10,
  }
}
