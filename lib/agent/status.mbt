///|
/// Current status of an agent session.
pub(all) enum AgentStatus {
  Idle
  Running
  WaitingForInput
  Error
  Completed
} derive(Eq, Compare, Debug)

///|
/// How the agent session was initiated.
pub(all) enum AgentSource {
  Manual
  Cron
  Channel
} derive(Eq, Compare, Debug)

///|
/// Convert AgentStatus to a string for JSON serialization.
pub fn AgentStatus::to_string_value(self : AgentStatus) -> String {
  match self {
    Idle => "idle"
    Running => "running"
    WaitingForInput => "waiting_for_input"
    Error => "error"
    Completed => "completed"
  }
}

///|
/// Convert AgentSource to a string for JSON serialization.
pub fn AgentSource::to_string_value(self : AgentSource) -> String {
  match self {
    Manual => "manual"
    Cron => "cron"
    Channel => "channel"
  }
}

///|
impl ToJson for AgentStatus with to_json(self) {
  self.to_string_value().to_json()
}

///|
impl ToJson for AgentSource with to_json(self) {
  self.to_string_value().to_json()
}
