///|
/// ServerMaster configuration
pub(all) struct MasterConfig {
  max_workers : Int
  min_workers : Int
  worker_timeout_ms : Int
  auto_restart : Bool
  graceful_shutdown_ms : Int
} derive(Show)

///|
/// ServerMaster running state
pub enum MasterStatus {
  Starting
  Running
  ShuttingDown
  MasterStopped
} derive(Show, Eq)

///|
/// Worker pool statistics
pub(all) struct PoolStats {
  total_workers : Int
  idle_workers : Int
  busy_workers : Int
  failed_workers : Int
  total_tasks_completed : Int
  total_tasks_failed : Int
  uptime_seconds : Int
} derive(Show, Eq, ToJson, FromJson)

///|
/// ServerMaster — manages a pool of Workers
pub(all) struct ServerMaster {
  config : MasterConfig
  mut status : MasterStatus
  mut workers : Array[Worker]
  mut next_worker_id : Int
  mut started_at : String
} derive(Show)

///|
/// Create default MasterConfig
pub fn MasterConfig::default() -> MasterConfig {
  {
    max_workers: 4,
    min_workers: 1,
    worker_timeout_ms: 30000,
    auto_restart: true,
    graceful_shutdown_ms: 15000,
  }
}

///|
/// Create a new ServerMaster with given or default config
pub fn ServerMaster::new(
  config? : MasterConfig = MasterConfig::default(),
) -> ServerMaster {
  {
    config,
    status: MasterStopped,
    workers: [],
    next_worker_id: 1,
    started_at: "",
  }
}

///|
/// Create a new worker with the next available ID
fn ServerMaster::create_worker(self : ServerMaster) -> Worker {
  let wid : WorkerId = {
    id: self.next_worker_id,
    name: "worker-" + self.next_worker_id.to_string(),
  }
  self.next_worker_id += 1
  let config = WorkerConfig::default_with_id(wid)
  Worker::new(config)
}

///|
/// Start the master, creating min_workers
pub fn ServerMaster::start(self : ServerMaster) -> Unit {
  self.status = Starting
  // Create minimum number of workers
  for i = 0; i < self.config.min_workers; i = i + 1 {
    let w = self.create_worker()
    self.workers.push(w)
  }
  self.status = Running
}

///|
/// Stop the master, requesting all workers to stop
pub fn ServerMaster::stop(self : ServerMaster) -> Unit {
  self.status = ShuttingDown
  for w in self.workers {
    w.request_stop()
  }
}

///|
/// Get current master status
pub fn ServerMaster::master_status(self : ServerMaster) -> MasterStatus {
  self.status
}

///|
/// Dispatch a task to an available worker
/// Returns the WorkerId of the assigned worker, or an error if none available
pub fn ServerMaster::dispatch_task(
  self : ServerMaster,
  task_desc : String,
) -> Result[WorkerId, String] {
  // Find an idle worker
  for w in self.workers {
    if w.is_available() {
      w.mark_busy(task_desc)
      return Ok(w.config.id)
    }
  }
  // No idle worker, try to scale up if possible
  if self.workers.length() < self.config.max_workers {
    let w = self.create_worker()
    w.mark_busy(task_desc)
    let wid = w.config.id
    self.workers.push(w)
    return Ok(wid)
  }
  Err("All workers busy and pool is at maximum capacity")
}

///|
/// Scale up: add a new worker to the pool
pub fn ServerMaster::scale_up(self : ServerMaster) -> Result[WorkerId, String] {
  if self.workers.length() >= self.config.max_workers {
    return Err(
      "Cannot scale up: already at max_workers (" +
      self.config.max_workers.to_string() +
      ")",
    )
  }
  let w = self.create_worker()
  let wid = w.config.id
  self.workers.push(w)
  Ok(wid)
}

///|
/// Scale down: remove one idle worker from the pool
pub fn ServerMaster::scale_down(self : ServerMaster) -> Result[Unit, String] {
  if self.workers.length() <= self.config.min_workers {
    return Err(
      "Cannot scale down: already at min_workers (" +
      self.config.min_workers.to_string() +
      ")",
    )
  }
  // Find last idle worker and remove it
  let mut idx = -1
  for i = self.workers.length() - 1; i >= 0; i = i - 1 {
    if self.workers[i].is_available() {
      idx = i
      break
    }
  }
  if idx < 0 {
    return Err("No idle workers to remove")
  }
  self.workers[idx].status = Stopped
  let new_workers : Array[Worker] = []
  for i = 0; i < self.workers.length(); i = i + 1 {
    if i != idx {
      new_workers.push(self.workers[i])
    }
  }
  self.workers = new_workers
  Ok(())
}

///|
/// Health check: detect workers with expired heartbeat or failed status
pub fn ServerMaster::health_check(
  self : ServerMaster,
  current_time : String,
) -> Array[WorkerId] {
  let expired : Array[WorkerId] = []
  for w in self.workers {
    match w.status {
      Failed(_) => expired.push(w.config.id)
      Busy(_) =>
        if w.is_heartbeat_expired(current_time, self.config.worker_timeout_ms) {
          expired.push(w.config.id)
        }
      _ => ()
    }
  }
  expired
}

///|
/// Restart a worker by its ID
pub fn ServerMaster::restart_worker(
  self : ServerMaster,
  worker_id : WorkerId,
) -> Result[Unit, String] {
  for w in self.workers {
    if w.config.id == worker_id {
      w.status = Idle
      w.last_heartbeat = ""
      return Ok(())
    }
  }
  Err("Worker not found: " + worker_id.name)
}

///|
/// Get pool statistics
pub fn ServerMaster::pool_stats(self : ServerMaster) -> PoolStats {
  let mut idle = 0
  let mut busy = 0
  let mut failed = 0
  let mut completed = 0
  let mut task_failed = 0
  for w in self.workers {
    match w.status {
      Idle => idle += 1
      Busy(_) => busy += 1
      Failed(_) => failed += 1
      _ => ()
    }
    completed += w.tasks_completed
    task_failed += w.tasks_failed
  }
  {
    total_workers: self.workers.length(),
    idle_workers: idle,
    busy_workers: busy,
    failed_workers: failed,
    total_tasks_completed: completed,
    total_tasks_failed: task_failed,
    uptime_seconds: 0,
  }
}

///|
/// Get all worker statuses
pub fn ServerMaster::worker_statuses(
  self : ServerMaster,
) -> Array[(WorkerId, WorkerStatus)] {
  let result : Array[(WorkerId, WorkerStatus)] = []
  for w in self.workers {
    result.push((w.config.id, w.status))
  }
  result
}

///|
/// Find a worker by its ID
pub fn ServerMaster::find_worker(
  self : ServerMaster,
  worker_id : WorkerId,
) -> Worker? {
  for w in self.workers {
    if w.config.id == worker_id {
      return Some(w)
    }
  }
  None
}

///|
/// Complete a task on a worker, returning it to idle
pub fn ServerMaster::complete_task(
  self : ServerMaster,
  worker_id : WorkerId,
  success : Bool,
) -> Result[Unit, String] {
  for w in self.workers {
    if w.config.id == worker_id {
      w.task_done(success)
      return Ok(())
    }
  }
  Err("Worker not found: " + worker_id.name)
}
