///|
/// Agent configuration, loaded from TOML config file and environment variables.
pub(all) struct AgentConfig {
  mut permission_mode : PermissionMode
  mut max_tokens : Int
  mut verbose : Bool
  mut enable_compression : Bool
  mut enable_prompt_caching : Bool
  mut models : Array[ModelConfig]
  mut current_model_id : String?
  mut memory_update_enabled : Bool
  mut skill_evolution : Json?
  mut max_running_agents : Int
  mut max_idle_agents : Int
  mut proxy_url : String
  mut fallback_model : String
  mut compression_threshold : Int
  mut env_source : String
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
    proxy_url: "",
    fallback_model: "",
    compression_threshold: 10000,
    env_source: "toml",
  }
}
