///|
/// A scheduled task
#derive(Eq, Debug, ToJson)
pub(all) struct Schedule {
  name : String
  task_name : String
  cron : CronExpression
  mut enabled : Bool
  mut last_run_at : Int32?
  mut next_run_at : Int32?
  mut run_count : Int32
}

///|
pub extend Schedule with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend Schedule with Eq::{not_equal, equal}

///|
pub extend Schedule with ToJson::{to_json}

///|
/// Scheduler configuration
#derive(Eq, Debug, ToJson)
pub(all) struct SchedulerConfig {
  schedules : Array[Schedule]
  tasks_dir : String
  config_path : String
}

///|
pub extend SchedulerConfig with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend SchedulerConfig with Eq::{not_equal, equal}

///|
pub extend SchedulerConfig with ToJson::{to_json}

///|
/// Scheduler state
#derive(Eq, Debug, ToJson)
pub(all) enum SchedulerState {
  Stopped
  Running
  Paused
}

///|
pub extend SchedulerState with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend SchedulerState with Eq::{not_equal, equal}

///|
pub extend SchedulerState with ToJson::{to_json}

///|
/// Scheduler error
///
/// Plain `data`-style `enum`, not `suberror`: this package carries failures as
/// ordinary `Result[T, SchedulerError]` values that callers match on, and never
/// `raise`/`catch` them. Keeping it out of the native `Error` hierarchy avoids
/// the `result_error_return` (E0078) warning on every `Result` signature.
#derive(ToJson, Debug)
pub(all) enum SchedulerError {
  SchedulerError(String)
}

///|
pub extend SchedulerError with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend SchedulerError with ToJson::{to_json}
