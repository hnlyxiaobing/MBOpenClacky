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

// ── YAML Subset Serialization/Deserialization ─────────────────────────────

///|
/// Serialize a single Schedule entry to YAML lines.
fn schedule_to_yml_lines(schedule : Schedule) -> Array[String] {
  let lines : Array[String] = []
  lines.push("- name: " + yml_quote(schedule.name))
  lines.push("  task_name: " + yml_quote(schedule.task_name))
  lines.push("  cron: " + yml_quote(schedule.cron.raw))
  lines.push("  enabled: " + schedule.enabled.to_string())
  match schedule.last_run_at {
    Some(ts) => lines.push("  last_run_at: " + ts.to_string())
    None => ()
  }
  match schedule.next_run_at {
    Some(ts) => lines.push("  next_run_at: " + ts.to_string())
    None => ()
  }
  lines.push("  run_count: " + schedule.run_count.to_string())
  lines
}

///|
/// Serialize the full SchedulerConfig to YAML string.
fn config_to_yml(config : SchedulerConfig) -> String {
  let mut result = "# schedules.yml - managed by MBOpenClacky scheduler\n"
  result = result + "tasks_dir: " + yml_quote(config.tasks_dir) + "\n"
  result = result + "schedules:\n"
  for schedule in config.schedules {
    for line in schedule_to_yml_lines(schedule) {
      result = result + line + "\n"
    }
  }
  result
}

///|
/// Quote and escape a YAML string value (round-trip safe for quotes
/// and backslashes inside task names / cron expressions).
fn yml_quote(s : String) -> String {
  let mut out : String = "\""
  for ch in s.iter() {
    if ch == '"' || ch == '\\' {
      out = out + "\\"
    }
    out = out + ch.to_string()
  }
  out + "\""
}

///|
/// Strip surrounding quotes and unescape from a YAML value.
fn yml_unquote(value : String) -> String {
  let v = value.trim().to_owned()
  if v.length() >= 2 && v[0:1] == "\"" && v[v.length() - 1:] == "\"" {
    let inner = v[1:v.length() - 1].to_owned()
    let chars = inner.to_array()
    let mut out : String = ""
    let mut i = 0
    while i < chars.length() {
      if chars[i] == '\\' &&
        i + 1 < chars.length() &&
        (chars[i + 1] == '"' || chars[i + 1] == '\\') {
        out = out + chars[i + 1].to_string()
        i = i + 2
      } else {
        out = out + chars[i].to_string()
        i = i + 1
      }
    }
    out
  } else {
    v
  }
}

///|
/// Parse a key: value line, returning (key, value) or None.
fn yml_parse_kv(line : String) -> (String, String)? {
  let trimmed = line.trim().to_owned()
  // Skip list markers for the key extraction
  let content = if trimmed.has_prefix("- ") {
    trimmed[2:].to_owned()
  } else {
    trimmed
  }
  match content.find(":") {
    Some(idx) if idx > 0 => {
      let key = content[0:idx].trim().to_owned()
      let value = content[idx + 1:].to_owned()
      Some((key, yml_unquote(value)))
    }
    _ => None
  }
}

///|
/// Parse schedules.yml content into SchedulerConfig.
/// Tolerates missing fields and skips malformed entries.
fn parse_schedules_yml(
  content : String,
  config_path : String,
) -> SchedulerConfig {
  let schedules : Array[Schedule] = []
  let mut tasks_dir = ""
  // Current entry being built
  let mut cur_name : String? = None
  let mut cur_task_name : String? = None
  let mut cur_cron : String? = None
  let mut cur_enabled = true
  let mut cur_last_run : Int? = None
  let mut cur_next_run : Int? = None
  let mut cur_run_count = 0

  ///|
  /// Flush the current entry into schedules array
  let flush_entry = fn() -> Unit {
    match (cur_name, cur_cron) {
      (Some(name), Some(cron_str)) =>
        match CronExpression::parse(cron_str) {
          Ok(cron) => {
            let task = match cur_task_name {
              Some(tn) => tn
              None => name
            }
            schedules.push({
              name,
              task_name: task,
              cron,
              enabled: cur_enabled,
              last_run_at: cur_last_run,
              next_run_at: cur_next_run,
              run_count: cur_run_count,
            })
          }
          Err(_) => () // skip malformed cron entry
        }
      _ => () // skip incomplete entry
    }
  }

  let lines = content.split("\n")
  for line_sv in lines {
    let line = line_sv.to_owned()
    let trimmed = line.trim().to_owned()
    // Skip empty lines and comments
    if trimmed.is_empty() || trimmed.has_prefix("#") {
      ()
    } else if trimmed.has_prefix("- ") {
      // New entry starts - flush previous
      flush_entry()
      // Reset fields
      cur_name = None
      cur_task_name = None
      cur_cron = None
      cur_enabled = true
      cur_last_run = None
      cur_next_run = None
      cur_run_count = 0
      // Parse the first kv of this entry
      match yml_parse_kv(line) {
        Some((key, value)) =>
          if key == "name" {
            cur_name = Some(value)
          } else if key == "task_name" {
            cur_task_name = Some(value)
          } else if key == "cron" {
            cur_cron = Some(value)
          }
        None => ()
      }
    } else {
      match yml_parse_kv(line) {
        Some((key, value)) =>
          if key == "name" {
            cur_name = Some(value)
          } else if key == "task_name" {
            cur_task_name = Some(value)
          } else if key == "cron" {
            cur_cron = Some(value)
          } else if key == "enabled" {
            cur_enabled = value == "true"
          } else if key == "last_run_at" {
            cur_last_run = parse_int(value)
          } else if key == "next_run_at" {
            cur_next_run = parse_int(value)
          } else if key == "run_count" {
            cur_run_count = match parse_int(value) {
              Some(n) => n
              None => 0
            }
          } else if key == "tasks_dir" {
            tasks_dir = value
          }
        // Unknown keys are silently ignored (forward compat)
        None => ()
      }
    }
  }
  // Flush last entry
  flush_entry()
  { schedules, tasks_dir, config_path }
}

// ── Scheduler Lifecycle ───────────────────────────────────────────────────

///|
/// Load scheduler from config file.
/// If the file does not exist, returns an empty scheduler (decision 5: graceful empty start).
pub fn Scheduler::load_from_config(
  config_path : String,
) -> Result[Scheduler, SchedulerError] {
  if !@fs.path_exists(config_path) {
    // File missing: empty start (decision 5)
    let config : SchedulerConfig = { schedules: [], tasks_dir: "", config_path }
    return Ok(Scheduler::new(config))
  }
  let content = @fs.read_file_to_string(config_path) catch {
    _ => return Err(SchedulerError("Failed to read schedules.yml"))
  }
  let config = parse_schedules_yml(content, config_path)
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
/// Validate a task name used to build a file path (rejects path traversal).
fn validate_task_name(name : String) -> Result[Unit, SchedulerError] {
  if name.is_empty() {
    return Err(SchedulerError("Task name must not be empty"))
  }
  if name.contains("/") || name.contains("\\") || name.contains("..") {
    return Err(
      SchedulerError("Task name must not contain '/', '\\', or '..': " + name),
    )
  }
  Ok(())
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
  // Write-through: surface persistence failure to the caller instead of
  // silently claiming success (the schedule would be lost on restart).
  match self.save_config() {
    Ok(_) => Ok(())
    Err(e) => Err(e)
  }
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
  // Write-through: surface persistence failure to the caller.
  match self.save_config() {
    Ok(_) => Ok(())
    Err(e) => Err(e)
  }
}

///|
/// Update a schedule
pub fn Scheduler::update_schedule(
  self : Scheduler,
  name : String,
  cron_expr : String?,
  enabled : Bool?,
) -> Result[Unit, SchedulerError] {
  let mut found_idx : Int = -1
  let mut i = 0
  while i < self.config.schedules.length() {
    if self.config.schedules[i].name == name {
      found_idx = i
    }
    i = i + 1
  }
  if found_idx < 0 {
    return Err(SchedulerError("Schedule not found: " + name))
  }
  let old = self.config.schedules[found_idx]
  // Parse the new cron expression BEFORE applying any mutation, so an
  // invalid expression cannot leave a half-applied update in memory.
  let new_cron : CronExpression? = match cron_expr {
    Some(expr) =>
      match CronExpression::parse(expr) {
        Ok(c) => Some(c)
        Err(e) => return Err(SchedulerError("Invalid cron expression: " + e))
      }
    None => None
  }
  let updated : Schedule = {
    name: old.name,
    task_name: old.task_name,
    cron: match new_cron {
      Some(c) => c
      None => old.cron
    },
    enabled: match enabled {
      Some(e) => e
      None => old.enabled
    },
    last_run_at: old.last_run_at,
    next_run_at: old.next_run_at,
    run_count: old.run_count,
  }
  self.config.schedules[found_idx] = updated
  // Write-through: surface persistence failure to the caller.
  match self.save_config() {
    Ok(_) => Ok(())
    Err(e) => Err(e)
  }
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
      schedule.last_run_at = Some(@utils.now_seconds())
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
  // Reject path-traversal names before they reach the filesystem.
  match validate_task_name(name) {
    Ok(_) => ()
    Err(e) => return Err(e)
  }
  // Write task file to tasks_dir (write-through, decision 4)
  let task_path = self.config.tasks_dir + "/" + name + ".md"
  @utils.ensure_dir(self.config.tasks_dir)
  @fs.write_string_to_file(task_path, content) catch {
    _ => return Err(SchedulerError("Failed to write task file: " + task_path))
  }
  // Add schedule (persists schedules.yml; errors propagate)
  self.add_schedule(name, name, cron_expr, true)
}

///|
/// Delete a cron task (remove schedule + delete task file)
pub fn Scheduler::delete_cron_task(
  self : Scheduler,
  name : String,
) -> Result[Unit, SchedulerError] {
  // Reject path-traversal names before they reach the filesystem.
  match validate_task_name(name) {
    Ok(_) => ()
    Err(e) => return Err(e)
  }
  // Remove schedule (write-through save happens inside)
  let _ = self.remove_schedule(name)
  // Delete task file from disk
  let task_path = self.config.tasks_dir + "/" + name + ".md"
  if @fs.path_exists(task_path) {
    @fs.remove_file(task_path) catch {
      _ => () // best-effort removal; schedule already removed
    }
  }
  Ok(())
}

///|
/// Save config to file (write-through, decision 4).
/// An empty config_path means an in-memory scheduler (e.g. the web layer
/// persists through its own JSON state file): nothing to write, Ok.
/// Uses atomic write pattern: write to temp then rename is not available,
/// so we do direct write (acceptable for low-frequency operations).
fn Scheduler::save_config(self : Scheduler) -> Result[Unit, SchedulerError] {
  if self.config.config_path.is_empty() {
    return Ok(())
  }
  let yml_content = config_to_yml(self.config)
  @fs.write_string_to_file(self.config.config_path, yml_content) catch {
    _ => return Err(SchedulerError("Failed to save schedules.yml"))
  }
  Ok(())
}
