///|
/// Unit tests for the system tips row (TipsState + format_tips).

///|
test "tips: set shows message and restarts expiry window" {
  let tips = TipsState::new()
  assert_true(tips.message is None)
  tips.set("hello", TipsType::Info, 100)
  assert_eq(tips.message, Some("hello"))
  assert_eq(tips.type_, TipsType::Info)
  // Not expired within the 2s (10 tick) window.
  assert_true(!tips.is_expired(109))
  // Expired exactly at the window boundary.
  assert_true(tips.is_expired(110))
  // Re-setting restarts the window.
  tips.set("again", TipsType::Warn, 109)
  assert_true(!tips.is_expired(118))
  assert_true(tips.is_expired(119))
}

///|
test "tips: clear hides the row and disarms expiry" {
  let tips = TipsState::new()
  tips.set("x", TipsType::Error, 0)
  tips.clear()
  assert_true(tips.message is None)
  assert_true(!tips.is_expired(100))
}

///|
test "format_tips: severity prefixes and colors" {
  let info = format_tips("m", TipsType::Info, 80)
  assert_true(
    info.contains("[") && info.contains("Info") && info.contains("] "),
  )
  assert_true(info.contains("\u{1b}[36m")) // cyan
  assert_true(info.contains("m"))
  let warn = format_tips("m", TipsType::Warn, 80)
  assert_true(warn.contains("Warn"))
  assert_true(warn.contains("\u{1b}[33m")) // yellow
  let err = format_tips("m", TipsType::Error, 80)
  assert_true(err.contains("Error"))
  assert_true(err.contains("\u{1b}[31m")) // red
}

///|
test "format_tips: long messages are truncated to width - 10" {
  let long = "x".repeat(200)
  let line = format_tips(long, TipsType::Info, 80)
  assert_true(line.contains("..."))
  // 70 visible message chars max (67 + "...").
  assert_true(!line.contains("x".repeat(71)))
}
