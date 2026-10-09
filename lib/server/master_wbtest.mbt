///|
test "MasterConfig default values" {
  let config = MasterConfig::default()
  @debug.assert_eq(config.max_workers, 4)
  @debug.assert_eq(config.min_workers, 1)
  @debug.assert_eq(config.worker_timeout_ms, 30000)
  @debug.assert_eq(config.auto_restart, true)
  @debug.assert_eq(config.graceful_shutdown_ms, 15000)
}

///|
test "ServerMaster new creates empty pool" {
  let master = ServerMaster::new()
  @debug.assert_eq(master.workers.length(), 0)
  @debug.assert_eq(master.status, MasterStopped)
  @debug.assert_eq(master.next_worker_id, 1)
}

///|
test "ServerMaster start creates min workers" {
  let master = ServerMaster::new()
  master.start()
  @debug.assert_eq(master.status, Running)
  @debug.assert_eq(master.workers.length(), 1) // min_workers = 1
}

///|
test "dispatch_task assigns to idle worker" {
  let master = ServerMaster::new()
  master.start()
  let result = master.dispatch_task("process request")
  assert_true(result is Ok(_))
  let wid = result.unwrap()
  @debug.assert_eq(wid.id, 1)
  // Worker should now be busy
  let w = master.find_worker(wid)
  assert_true(w is Some(_))
  @debug.assert_eq(w.unwrap().status, Busy("process request"))
}

///|
test "dispatch_task scales up when needed" {
  let config : MasterConfig = {
    max_workers: 3,
    min_workers: 1,
    worker_timeout_ms: 30000,
    auto_restart: true,
    graceful_shutdown_ms: 15000,
  }
  let master = ServerMaster::new(config~)
  master.start()
  // First task goes to existing worker
  let _ = master.dispatch_task("task1")
  // Second task should create a new worker
  let r2 = master.dispatch_task("task2")
  assert_true(r2 is Ok(_))
  @debug.assert_eq(master.workers.length(), 2)
}

///|
test "dispatch_task fails when at max" {
  let config : MasterConfig = {
    max_workers: 1,
    min_workers: 1,
    worker_timeout_ms: 30000,
    auto_restart: true,
    graceful_shutdown_ms: 15000,
  }
  let master = ServerMaster::new(config~)
  master.start()
  let _ = master.dispatch_task("task1")
  let r2 = master.dispatch_task("task2")
  assert_true(r2 is Err(_))
}

///|
test "complete_task returns worker to idle" {
  let master = ServerMaster::new()
  master.start()
  let wid = master.dispatch_task("do work").unwrap()
  let _ = master.complete_task(wid, true)
  let w = master.find_worker(wid).unwrap()
  @debug.assert_eq(w.status, Idle)
  @debug.assert_eq(w.tasks_completed, 1)
}

///|
test "scale_up adds worker" {
  let master = ServerMaster::new()
  master.start()
  @debug.assert_eq(master.workers.length(), 1)
  let result = master.scale_up()
  assert_true(result is Ok(_))
  @debug.assert_eq(master.workers.length(), 2)
}

///|
test "scale_down removes idle worker" {
  let config : MasterConfig = {
    max_workers: 4,
    min_workers: 1,
    worker_timeout_ms: 30000,
    auto_restart: true,
    graceful_shutdown_ms: 15000,
  }
  let master = ServerMaster::new(config~)
  master.start()
  let _ = master.scale_up()
  @debug.assert_eq(master.workers.length(), 2)
  let result = master.scale_down()
  assert_true(result is Ok(_))
  @debug.assert_eq(master.workers.length(), 1)
}

///|
test "health_check detects expired workers" {
  let master = ServerMaster::new()
  master.start()
  let wid = master.dispatch_task("long task").unwrap()
  let w = master.find_worker(wid).unwrap()
  w.set_heartbeat("2026-06-01T10:00:00Z")
  // Current time is later, so heartbeat is expired
  let expired = master.health_check("2026-06-01T11:00:00Z")
  @debug.assert_eq(expired.length(), 1)
  @debug.assert_eq(expired[0], wid)
}

///|
test "restart_worker replaces failed" {
  let master = ServerMaster::new()
  master.start()
  let wid = master.dispatch_task("failing task").unwrap()
  let w = master.find_worker(wid).unwrap()
  w.status = Failed("crash")
  let result = master.restart_worker(wid)
  assert_true(result is Ok(_))
  let w2 = master.find_worker(wid).unwrap()
  @debug.assert_eq(w2.status, Idle)
}

///|
test "stop transitions to ShuttingDown" {
  let master = ServerMaster::new()
  master.start()
  master.stop()
  @debug.assert_eq(master.status, ShuttingDown)
  // Workers should be Stopping
  for w in master.workers {
    @debug.assert_eq(w.status, Stopping)
  }
}

///|
test "pool_stats reflects current state" {
  let master = ServerMaster::new()
  master.start()
  let _ = master.scale_up()
  let _ = master.dispatch_task("work")
  let stats = master.pool_stats()
  @debug.assert_eq(stats.total_workers, 2)
  @debug.assert_eq(stats.idle_workers, 1)
  @debug.assert_eq(stats.busy_workers, 1)
  @debug.assert_eq(stats.failed_workers, 0)
}

///|
test "worker_statuses lists all" {
  let master = ServerMaster::new()
  master.start()
  let _ = master.scale_up()
  let statuses = master.worker_statuses()
  @debug.assert_eq(statuses.length(), 2)
}

///|
test "Worker new defaults to Idle" {
  let wid : WorkerId = { id: 1, name: "test-worker", }
  let config = WorkerConfig::default_with_id(wid)
  let w = Worker::new(config)
  @debug.assert_eq(w.status, Idle)
  @debug.assert_eq(w.tasks_completed, 0)
  @debug.assert_eq(w.tasks_failed, 0)
}

///|
test "Worker mark_busy changes status" {
  let wid : WorkerId = { id: 1, name: "w1", }
  let w = Worker::new(WorkerConfig::default_with_id(wid))
  w.mark_busy("processing")
  @debug.assert_eq(w.status, Busy("processing"))
}

///|
test "Worker task_done increments counters" {
  let wid : WorkerId = { id: 1, name: "w1", }
  let w = Worker::new(WorkerConfig::default_with_id(wid))
  w.mark_busy("t1")
  w.task_done(true)
  @debug.assert_eq(w.tasks_completed, 1)
  @debug.assert_eq(w.tasks_failed, 0)
  w.mark_busy("t2")
  w.task_done(false)
  @debug.assert_eq(w.tasks_completed, 1)
  @debug.assert_eq(w.tasks_failed, 1)
  // A failed task marks the worker `Failed`, which `health_check` reports and
  // `restart_worker` clears.
  @debug.assert_eq(w.status, Failed("task failed"))
  assert_false(w.is_available())
}

///|
test "Worker is_available when Idle" {
  let wid : WorkerId = { id: 1, name: "w1", }
  let w = Worker::new(WorkerConfig::default_with_id(wid))
  assert_true(w.is_available())
  w.mark_busy("work")
  assert_false(w.is_available())
  w.mark_idle()
  assert_true(w.is_available())
}

///|
test "failed task makes the worker unhealthy until restarted" {
  let master = ServerMaster::new()
  master.start()
  let wid = master.dispatch_task("do work").unwrap()
  let _ = master.complete_task(wid, false)
  @debug.assert_eq(
    master.find_worker(wid).unwrap().status,
    Failed("task failed"),
  )
  assert_true(master.health_check("2026-01-01T00:00:00Z").contains(wid))
  @debug.assert_eq(master.pool_stats().failed_workers, 1)
  let _ = master.restart_worker(wid)
  assert_false(master.health_check("2026-01-01T00:00:00Z").contains(wid))
  @debug.assert_eq(master.find_worker(wid).unwrap().status, Idle)
}
