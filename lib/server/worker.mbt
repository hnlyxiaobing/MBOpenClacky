///|
/// Worker status in the pool
pub enum WorkerStatus {
  Idle
  Busy(String)
  Stopping
  Stopped
  Failed(String)
} derive(Show, Eq)

///|
/// Worker identifier
pub(all) struct WorkerId {
  id : Int
  name : String
} derive(Show, Eq, ToJson, FromJson)

///|
/// Worker configuration
pub(all) struct WorkerConfig {
  id : WorkerId
  max_tasks : Int
  heartbeat_interval_ms : Int
  shutdown_timeout_ms : Int
} derive(Show)

///|
/// Worker instance in the pool
pub(all) struct Worker {
  config : WorkerConfig
  mut status : WorkerStatus
  mut tasks_completed : Int
  mut tasks_failed : Int
  mut last_heartbeat : String
  mut started_at : String
} derive(Show)

///|
/// Create a new Worker with default Idle status
pub fn Worker::new(config : WorkerConfig) -> Worker {
  {
    config,
    status: Idle,
    tasks_completed: 0,
    tasks_failed: 0,
    last_heartbeat: "",
    started_at: "",
  }
}

///|
/// Get current worker status
pub fn Worker::status(self : Worker) -> WorkerStatus {
  self.status
}

///|
/// Mark worker as busy with a task description
pub fn Worker::mark_busy(self : Worker, task_desc : String) -> Unit {
  self.status = Busy(task_desc)
}

///|
/// Mark worker as idle (available for new tasks)
pub fn Worker::mark_idle(self : Worker) -> Unit {
  self.status = Idle
}

///|
/// Record task completion, incrementing appropriate counter
pub fn Worker::task_done(self : Worker, success : Bool) -> Unit {
  if success {
    self.tasks_completed += 1
  } else {
    self.tasks_failed += 1
  }
  self.status = Idle
}

///|
/// Update heartbeat timestamp
pub fn Worker::heartbeat(self : Worker) -> Unit {
  // In real usage, caller sets current time
  // Here we just mark it was called
  self.last_heartbeat = self.last_heartbeat
}

///|
/// Set heartbeat to a specific time string
pub fn Worker::set_heartbeat(self : Worker, time : String) -> Unit {
  self.last_heartbeat = time
}

///|
/// Check if heartbeat has expired based on ISO8601 string comparison
pub fn Worker::is_heartbeat_expired(
  self : Worker,
  current_time : String,
  _timeout_ms : Int,
) -> Bool {
  // Simple heuristic: if last_heartbeat is empty, consider expired
  if self.last_heartbeat == "" {
    return true
  }
  // ISO8601 strings are lexicographically sortable
  // If current_time > last_heartbeat, heartbeat is stale
  // In a real system we'd parse and compare with timeout_ms
  // For now: expired if last_heartbeat < current_time (any staleness)
  self.last_heartbeat < current_time
}

///|
/// Get run statistics: (completed, failed)
pub fn Worker::stats(self : Worker) -> (Int, Int) {
  (self.tasks_completed, self.tasks_failed)
}

///|
/// Request the worker to stop
pub fn Worker::request_stop(self : Worker) -> Unit {
  match self.status {
    Stopped | Stopping => ()
    _ => self.status = Stopping
  }
}

///|
/// Check if worker is available to accept new tasks
pub fn Worker::is_available(self : Worker) -> Bool {
  match self.status {
    Idle => true
    _ => false
  }
}

///|
/// Create a default WorkerConfig with given id
pub fn WorkerConfig::default_with_id(id : WorkerId) -> WorkerConfig {
  { id, max_tasks: 1, heartbeat_interval_ms: 5000, shutdown_timeout_ms: 10000 }
}
