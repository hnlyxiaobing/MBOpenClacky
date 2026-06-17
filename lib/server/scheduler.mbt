///|
/// Scheduler check interval in seconds
let scheduler_check_interval : Int = 60

///|
/// Cron-based task scheduler
pub(all) struct Scheduler {
  config : SchedulerConfig
  mut state : SchedulerState
  mut last_check_at : Int?
}

///|
/// Create a new Scheduler
pub fn Scheduler::new(config : SchedulerConfig) -> Scheduler {
  { config, state: Stopped, last_check_at: None }
}

///|
/// Load scheduler from config file
pub fn Scheduler::load_from_config(
  config_path : String,
) -> Result[Scheduler, SchedulerError] {
  // TODO: FFI - read and parse schedules.yml
  let config : SchedulerConfig = { schedules: [], tasks_dir: "", config_path }
  let _ = scheduler_check_interval
  Ok(Scheduler::new(config))
}

///|
/// Start the scheduler
pub fn Scheduler::start(self : Scheduler) -> Result[Unit, SchedulerError] {
  match self.state {
    Running => Err(SchedulerError("Scheduler is already running"))
    _ => {
      self.state = Running
      Ok(())
    }
  }
}

///|
/// Stop the scheduler
pub fn Scheduler::stop(self : Scheduler) -> Unit {
  self.state = Stopped
}

///|
/// Add a new schedule
pub fn Scheduler::add_schedule(
  self : Scheduler,
  name : String,
  task_name : String,
  cron_expr : String,
  enabled : Bool,
) -> Result[Unit, SchedulerError] {
  // Check for duplicate name
  for schedule in self.config.schedules {
    if schedule.name == name {
      return Err(SchedulerError("Schedule already exists: " + name))
    }
  }
  // Parse cron expression
  let cron = match CronExpression::parse(cron_expr) {
    Ok(c) => c
    Err(e) => return Err(SchedulerError("Invalid cron expression: " + e))
  }
  let schedule : Schedule = {
    name,
    task_name,
    cron,
    enabled,
    last_run_at: None,
    next_run_at: None,
    run_count: 0,
  }
  self.config.schedules.push(schedule)
  let _ = self.save_config()
  Ok(())
}

///|
/// Remove a schedule by name
pub fn Scheduler::remove_schedule(
  self : Scheduler,
  name : String,
) -> Result[Unit, SchedulerError] {
  let initial_len = self.config.schedules.length()
  let new_schedules : Array[Schedule] = []
  for schedule in self.config.schedules {
    if schedule.name != name {
      new_schedules.push(schedule)
    }
  }
  if new_schedules.length() == initial_len {
    return Err(SchedulerError("Schedule not found: " + name))
  }
  // Replace schedules array content
  self.config.schedules.clear()
  for s in new_schedules {
    self.config.schedules.push(s)
  }
  let _ = self.save_config()
  Ok(())
}

///|
/// Update a schedule
pub fn Scheduler::update_schedule(
  self : Scheduler,
  name : String,
  cron_expr : String?,
  enabled : Bool?,
) -> Result[Unit, SchedulerError] {
  for schedule in self.config.schedules {
    if schedule.name == name {
      match enabled {
        Some(e) => schedule.enabled = e
        None => ()
      }
      match cron_expr {
        Some(_expr) =>
          // TODO: update cron field - would need mutable cron
          ()
        None => ()
      }
      let _ = self.save_config()
      return Ok(())
    }
  }
  Err(SchedulerError("Schedule not found: " + name))
}

///|
/// List all schedules
pub fn Scheduler::list_schedules(self : Scheduler) -> Array[Schedule] {
  self.config.schedules
}

///|
/// Check and execute due tasks
pub fn Scheduler::tick(
  self : Scheduler,
  current_minute : Int,
  current_hour : Int,
  current_day : Int,
  current_month : Int,
  current_weekday : Int,
) -> Array[String] {
  let due_tasks : Array[String] = []
  match self.state {
    Running => ()
    _ => return due_tasks
  }
  for schedule in self.config.schedules {
    if schedule.enabled &&
      schedule.cron.matches(
        current_minute, current_hour, current_day, current_month, current_weekday,
      ) {
      due_tasks.push(schedule.task_name)
      schedule.run_count = schedule.run_count + 1
      schedule.last_run_at = Some(0) // TODO: actual timestamp
    }
  }
  due_tasks
}

///|
/// Get schedule by name
pub fn Scheduler::get_schedule(self : Scheduler, name : String) -> Schedule? {
  for schedule in self.config.schedules {
    if schedule.name == name {
      return Some(schedule)
    }
  }
  None
}

///|
/// Create a cron task (write task file + add schedule)
pub fn Scheduler::create_cron_task(
  self : Scheduler,
  name : String,
  content : String,
  cron_expr : String,
) -> Result[Unit, SchedulerError] {
  // TODO: FFI - write task file to tasks_dir
  let _task_path = self.config.tasks_dir + "/" + name + ".md"
  let _ = content
  // Add schedule
  self.add_schedule(name, name, cron_expr, true)
}

///|
/// Delete a cron task (remove schedule + delete task file)
pub fn Scheduler::delete_cron_task(
  self : Scheduler,
  name : String,
) -> Result[Unit, SchedulerError] {
  // Remove schedule
  let _ = self.remove_schedule(name)
  // TODO: FFI - delete task file
  let _task_path = self.config.tasks_dir + "/" + name + ".md"
  Ok(())
}

///|
/// Save config to file
fn Scheduler::save_config(self : Scheduler) -> Result[Unit, SchedulerError] {
  // TODO: FFI - serialize and write config to self.config.config_path
  let _ = self.config.config_path
  Ok(())
}
