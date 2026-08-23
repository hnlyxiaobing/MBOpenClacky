///|
/// White-box tests for Scheduler persistence (schedules.yml round-trip).
/// Each test uses a unique file under /tmp and cleans up afterwards so
/// parallel test runs never collide (and never touch the real config).

///|
/// Best-effort file removal (missing file is fine).
fn sched_cleanup(path : String) -> Unit {
  if @fs.path_exists(path) {
    let _ = @fs.remove_file(path) catch { _ => () }
  }
}

///|
test "scheduler_persist_roundtrip" {
  let config_path = "/tmp/mboc-wbt-sched-persist-rt.yml"
  sched_cleanup(config_path)
  let config : SchedulerConfig = {
    schedules: [],
    tasks_dir: "/tmp/mboc-wbt-sched-tasks",
    config_path,
  }
  let scheduler = Scheduler::new(config)
  let add = scheduler.add_schedule("daily-backup", "backup", "0 2 * * *", true)
  assert_true(add is Ok(_))
  // Reload from disk and verify fields survive the round-trip
  let reloaded = Scheduler::load_from_config(config_path).unwrap()
  let schedules = reloaded.list_schedules()
  @debug.assert_eq(schedules.length(), 1)
  @debug.assert_eq(schedules[0].name, "daily-backup")
  @debug.assert_eq(schedules[0].task_name, "backup")
  @debug.assert_eq(schedules[0].cron.raw, "0 2 * * *")
  @debug.assert_eq(schedules[0].enabled, true)
  sched_cleanup(config_path)
}

///|
/// Task names containing quotes/backslashes must round-trip through the
/// YAML quoting layer (W8 fix).
test "scheduler_persist_special_chars_roundtrip" {
  let config_path = "/tmp/mboc-wbt-sched-persist-quote.yml"
  sched_cleanup(config_path)
  let config : SchedulerConfig = {
    schedules: [],
    tasks_dir: "/tmp/mboc-wbt-sched-tasks",
    config_path,
  }
  let scheduler = Scheduler::new(config)
  let tricky = "say \"hi\" \\ now"
  let add = scheduler.add_schedule(tricky, "backup", "0 2 * * *", true)
  assert_true(add is Ok(_))
  let reloaded = Scheduler::load_from_config(config_path).unwrap()
  let schedules = reloaded.list_schedules()
  @debug.assert_eq(schedules.length(), 1)
  // The name must survive escaping exactly
  @debug.assert_eq(schedules[0].name, tricky)
  sched_cleanup(config_path)
}

///|
/// A dirty schedules.yml (garbage lines, malformed cron, incomplete
/// entries) must load without error and keep only the valid entries.
test "scheduler_persist_dirty_file_tolerated" {
  let config_path = "/tmp/mboc-wbt-sched-persist-dirty.yml"
  sched_cleanup(config_path)
  let dirty = "# schedules.yml - managed by MBOpenClacky scheduler\n" +
    "tasks_dir: \"/tmp/mboc-wbt-sched-tasks\"\n" +
    "this is total garbage !!!\n" +
    "schedules:\n" +
    "- name: \"good-task\"\n" +
    "  task_name: \"good\"\n" +
    "  cron: \"0 2 * * *\"\n" +
    "  enabled: true\n" +
    "  run_count: 3\n" +
    "- name: \"bad-cron\"\n" +
    "  cron: \"not a cron\"\n" +
    "- name: \"no-cron\"\n" +
    "  enabled: true\n"
  @fs.write_string_to_file(config_path, dirty) catch {
    _ => fail("test setup: could not write dirty config")
  }
  let result = Scheduler::load_from_config(config_path)
  assert_true(result is Ok(_))
  let scheduler = result.unwrap()
  let schedules = scheduler.list_schedules()
  // Only the complete, valid entry survives
  @debug.assert_eq(schedules.length(), 1)
  @debug.assert_eq(schedules[0].name, "good-task")
  @debug.assert_eq(schedules[0].run_count, 3)
  @debug.assert_eq(scheduler.config.tasks_dir, "/tmp/mboc-wbt-sched-tasks")
  sched_cleanup(config_path)
}

///|
/// Missing config file = graceful empty start (decision 5).
test "scheduler_persist_missing_file_empty_start" {
  let config_path = "/tmp/mboc-wbt-sched-persist-missing.yml"
  sched_cleanup(config_path)
  let result = Scheduler::load_from_config(config_path)
  assert_true(result is Ok(_))
  let scheduler = result.unwrap()
  @debug.assert_eq(scheduler.list_schedules().length(), 0)
}

///|
/// remove_schedule must persist the removal (file no longer lists it).
test "scheduler_remove_persists" {
  let config_path = "/tmp/mboc-wbt-sched-persist-del.yml"
  sched_cleanup(config_path)
  let config : SchedulerConfig = {
    schedules: [],
    tasks_dir: "/tmp/mboc-wbt-sched-tasks",
    config_path,
  }
  let scheduler = Scheduler::new(config)
  let _ = scheduler.add_schedule("keep-me", "t1", "0 2 * * *", true)
  let _ = scheduler.add_schedule("drop-me", "t2", "0 3 * * *", true)
  let removed = scheduler.remove_schedule("drop-me")
  assert_true(removed is Ok(_))
  let reloaded = Scheduler::load_from_config(config_path).unwrap()
  let schedules = reloaded.list_schedules()
  @debug.assert_eq(schedules.length(), 1)
  @debug.assert_eq(schedules[0].name, "keep-me")
  sched_cleanup(config_path)
}

///|
/// add_schedule with an invalid cron must fail AND leave nothing on disk.
test "scheduler_add_invalid_cron_no_persist" {
  let config_path = "/tmp/mboc-wbt-sched-persist-bad.yml"
  sched_cleanup(config_path)
  let config : SchedulerConfig = {
    schedules: [],
    tasks_dir: "/tmp/mboc-wbt-sched-tasks",
    config_path,
  }
  let scheduler = Scheduler::new(config)
  let result = scheduler.add_schedule("bad", "t", "not a cron", true)
  assert_true(result is Err(_))
  // Nothing was written (memory-only failure must not create the file)
  let reloaded = Scheduler::load_from_config(config_path).unwrap()
  @debug.assert_eq(reloaded.list_schedules().length(), 0)
}

///|
/// update_schedule with an invalid cron must fail atomically: neither the
/// in-memory schedule nor the persisted file keeps a half-applied change.
test "scheduler_update_atomic_invalid_cron" {
  let config_path = "/tmp/mboc-wbt-sched-persist-atomic.yml"
  sched_cleanup(config_path)
  let config : SchedulerConfig = {
    schedules: [],
    tasks_dir: "/tmp/mboc-wbt-sched-tasks",
    config_path,
  }
  let scheduler = Scheduler::new(config)
  let _ = scheduler.add_schedule("stable", "t", "0 2 * * *", true)
  // Try to update with a broken cron: must Err
  let result = scheduler.update_schedule("stable", Some("garbage"), None)
  assert_true(result is Err(_))
  // In-memory cron unchanged
  @debug.assert_eq(
    scheduler.get_schedule("stable").unwrap().cron.raw,
    "0 2 * * *",
  )
  // Persisted cron unchanged too
  let reloaded = Scheduler::load_from_config(config_path).unwrap()
  @debug.assert_eq(
    reloaded.get_schedule("stable").unwrap().cron.raw,
    "0 2 * * *",
  )
  sched_cleanup(config_path)
}

///|
/// create_cron_task must reject path-traversal names before any file is
/// written (W5 fix).
test "scheduler_create_cron_task_rejects_traversal" {
  let config_path = "/tmp/mboc-wbt-sched-persist-trav.yml"
  sched_cleanup(config_path)
  let tasks_dir = "/tmp/mboc-wbt-sched-tasks-trav"
  let config : SchedulerConfig = { schedules: [], tasks_dir, config_path }
  let scheduler = Scheduler::new(config)
  for evil in ["../evil", "a/b", "a\\b", "..", ""] {
    let result = scheduler.create_cron_task(evil, "content", "* * * * *")
    assert_true(result is Err(_))
  }
  sched_cleanup(config_path)
}

///|
/// add_schedule duplicate names are rejected.
test "scheduler_add_duplicate_name_rejected" {
  let config_path = "/tmp/mboc-wbt-sched-persist-dup.yml"
  sched_cleanup(config_path)
  let config : SchedulerConfig = {
    schedules: [],
    tasks_dir: "/tmp/mboc-wbt-sched-tasks",
    config_path,
  }
  let scheduler = Scheduler::new(config)
  let _ = scheduler.add_schedule("dup", "t", "0 2 * * *", true)
  let result = scheduler.add_schedule("dup", "t2", "0 3 * * *", true)
  assert_true(result is Err(_))
  @debug.assert_eq(scheduler.list_schedules().length(), 1)
  sched_cleanup(config_path)
}

///|
/// Write-through failures must propagate as Err (C7 fix): an unwritable
/// config_path cannot silently succeed.
test "scheduler_save_failure_propagates" {
  // /proc rejects regular file creation even for root
  let config_path = "/proc/mboc-wbt-sched-impossible.yml"
  let config : SchedulerConfig = {
    schedules: [],
    tasks_dir: "/tmp/mboc-wbt-sched-tasks",
    config_path,
  }
  let scheduler = Scheduler::new(config)
  let result = scheduler.add_schedule("doomed", "t", "0 2 * * *", true)
  assert_true(result is Err(_))
  // remove_schedule must also surface the write failure
  let config2 : SchedulerConfig = {
    schedules: [
      {
        name: "existing",
        task_name: "t",
        cron: CronExpression::parse("0 2 * * *").unwrap(),
        enabled: true,
        last_run_at: None,
        next_run_at: None,
        run_count: 0,
      },
    ],
    tasks_dir: "/tmp/mboc-wbt-sched-tasks",
    config_path,
  }
  let scheduler2 = Scheduler::new(config2)
  let result2 = scheduler2.remove_schedule("existing")
  assert_true(result2 is Err(_))
}

///|
/// yml_quote / yml_unquote escape round-trip (W8).
test "scheduler_yml_quote_roundtrip" {
  for s in ["plain", "with \"quote\"", "back\\slash", "both \" and \\ mixed"] {
    let quoted = yml_quote(s)
    let unquoted = yml_unquote(quoted)
    @debug.assert_eq(unquoted, s)
  }
}
