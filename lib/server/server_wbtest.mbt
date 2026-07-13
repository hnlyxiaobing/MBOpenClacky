///|
test "cron_parse_every_minute" {
  let result = CronExpression::parse("* * * * *")
  match result {
    Ok(expr) => {
      @debug.assert_eq(expr.minute, Any)
      @debug.assert_eq(expr.hour, Any)
      @debug.assert_eq(expr.day_of_month, Any)
      @debug.assert_eq(expr.month, Any)
      @debug.assert_eq(expr.day_of_week, Any)
      @debug.assert_eq(expr.raw, "* * * * *")
    }
    Err(e) => fail("unexpected error: \{e}")
  }
}

///|
test "cron_parse_specific_time" {
  let result = CronExpression::parse("30 9 * * *")
  match result {
    Ok(expr) => {
      @debug.assert_eq(expr.minute, Value(30))
      @debug.assert_eq(expr.hour, Value(9))
      @debug.assert_eq(expr.day_of_month, Any)
      @debug.assert_eq(expr.month, Any)
      @debug.assert_eq(expr.day_of_week, Any)
    }
    Err(e) => fail("unexpected error: \{e}")
  }
}

///|
test "cron_parse_step" {
  let result = CronExpression::parse("*/5 * * * *")
  match result {
    Ok(expr) => {
      @debug.assert_eq(expr.minute, Step(0, 5))
      @debug.assert_eq(expr.hour, Any)
    }
    Err(e) => fail("unexpected error: \{e}")
  }
}

///|
test "cron_parse_range" {
  let result = CronExpression::parse("0 9-17 * * *")
  match result {
    Ok(expr) => {
      @debug.assert_eq(expr.minute, Value(0))
      @debug.assert_eq(expr.hour, Range(9, 17))
    }
    Err(e) => fail("unexpected error: \{e}")
  }
}

///|
test "cron_parse_range_step" {
  let result = CronExpression::parse("0 9-17/2 * * *")
  match result {
    Ok(expr) => {
      @debug.assert_eq(expr.minute, Value(0))
      @debug.assert_eq(expr.hour, RangeStep(9, 17, 2))
    }
    Err(e) => fail("unexpected error: \{e}")
  }
}

///|
test "cron_parse_list" {
  let result = CronExpression::parse("0 9,12,18 * * *")
  match result {
    Ok(expr) => {
      @debug.assert_eq(expr.minute, Value(0))
      @debug.assert_eq(expr.hour, List([9, 12, 18]))
    }
    Err(e) => fail("unexpected error: \{e}")
  }
}

///|
test "cron_parse_weekday" {
  let result = CronExpression::parse("0 9 * * 1-5")
  match result {
    Ok(expr) => {
      @debug.assert_eq(expr.minute, Value(0))
      @debug.assert_eq(expr.hour, Value(9))
      @debug.assert_eq(expr.day_of_week, Range(1, 5))
    }
    Err(e) => fail("unexpected error: \{e}")
  }
}

///|
test "cron_parse_invalid" {
  // Too few fields
  let r1 = CronExpression::parse("* * *")
  assert_true(r1 is Err(_))
  // Invalid value
  let r2 = CronExpression::parse("60 * * * *")
  assert_true(r2 is Err(_))
  // Invalid range
  let r3 = CronExpression::parse("* 25 * * *")
  assert_true(r3 is Err(_))
}

///|
test "cron_matches_basic" {
  let expr = CronExpression::parse("30 9 * * *").unwrap()
  assert_true(expr.matches(30, 9, 15, 6, 3))
  assert_false(expr.matches(31, 9, 15, 6, 3))
  assert_false(expr.matches(30, 10, 15, 6, 3))
}

///|
test "cron_matches_step" {
  let expr = CronExpression::parse("*/5 * * * *").unwrap()
  assert_true(expr.matches(0, 12, 1, 1, 0))
  assert_true(expr.matches(5, 12, 1, 1, 0))
  assert_true(expr.matches(10, 12, 1, 1, 0))
  assert_true(expr.matches(55, 12, 1, 1, 0))
  assert_false(expr.matches(3, 12, 1, 1, 0))
  assert_false(expr.matches(7, 12, 1, 1, 0))
}

///|
test "cron_matches_range" {
  let expr = CronExpression::parse("0 9-17 * * *").unwrap()
  assert_true(expr.matches(0, 9, 1, 1, 0))
  assert_true(expr.matches(0, 13, 1, 1, 0))
  assert_true(expr.matches(0, 17, 1, 1, 0))
  assert_false(expr.matches(0, 8, 1, 1, 0))
  assert_false(expr.matches(0, 18, 1, 1, 0))
}

///|
test "cron_matches_list" {
  let expr = CronExpression::parse("0 9,12,18 * * *").unwrap()
  assert_true(expr.matches(0, 9, 1, 1, 0))
  assert_true(expr.matches(0, 12, 1, 1, 0))
  assert_true(expr.matches(0, 18, 1, 1, 0))
  assert_false(expr.matches(0, 10, 1, 1, 0))
  assert_false(expr.matches(0, 15, 1, 1, 0))
}

///|
test "cron_no_match" {
  let expr = CronExpression::parse("0 9 * * 1-5").unwrap()
  // weekday 0 = Sunday, should not match 1-5
  assert_false(expr.matches(0, 9, 1, 1, 0))
  // weekday 6 = Saturday, should not match 1-5
  assert_false(expr.matches(0, 9, 1, 1, 6))
  // weekday 3 = Wednesday, should match
  assert_true(expr.matches(0, 9, 1, 1, 3))
}

///|
test "scheduler_new" {
  let config : SchedulerConfig = {
    schedules: [],
    tasks_dir: "/tmp/tasks",
    config_path: "/tmp/schedules.yml",
  }
  let scheduler = Scheduler::new(config)
  @debug.assert_eq(scheduler.state, Stopped)
  @debug.assert_eq(scheduler.last_check_at, None)
}

///|
test "scheduler_add_schedule" {
  let config : SchedulerConfig = {
    schedules: [],
    tasks_dir: "/tmp/tasks",
    config_path: "/tmp/schedules.yml",
  }
  let scheduler = Scheduler::new(config)
  let result = scheduler.add_schedule(
    "daily-backup", "backup", "0 2 * * *", true,
  )
  assert_true(result is Ok(_))
  @debug.assert_eq(scheduler.config.schedules.length(), 1)
  @debug.assert_eq(scheduler.config.schedules[0].name, "daily-backup")
  @debug.assert_eq(scheduler.config.schedules[0].task_name, "backup")
  @debug.assert_eq(scheduler.config.schedules[0].enabled, true)
}

///|
test "scheduler_remove_schedule" {
  let config : SchedulerConfig = {
    schedules: [],
    tasks_dir: "/tmp/tasks",
    config_path: "/tmp/schedules.yml",
  }
  let scheduler = Scheduler::new(config)
  let _ = scheduler.add_schedule("test-task", "test", "* * * * *", true)
  @debug.assert_eq(scheduler.config.schedules.length(), 1)
  let result = scheduler.remove_schedule("test-task")
  assert_true(result is Ok(_))
  @debug.assert_eq(scheduler.config.schedules.length(), 0)
  // Remove non-existent
  let r2 = scheduler.remove_schedule("nonexistent")
  assert_true(r2 is Err(_))
}

///|
test "scheduler_list_schedules" {
  let config : SchedulerConfig = {
    schedules: [],
    tasks_dir: "/tmp/tasks",
    config_path: "/tmp/schedules.yml",
  }
  let scheduler = Scheduler::new(config)
  let _ = scheduler.add_schedule("task1", "t1", "0 * * * *", true)
  let _ = scheduler.add_schedule("task2", "t2", "*/5 * * * *", false)
  let list = scheduler.list_schedules()
  @debug.assert_eq(list.length(), 2)
}

///|
test "scheduler_tick_executes_due" {
  let config : SchedulerConfig = {
    schedules: [],
    tasks_dir: "/tmp/tasks",
    config_path: "/tmp/schedules.yml",
  }
  let scheduler = Scheduler::new(config)
  let _ = scheduler.add_schedule("hourly", "cleanup", "0 * * * *", true)
  let _ = scheduler.start()
  // At minute=0, should trigger
  let due = scheduler.tick(0, 12, 15, 6, 3)
  @debug.assert_eq(due.length(), 1)
  @debug.assert_eq(due[0], "cleanup")
  // At minute=30, should not trigger
  let not_due = scheduler.tick(30, 12, 15, 6, 3)
  @debug.assert_eq(not_due.length(), 0)
}

///|
test "scheduler_tick_skips_disabled" {
  let config : SchedulerConfig = {
    schedules: [],
    tasks_dir: "/tmp/tasks",
    config_path: "/tmp/schedules.yml",
  }
  let scheduler = Scheduler::new(config)
  let _ = scheduler.add_schedule("disabled-task", "noop", "* * * * *", false)
  let _ = scheduler.start()
  let due = scheduler.tick(0, 0, 1, 1, 0)
  @debug.assert_eq(due.length(), 0)
}

///|
test "scheduler_get_schedule" {
  let config : SchedulerConfig = {
    schedules: [],
    tasks_dir: "/tmp/tasks",
    config_path: "/tmp/schedules.yml",
  }
  let scheduler = Scheduler::new(config)
  let _ = scheduler.add_schedule("my-task", "run-it", "*/10 * * * *", true)
  match scheduler.get_schedule("my-task") {
    Some(s) => {
      @debug.assert_eq(s.name, "my-task")
      @debug.assert_eq(s.task_name, "run-it")
    }
    None => fail("schedule not found")
  }
  assert_true(scheduler.get_schedule("nonexistent") is None)
}

///|
test "browser_config_default" {
  let config = BrowserConfig::default_config()
  @debug.assert_eq(config.enabled, false)
  @debug.assert_eq(config.chrome_version, None)
  @debug.assert_eq(config.configured_at, None)
  @debug.assert_eq(config.mcp_command, "chrome-devtools-mcp")
  @debug.assert_eq(config.features.length(), 3)
}

///|
test "browser_manager_new" {
  let mgr = BrowserManager::new("/home/user/.mbopenclacky/browser.yml")
  @debug.assert_eq(mgr.is_running, false)
  @debug.assert_eq(mgr.daemon_pid, None)
  @debug.assert_eq(mgr.started_at, None)
  @debug.assert_eq(mgr.config.enabled, false)
}

///|
test "browser_status_not_running" {
  let mgr = BrowserManager::new("/tmp/browser.yml")
  let status = mgr.status()
  @debug.assert_eq(status.enabled, false)
  @debug.assert_eq(status.daemon_running, false)
  @debug.assert_eq(status.chrome_version, None)
  @debug.assert_eq(status.pid, None)
  @debug.assert_eq(status.uptime_seconds, None)
}

///|
test "browser_toggle" {
  let mgr = BrowserManager::new("/tmp/browser.yml")
  // Default enabled = false, toggle returns !enabled = true
  let new_state = mgr.toggle()
  @debug.assert_eq(new_state, true)
}

///|
test "backup_config_default" {
  let config = BackupConfig::default_config()
  @debug.assert_eq(config.enabled, false)
  @debug.assert_eq(config.cron, None)
  @debug.assert_eq(config.dest_dir, "~/clacky_backups")
  @debug.assert_eq(config.keep, 7)
  @debug.assert_eq(config.include_sessions, true)
}

///|
test "backup_manager_new" {
  let mgr = BackupManager::new("/tmp/backup.yml", "/home/user/.mbopenclacky")
  @debug.assert_eq(mgr.config.enabled, false)
  @debug.assert_eq(mgr.source_dir, "/home/user/.mbopenclacky")
  @debug.assert_eq(mgr.config_path, "/tmp/backup.yml")
}

///|
test "backup_should_exclude" {
  assert_true(should_exclude("/path/to/ocr_cache/file.dat"))
  assert_true(should_exclude("/path/to/.DS_Store"))
  assert_true(should_exclude("/some/trash/file"))
  assert_true(should_exclude("/logs/safety_logs/event.log"))
  assert_false(should_exclude("/path/to/config.yml"))
  assert_false(should_exclude("/path/to/sessions/abc.json"))
}

///|
test "backup_generate_archive_name" {
  let name = generate_archive_name("20260617-143000")
  @debug.assert_eq(name, "mbopenclacky-backup-20260617-143000.tar.gz")
}

///|
test "discover_extract_port" {
  let port = extract_port_from_filename("mbopenclacky-master-8080.pid")
  @debug.assert_eq(port, Some(8080))
  let port2 = extract_port_from_filename("mbopenclacky-master-3000.pid")
  @debug.assert_eq(port2, Some(3000))
  // Invalid prefix
  let none1 = extract_port_from_filename("other-prefix-8080.pid")
  @debug.assert_eq(none1, None)
  // No .pid suffix
  let none2 = extract_port_from_filename("mbopenclacky-master-8080.txt")
  @debug.assert_eq(none2, None)
  // Empty port
  let none3 = extract_port_from_filename("mbopenclacky-master-.pid")
  @debug.assert_eq(none3, None)
}

///|
test "discover_find_all_empty" {
  let servers = find_all_local()
  @debug.assert_eq(servers.length(), 0)
}

///|
test "server_instance_creation" {
  let instance : ServerInstance = { host: "127.0.0.1", port: 8080, pid: 12345 }
  @debug.assert_eq(instance.host, "127.0.0.1")
  @debug.assert_eq(instance.port, 8080)
  @debug.assert_eq(instance.pid, 12345)
}
