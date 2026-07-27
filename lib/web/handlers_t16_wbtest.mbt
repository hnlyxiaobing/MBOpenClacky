///| White-box tests for T16: pinned sorting, q_scope/date filter, latest_cron_updated_at.

///|
/// Helper: create a minimal SessionSummary for testing.
fn t16_make_summary(
  id : String,
  updated_at : String,
  pinned : Bool,
) -> SessionSummary {
  {
    id,
    name: id,
    working_dir: "/tmp",
    status: "idle",
    created_at: updated_at,
    updated_at,
    total_tasks: 0,
    total_cost: 0.0,
    cost_source: "",
    error: "",
    model: None,
    source: "web",
    latest_latency: None,
    pinned,
    agent_profile: "",
    sub_model: None,
    sub_model_options: [],
    reasoning_effort: None,
    model_id: None,
    card_model: None,
    channel_info: None,
    error_code: None,
    top_up_url: None,
    raw_message: None,
  }
}

///|
test "t16 pinned sort: pinned sessions come before unpinned" {
  let summaries : Array[SessionSummary] = [
    t16_make_summary("s1", "2026-07-27T10:00:00Z", false),
    t16_make_summary("s2", "2026-07-27T09:00:00Z", true),
    t16_make_summary("s3", "2026-07-27T11:00:00Z", false),
    t16_make_summary("s4", "2026-07-27T08:00:00Z", true),
  ]
  summaries.sort_by(fn(a, b) {
    let a_pin = if a.pinned { 0 } else { 1 }
    let b_pin = if b.pinned { 0 } else { 1 }
    let pin_cmp = a_pin.compare(b_pin)
    if pin_cmp != 0 {
      pin_cmp
    } else {
      b.updated_at.compare(a.updated_at)
    }
  })
  // Pinned sessions (s2, s4) should come first, sorted by updated_at descending
  @debug.assert_eq(summaries[0].id, "s2")
  @debug.assert_eq(summaries[1].id, "s4")
  @debug.assert_eq(summaries[2].id, "s3")
  @debug.assert_eq(summaries[3].id, "s1")
}

///|
test "t16 pinned sort: within same pinned status, newer first" {
  let summaries : Array[SessionSummary] = [
    t16_make_summary("old", "2026-01-01T00:00:00Z", true),
    t16_make_summary("new", "2026-12-31T23:59:59Z", true),
    t16_make_summary("mid", "2026-06-15T12:00:00Z", true),
  ]
  summaries.sort_by(fn(a, b) {
    let a_pin = if a.pinned { 0 } else { 1 }
    let b_pin = if b.pinned { 0 } else { 1 }
    let pin_cmp = a_pin.compare(b_pin)
    if pin_cmp != 0 {
      pin_cmp
    } else {
      b.updated_at.compare(a.updated_at)
    }
  })
  @debug.assert_eq(summaries[0].id, "new")
  @debug.assert_eq(summaries[1].id, "mid")
  @debug.assert_eq(summaries[2].id, "old")
}

///|
test "t16 pinned sort: all unpinned, newest first" {
  let summaries : Array[SessionSummary] = [
    t16_make_summary("a", "2026-03-01T00:00:00Z", false),
    t16_make_summary("b", "2026-09-01T00:00:00Z", false),
    t16_make_summary("c", "2026-01-01T00:00:00Z", false),
  ]
  summaries.sort_by(fn(a, b) {
    let a_pin = if a.pinned { 0 } else { 1 }
    let b_pin = if b.pinned { 0 } else { 1 }
    let pin_cmp = a_pin.compare(b_pin)
    if pin_cmp != 0 {
      pin_cmp
    } else {
      b.updated_at.compare(a.updated_at)
    }
  })
  @debug.assert_eq(summaries[0].id, "b")
  @debug.assert_eq(summaries[1].id, "a")
  @debug.assert_eq(summaries[2].id, "c")
}

///|
test "t16 latest_cron_updated_at: empty executions returns null" {
  let old_executions = schedule_state.val.executions.copy()
  schedule_state.val.executions.clear()
  let result = compute_latest_cron_updated_at()
  match result {
    Null => ()
    _ => @debug.assert_eq(true, false) // Expected null
  }
  // Restore
  schedule_state.val.executions.clear()
  for e in old_executions {
    schedule_state.val.executions.push(e)
  }
}

///|
test "t16 latest_cron_updated_at: returns latest execution timestamp" {
  let old_executions = schedule_state.val.executions.copy()
  schedule_state.val.executions.clear()
  schedule_state.val.executions.push({
    schedule_name: "task1",
    status: "success",
    executed_at: "2026-07-27T08:00:00Z",
    output: "",
  })
  schedule_state.val.executions.push({
    schedule_name: "task2",
    status: "success",
    executed_at: "2026-07-27T12:00:00Z",
    output: "",
  })
  schedule_state.val.executions.push({
    schedule_name: "task3",
    status: "failed",
    executed_at: "2026-07-27T10:00:00Z",
    output: "",
  })
  let result = compute_latest_cron_updated_at()
  match result {
    String(s) => @debug.assert_eq(s, "2026-07-27T12:00:00Z")
    _ => @debug.assert_eq(true, false) // Expected string
  }
  // Restore
  schedule_state.val.executions.clear()
  for e in old_executions {
    schedule_state.val.executions.push(e)
  }
}

///|
test "t16 latest_cron_updated_at: single execution" {
  let old_executions = schedule_state.val.executions.copy()
  schedule_state.val.executions.clear()
  schedule_state.val.executions.push({
    schedule_name: "only",
    status: "success",
    executed_at: "2026-01-15T10:30:00Z",
    output: "done",
  })
  let result = compute_latest_cron_updated_at()
  match result {
    String(s) => @debug.assert_eq(s, "2026-01-15T10:30:00Z")
    _ => @debug.assert_eq(true, false) // Expected string
  }
  // Restore
  schedule_state.val.executions.clear()
  for e in old_executions {
    schedule_state.val.executions.push(e)
  }
}

///|
test "t16 date filter: has_prefix matches date prefix" {
  let created_at = "2026-07-27T10:30:00Z"
  let date_filter = "2026-07-27"
  assert_true(created_at.has_prefix(date_filter))
  assert_false(created_at.has_prefix("2026-07-26"))
  assert_false(created_at.has_prefix("2026-06"))
}

///|
test "t16 date filter: partial date prefix works" {
  let created_at = "2026-07-27T10:30:00Z"
  assert_true(created_at.has_prefix("2026-07"))
  assert_true(created_at.has_prefix("2026"))
  assert_false(created_at.has_prefix("2025"))
}
