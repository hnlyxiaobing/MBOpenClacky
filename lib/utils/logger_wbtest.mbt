///|
test "format_log_line basic" {
  // Set a known timestamp for deterministic output
  @sys.set_env_var("MBOPENCLACKY_LOG_TIMESTAMP", "2026-06-23T21:30:00")
  let line = format_log_line(Info, "server started", [])
  @debug.assert_eq(line, "[2026-06-23T21:30:00] INFO  server started")
  @sys.set_env_var("MBOPENCLACKY_LOG_TIMESTAMP", "")
}

///|
test "format_log_line with context" {
  @sys.set_env_var("MBOPENCLACKY_LOG_TIMESTAMP", "2026-06-23T21:30:00")
  let ctx : LogContext = [("host", "localhost"), ("port", "8080")]
  let line = format_log_line(Error, "connection failed", ctx)
  @debug.assert_eq(
    line, "[2026-06-23T21:30:00] ERROR connection failed | host=localhost port=8080",
  )
  @sys.set_env_var("MBOPENCLACKY_LOG_TIMESTAMP", "")
}

///|
test "should_log level filtering" {
  let logger = Logger::new(min_level=Warn)
  // Debug and Info should be filtered out
  assert_false(logger.should_log(Debug))
  assert_false(logger.should_log(Info))
  // Warn and Error should pass
  assert_true(logger.should_log(Warn))
  assert_true(logger.should_log(Error))
}

///|
test "level_label formatting" {
  // All labels must be exactly 5 characters wide
  @debug.assert_eq(level_label(Debug), "DEBUG")
  @debug.assert_eq(level_label(Info), "INFO ")
  @debug.assert_eq(level_label(Warn), "WARN ")
  @debug.assert_eq(level_label(Error), "ERROR")
  // Verify fixed width
  @debug.assert_eq(level_label(Debug).length(), 5)
  @debug.assert_eq(level_label(Info).length(), 5)
  @debug.assert_eq(level_label(Warn).length(), 5)
  @debug.assert_eq(level_label(Error).length(), 5)
}

///|
test "logger new defaults" {
  let logger = Logger::new()
  @debug.assert_eq(logger.max_files, 7)
  assert_true(logger.min_level == Info)
  @debug.assert_eq(logger.console_echo, false)
  // Default log_dir should contain ".mbopenclacky"
  assert_true(logger.log_dir.contains("logs"))
}

///|
test "log_filename format" {
  @sys.set_env_var("MBOPENCLACKY_LOG_DATE", "2026-06-23")
  let logger = Logger::new()
  let filename = logger.log_filename()
  @debug.assert_eq(filename, "clacky-2026-06-23.log")
  assert_true(filename.has_prefix("clacky-"))
  assert_true(filename.has_suffix(".log"))
  @sys.set_env_var("MBOPENCLACKY_LOG_DATE", "")
}
