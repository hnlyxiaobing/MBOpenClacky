///| Extended server tests: cron expression parsing, backup config, backup types.

// ── BackupConfig Tests ──────────────────────────────────────────────────────

///|
test "ext_backup_config_default" {
  let cfg = BackupConfig::default_config()
  assert_false(cfg.enabled)
  assert_true(cfg.cron is None)
  assert_eq(cfg.dest_dir, "~/clacky_backups")
  assert_eq(cfg.keep, 7)
  assert_true(cfg.include_sessions)
}

///|
test "ext_backup_config_mutable" {
  let cfg = BackupConfig::default_config()
  cfg.enabled = true
  cfg.dest_dir = "/tmp/backups"
  cfg.keep = 30
  cfg.include_sessions = false
  assert_true(cfg.enabled)
  assert_eq(cfg.dest_dir, "/tmp/backups")
  assert_eq(cfg.keep, 30)
  assert_false(cfg.include_sessions)
}

// ── BackupResult & BackupEntry Tests ─────────────────────────────────────────

///|
test "ext_backup_result_construction" {
  let r : BackupResult = {
    archive_path: "/tmp/backup.tar.gz",
    size_bytes: 1024,
    dest_dir: "/tmp",
    timestamp: "2026-01-01",
    files_count: 10,
  }
  assert_eq(r.archive_path, "/tmp/backup.tar.gz")
  assert_eq(r.size_bytes, 1024)
  assert_eq(r.files_count, 10)
}

///|
test "ext_backup_result_equality" {
  let r1 : BackupResult = {
    archive_path: "a",
    size_bytes: 1,
    dest_dir: "d",
    timestamp: "t",
    files_count: 1,
  }
  let r2 : BackupResult = {
    archive_path: "a",
    size_bytes: 1,
    dest_dir: "d",
    timestamp: "t",
    files_count: 1,
  }
  assert_true(r1 == r2)
}

///|
test "ext_backup_entry_construction" {
  let e : BackupEntry = {
    name: "backup-001",
    path: "/tmp/backup-001.tar.gz",
    size_bytes: 2048,
    created_at: "2026-01-01T00:00:00Z",
  }
  assert_eq(e.name, "backup-001")
  assert_eq(e.size_bytes, 2048)
}

// ── CronExpression::parse Tests ─────────────────────────────────────────────

///|
test "ext_cron_parse_every_5_minutes" {
  let result = CronExpression::parse("*/5 * * * *")
  assert_true(result is Ok(_))
  match result {
    Ok(expr) => assert_eq(expr.raw, "*/5 * * * *")
    Err(_) => assert_true(false)
  }
}

///|
test "ext_cron_parse_daily_2am" {
  let result = CronExpression::parse("0 2 * * *")
  assert_true(result is Ok(_))
}

///|
test "ext_cron_parse_monthly_first" {
  let result = CronExpression::parse("0 0 1 * *")
  assert_true(result is Ok(_))
}

///|
test "ext_cron_parse_weekly_sunday" {
  let result = CronExpression::parse("0 0 * * 0")
  assert_true(result is Ok(_))
}

///|
test "ext_cron_parse_too_few_fields" {
  let result = CronExpression::parse("0 2 * *")
  assert_true(result is Err(_))
}

///|
test "ext_cron_parse_too_many_fields" {
  let result = CronExpression::parse("0 2 * * * extra")
  assert_true(result is Err(_))
}

///|
test "ext_cron_parse_empty_string" {
  let result = CronExpression::parse("")
  assert_true(result is Err(_))
}

///|
test "ext_cron_parse_invalid_value" {
  let result = CronExpression::parse("60 * * * *")
  assert_true(result is Err(_))
}

// ── parse_cron_field Tests ──────────────────────────────────────────────────

///|
test "ext_parse_cron_field_any" {
  let result = parse_cron_field("*", 0, 59)
  match result {
    Ok(f) => assert_true(f == CronField::Any)
    Err(_) => assert_true(false)
  }
}

///|
test "ext_parse_cron_field_step" {
  let result = parse_cron_field("*/5", 0, 59)
  match result {
    Ok(f) => assert_true(f == CronField::Step(0, 5))
    Err(_) => assert_true(false)
  }
}

///|
test "ext_parse_cron_field_value" {
  let result = parse_cron_field("5", 0, 59)
  match result {
    Ok(f) => assert_true(f == CronField::Value(5))
    Err(_) => assert_true(false)
  }
}

///|
test "ext_parse_cron_field_range" {
  let result = parse_cron_field("1-5", 0, 59)
  match result {
    Ok(f) => assert_true(f == CronField::Range(1, 5))
    Err(_) => assert_true(false)
  }
}

///|
test "ext_parse_cron_field_list" {
  let result = parse_cron_field("1,3,5", 0, 59)
  match result {
    Ok(CronField::List(arr)) => assert_eq(arr.length(), 3)
    _ => assert_true(false)
  }
}

///|
test "ext_parse_cron_field_out_of_range" {
  let result = parse_cron_field("60", 0, 59)
  assert_true(result is Err(_))
}

///|
test "ext_parse_cron_field_range_step" {
  let result = parse_cron_field("1-10/2", 0, 59)
  match result {
    Ok(f) => assert_true(f == CronField::RangeStep(1, 10, 2))
    Err(_) => assert_true(false)
  }
}

// ── Additional CronExpression::parse Tests ──────────────────────────────────

///|
test "ext_cron_parse_hourly" {
  assert_true(CronExpression::parse("0 * * * *") is Ok(_))
}

///|
test "ext_cron_parse_every_15_minutes" {
  assert_true(CronExpression::parse("*/15 * * * *") is Ok(_))
}

///|
test "ext_cron_parse_specific_hour" {
  assert_true(CronExpression::parse("30 9 * * *") is Ok(_))
}

///|
test "ext_cron_parse_weekday_range" {
  assert_true(CronExpression::parse("0 9 * * 1-5") is Ok(_))
}

///|
test "ext_cron_parse_month_range" {
  assert_true(CronExpression::parse("0 0 1 1-6 *") is Ok(_))
}

///|
test "ext_cron_parse_list_values" {
  assert_true(CronExpression::parse("0,30 * * * *") is Ok(_))
}

///|
test "ext_cron_parse_invalid_hour" {
  assert_true(CronExpression::parse("0 24 * * *") is Err(_))
}

///|
test "ext_cron_parse_invalid_month" {
  assert_true(CronExpression::parse("0 0 * 13 *") is Err(_))
}

///|
test "ext_cron_parse_preserves_raw" {
  match CronExpression::parse("0 2 * * *") {
    Ok(expr) => assert_eq(expr.raw, "0 2 * * *")
    Err(_) => assert_true(false)
  }
}

// ── Additional parse_cron_field Tests ────────────────────────────────────────

///|
test "ext_parse_cron_field_zero" {
  match parse_cron_field("0", 0, 59) {
    Ok(f) => assert_true(f == CronField::Value(0))
    Err(_) => assert_true(false)
  }
}

///|
test "ext_parse_cron_field_max_value" {
  assert_true(parse_cron_field("59", 0, 59) is Ok(_))
}

///|
test "ext_parse_cron_field_step_out_of_range" {
  assert_true(parse_cron_field("*/100", 0, 59) is Err(_))
}

///|
test "ext_parse_cron_field_empty_string" {
  assert_true(parse_cron_field("", 0, 59) is Err(_))
}

///|
test "ext_parse_cron_field_large_list" {
  match parse_cron_field("0,5,10,15,20,25,30,35,40,45,50,55", 0, 59) {
    Ok(CronField::List(arr)) => assert_eq(arr.length(), 12)
    _ => assert_true(false)
  }
}

// ── Additional BackupConfig Tests ───────────────────────────────────────────

///|
test "ext_backup_config_equality" {
  let c1 = BackupConfig::default_config()
  let c2 = BackupConfig::default_config()
  assert_true(c1 == c2)
}

///|
test "ext_backup_result_to_json" {
  let r : BackupResult = {
    archive_path: "/tmp/b.tar.gz",
    size_bytes: 100,
    dest_dir: "/tmp",
    timestamp: "2026-01-01",
    files_count: 5,
  }
  match r.to_json() {
    Object(obj) => assert_true(obj.get("files_count") is Some(_))
    _ => assert_true(false)
  }
}
