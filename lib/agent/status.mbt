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
pub extend AgentStatus with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend AgentStatus with Compare::{op_lt, op_le, op_ge, compare, op_gt}

///|
pub extend AgentStatus with Eq::{not_equal, equal}

///|
pub extend AgentStatus with ToJson::{to_json}

///|
/// How the agent session was initiated.
pub(all) enum AgentSource {
  Manual
  Cron
  Channel
} derive(Eq, Compare, Debug)

///|
pub extend AgentSource with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend AgentSource with Compare::{op_lt, op_le, op_ge, compare, op_gt}

///|
pub extend AgentSource with Eq::{not_equal, equal}

///|
pub extend AgentSource with ToJson::{to_json}

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
pub impl ToJson for AgentStatus with fn to_json(self) {
  self.to_string_value().to_json()
}

///|
pub impl ToJson for AgentSource with fn to_json(self) {
  self.to_string_value().to_json()
}
