///| Tests for the deterministic tool harness (T7).
///
/// These run the *shipped* task set in `test/eval/tasks/`, so a regression in
/// the tool layer or in a task file fails `moon test test/eval --release`.

///|
/// The shipped task directory, relative to the module root (`moon test` runs
/// with the module root as the working directory).
fn shipped_tasks_dir() -> String {
  "test/eval/tasks"
}

///|
/// Sandbox root for harness runs started from tests.
fn harness_test_root() -> String {
  "_build/eval_wbtest"
}

///|
async test "harness: shipped task set passes on every trial" {
  let tasks = load_harness_tasks(shipped_tasks_dir())
  @debug.assert_eq(tasks.length(), 3)
  let report = run_harness_batch(tasks, harness_test_root(), 2)
  let score = report.score(2)
  for result in report.results {
    for assertion in result.assertions {
      if !assertion.passed {
        println(
          "[harness FAIL] \{result.task_id}: \{assertion.description} — \{assertion.detail}",
        )
      }
    }
  }
  @debug.assert_eq(score.tasks, 3)
  @debug.assert_eq(score.tasks_passed, 3)
  @debug.assert_eq(score.assertions_passed, score.assertions)
  @debug.assert_eq(score.repeatable_tasks, 3)
  @debug.assert_eq(score.completion_rate(), 1.0)
  @debug.assert_eq(score.verification_rate(), 1.0)
  @debug.assert_eq(score.repeatability(), 1.0)
  @debug.assert_eq(score.cost_usd, 0.0)
}

///|
async test "harness: a non-allowlisted tool is rejected before execution" {
  let json = "{\"id\":\"escapes-allowlist\",\"goal\":\"\",\"steps\":[{\"tool\":\"terminal\",\"args\":{\"command\":\"echo hi\"}}],\"checks\":[]}"
  let task = match parse_harness_task(json) {
    Some(parsed) => parsed
    None => {
      fail("task json did not parse")
      return
    }
  }
  let report = run_harness_batch([task], harness_test_root(), 1)
  let score = report.score(1)
  @debug.assert_eq(score.tasks_passed, 0)
  @debug.assert_eq(score.assertions_passed, 0)
  @debug.assert_eq(report.results[0].steps_run, 0)
}

///|
test "harness: a document without a task id is not a task" {
  match parse_harness_task("{\"goal\":\"no id\"}") {
    Some(_) => fail("expected None for a task without an id")
    None => ()
  }
}

///|
test "harness: malformed json is not a task" {
  match parse_harness_task("not json at all") {
    Some(_) => fail("expected None for malformed json")
    None => ()
  }
}

///|
async test "harness: score json carries the scoring vector" {
  let tasks = load_harness_tasks(shipped_tasks_dir())
  let report = run_harness_batch(tasks, harness_test_root(), 1)
  let json = report.to_score_json("offline", 1)
  let fields = match json {
    Object(found) => found
    _ => {
      fail("score json is not an object")
      return
    }
  }
  for key in [
    "mode", "trials", "tasks", "tasks_passed", "assertions",
    "assertions_passed", "completion_rate", "verification_rate", "repeatability",
    "cost_usd", "results",
  ] {
    assert_true(fields.contains(key))
  }
}