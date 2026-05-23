///|
/// Configuration for spawning a sub-agent.
pub(all) struct SubAgentConfig {
  name : String
  model : String?
  allowed_tools : Array[String]?
  system_prompt_override : String?
  max_iterations : Int
} derive(Eq, Debug)

///|
impl ToJson for SubAgentConfig with fn to_json(self) {
  Json::object({
    "name": self.name.to_json(),
    "model": self.model.to_json(),
    "allowed_tools": self.allowed_tools.to_json(),
    "system_prompt_override": self.system_prompt_override.to_json(),
    "max_iterations": self.max_iterations.to_json(),
  })
}

///|
/// Lifecycle status for a spawned sub-agent.
pub(all) enum SubAgentStatus {
  Pending
  Running
  Completed
  Failed
} derive(Eq, Compare, Show, Debug)

///|
pub fn SubAgentStatus::to_string_value(self : SubAgentStatus) -> String {
  match self {
    Pending => "pending"
    Running => "running"
    Completed => "completed"
    Failed => "failed"
  }
}

///|
impl ToJson for SubAgentStatus with fn to_json(self) {
  self.to_string_value().to_json()
}

///|
/// A handle to a running or completed sub-agent.
pub(all) struct SubAgentHandle {
  id : String
  config : SubAgentConfig
  mut status : SubAgentStatus
  mut result : String?
  mut error : String?
  mut iterations : Int
} derive(Eq, Debug)

///|
pub fn SubAgentHandle::new(
  id : String,
  config : SubAgentConfig,
) -> SubAgentHandle {
  { id, config, status: Pending, result: None, error: None, iterations: 0 }
}

///|
/// Transition the handle to Running state.
pub fn SubAgentHandle::mark_running(self : SubAgentHandle) -> Unit {
  self.status = Running
}

///|
/// Transition the handle to Completed state with a result payload.
pub fn SubAgentHandle::mark_completed(
  self : SubAgentHandle,
  result : String,
) -> Unit {
  self.status = Completed
  self.result = Some(result)
}

///|
/// Transition the handle to Failed state with an error message.
pub fn SubAgentHandle::mark_failed(
  self : SubAgentHandle,
  error : String,
) -> Unit {
  self.status = Failed
  self.error = Some(error)
}

///|
/// Return true if the sub-agent has finished (Completed or Failed).
pub fn SubAgentHandle::is_done(self : SubAgentHandle) -> Bool {
  self.status == Completed || self.status == Failed
}
