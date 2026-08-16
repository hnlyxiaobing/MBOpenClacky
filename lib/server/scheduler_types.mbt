///|
/// A scheduled task
pub(all) struct Schedule {
  name : String
  task_name : String
  cron : CronExpression
  mut enabled : Bool
  mut last_run_at : Int?
  mut next_run_at : Int?
  mut run_count : Int
} derive(Eq, Debug, ToJson)

///|
pub extend Schedule with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend Schedule with Eq::{not_equal, equal}

///|
pub extend Schedule with ToJson::{to_json}

///|
/// Scheduler configuration
pub(all) struct SchedulerConfig {
  schedules : Array[Schedule]
  tasks_dir : String
  config_path : String
} derive(Eq, Debug, ToJson)

///|
pub extend SchedulerConfig with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend SchedulerConfig with Eq::{not_equal, equal}

///|
pub extend SchedulerConfig with ToJson::{to_json}

///|
/// Scheduler state
pub(all) enum SchedulerState {
  Stopped
  Running
  Paused
} derive(Eq, Debug, ToJson)

///|
pub extend SchedulerState with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend SchedulerState with Eq::{not_equal, equal}

///|
pub extend SchedulerState with ToJson::{to_json}

///|
/// Scheduler error
pub(all) suberror SchedulerError {
  SchedulerError(String)
} derive(ToJson, Debug)

///|
pub extend SchedulerError with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend SchedulerError with ToJson::{to_json}
