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
/// Scheduler configuration
pub(all) struct SchedulerConfig {
  schedules : Array[Schedule]
  tasks_dir : String
  config_path : String
} derive(Eq, Debug, ToJson)

///|
/// Scheduler state
pub(all) enum SchedulerState {
  Stopped
  Running
  Paused
} derive(Eq, Debug, ToJson)

///|
/// Scheduler error
pub(all) suberror SchedulerError {
  SchedulerError(String)
} derive(ToJson, Debug)
