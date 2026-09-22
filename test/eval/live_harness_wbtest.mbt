///| Tests for the model-driven harness driver (layer 8).
///
/// The driver is exercised through an injected runner, so these tests are
/// deterministic and network-free: they pin the batch mechanics (per-trial
/// sandboxes, repetition, assertion evaluation, scoring, reporting) and the
/// tool-surface restriction, while the model call itself is faked.

///|
/// Sandbox roots must sit one level under `_build/` because `@fs.create_dir`
/// does not create parents.
///
/// They are also absolute: the real runner moves the *process* cwd into the
/// trial sandbox (the file tools resolve relative paths against the process
/// cwd), and `moon test` runs a package's async tests concurrently, so a
/// relative root would be re-anchored by a sibling test mid-run.
fn live_test_root(name : String) -> String {
  let build = @path.Path::join(@utils.current_dir(), @path.Path("_build")).to_string()
  if !@fs.path_exists(build) {
    @fs.create_dir(build) catch {
      _ => ()
    }
  }
  let root = @path.Path::join(build, @path.Path("live_wbtest_\{name}")).to_string()
  if @fs.path_exists(root) {
    @fs.remove_dir(root) catch {
      _ => ()
    }
  }
  @fs.create_dir(root) catch {
    _ => ()
  }
  root
}

///|
fn live_test_task(id : String, prompt : String, trials : Int) -> HarnessTask {
  {
    id,
    goal: "write the marker file",
    seeds: [{ path: "{sandbox}/in.txt", content: "seed", }],
    steps: [],
    checks: [
      { kind: "file_exists", path: "{sandbox}/out.txt", text: "", },
      { kind: "file_contains", path: "{sandbox}/out.txt", text: "done", },
    ],
    prompt,
    acceptance: "out.txt contains done",
    trials,
  }
}

///|
/// A runner that acts like a model which used the `write` tool: it records the
/// sandbox it was handed and materializes the artifact the checks look for.
fn fake_runner(
  seen : Array[String],
  fail : Bool,
) -> async (String, String) -> LiveRunOutcome {
  async fn(_prompt : String, sandbox : String) -> LiveRunOutcome {
    // The injected runner type is async because the real one awaits the model;
    // the fake yields instead of pretending to call anything.
    @async.sleep(0)
    seen.push(sandbox)
    if !fail {
      @fs.write_string_to_file(
        @path.Path::join(sandbox, @path.Path("out.txt")).to_string(),
        "done",
      ) catch {
        _ => ()
      }
    }
    {
      status: if fail {
        "Error"
      } else {
        "Success"
      },
      iterations: 2,
      cost_usd: 0.01,
      cost_source: "Estimated",
      prompt_tokens: 30,
      completion_tokens: 7,
      tool_steps: ["write out.txt"],
      transcript: "assistant: done",
      error: if fail {
        Some("upstream 500")
      } else {
        None
      },
    }
  }
}

///|
async test "live: every trial runs in its own seeded sandbox" {
  let root = live_test_root("basic")
  let seen : Array[String] = []
  let report = run_live_batch(
    [live_test_task("cap-t", "write out.txt", 3)],
    "\{root}/sandbox",
    "\{root}/tx",
    None,
    fake_runner(seen, false),
  )
  @debug.assert_eq(report.results.length(), 3)
  @debug.assert_eq(seen.length(), 3)
  // Distinct directories per trial, and each one keeps its seed.
  assert_true(seen[0] != seen[1] && seen[1] != seen[2])
  for sandbox in seen {
    let seed = @fs.read_file_to_string(
      @path.Path::join(sandbox, @path.Path("in.txt")).to_string(),
    ) catch {
      _ => "seed write failed"
    }
    @debug.assert_eq(seed, "seed")
  }
  for result in report.results {
    @debug.assert_eq(result.passed, true)
    @debug.assert_eq(result.trial >= 1 && result.trial <= 3, true)
  }
  let score = report.as_harness_report().score(3, cost_usd=report.total_cost())
  @debug.assert_eq(score.tasks, 1)
  @debug.assert_eq(score.tasks_passed, 1)
  @debug.assert_eq(score.completion_rate(), 1.0)
  @debug.assert_eq(score.repeatability(), 1.0)
  // Cost is a real sum over trials, not a constant zero.
  assert_true(score.cost_usd > 0.029 && score.cost_usd < 0.031)
  @debug.assert_eq(report.infrastructure_errors(), 0)
}

///|
async test "live: --trials overrides the per-task trials field" {
  let root = live_test_root("override")
  let seen : Array[String] = []
  let report = run_live_batch(
    [live_test_task("cap-t", "write out.txt", 5)],
    "\{root}/sandbox",
    "\{root}/tx",
    Some(2),
    fake_runner(seen, false),
  )
  @debug.assert_eq(report.results.length(), 2)
  @debug.assert_eq(report.nominal_trials, 2)
}

///|
async test "live: trials default to 3 when the task does not set them" {
  let root = live_test_root("default")
  let seen : Array[String] = []
  let report = run_live_batch(
    [live_test_task("cap-t", "write out.txt", 0)],
    "\{root}/sandbox",
    "\{root}/tx",
    None,
    fake_runner(seen, false),
  )
  @debug.assert_eq(report.results.length(), 3)
}

///|
async test "live: a failing trial is reported, not hidden, and the batch continues" {
  let root = live_test_root("failure")
  let seen : Array[String] = []
  let report = run_live_batch(
    [live_test_task("cap-fail", "write out.txt", 2)],
    "\{root}/sandbox",
    "\{root}/tx",
    None,
    fake_runner(seen, true),
  )
  @debug.assert_eq(report.results.length(), 2)
  for result in report.results {
    @debug.assert_eq(result.passed, false)
    @debug.assert_eq(result.outcome.status, "Error")
    @debug.assert_eq(result.outcome.error, Some("upstream 500"))
  }
  @debug.assert_eq(report.infrastructure_errors(), 2)
  let score = report.as_harness_report().score(2, cost_usd=report.total_cost())
  @debug.assert_eq(score.tasks_passed, 0)
  @debug.assert_eq(score.completion_rate(), 0.0)
}

///|
async test "live: a task without a prompt is an infrastructure failure" {
  let root = live_test_root("noprompt")
  let seen : Array[String] = []
  let report = run_live_batch(
    [live_test_task("cap-noprompt", "", 1)],
    "\{root}/sandbox",
    "\{root}/tx",
    None,
    fake_runner(seen, false),
  )
  @debug.assert_eq(seen.length(), 0)
  @debug.assert_eq(report.infrastructure_errors(), 1)
  @debug.assert_eq(report.results[0].passed, false)
  let mut named = false
  for assertion in report.results[0].assertions {
    if !assertion.passed && assertion.description.contains("declares a prompt") {
      named = true
    }
  }
  @debug.assert_eq(named, true)
}

///|
async test "live: transcripts are persisted per trial" {
  let root = live_test_root("transcript")
  let seen : Array[String] = []
  let report = run_live_batch(
    [live_test_task("cap-tx", "write out.txt", 2)],
    "\{root}/sandbox",
    "\{root}/tx",
    None,
    fake_runner(seen, false),
  )
  for result in report.results {
    assert_true(@fs.path_exists(result.transcript_path))
    let text = @fs.read_file_to_string(result.transcript_path) catch { _ => "" }
    assert_true(text.contains("acceptance: out.txt contains done"))
    assert_true(text.contains("tool calls"))
  }
}

///|
async test "live: the score json carries the live-only detail" {
  let root = live_test_root("json")
  let seen : Array[String] = []
  let report = run_live_batch(
    [live_test_task("cap-json", "write out.txt", 1)],
    "\{root}/sandbox",
    "\{root}/tx",
    None,
    fake_runner(seen, false),
  )
  let fields = match report.to_score_json("live", 1) {
    Object(found) => found
    _ => {
      fail("score json is not an object")
      return
    }
  }
  for
    key in [
      "mode", "trials", "tasks", "tasks_passed", "assertions", "assertions_passed",
      "completion_rate", "verification_rate", "repeatability", "cost_usd", "results",
      "infrastructure_errors", "prompt_tokens", "completion_tokens", "cost_source",
      "trials_detail",
    ] {
    assert_true(fields.contains(key))
  }
  let markdown = report.to_markdown("live", 1)
  assert_true(markdown.contains("基础设施失败 trial 数"))
  assert_true(markdown.contains("cap-json · trial 1"))
}

///|
/// The live registry must expose exactly the offline allowlist. Under
/// `auto_approve` everything registered executes without confirmation, so a
/// leaked `terminal` entry would hand the model a shell on the host.
test "live: the tool surface is narrowed to the allowlist" {
  let registry = live_registry()
  for name in live_tool_allowlist {
    assert_true(registry.get_resolved(name) is Some(_))
  }
  for forbidden in ["terminal", "shell", "bash", "web_fetch", "web_search"] {
    @debug.assert_eq(registry.get_resolved(forbidden), None)
  }
  @debug.assert_eq(registry.size(), live_tool_allowlist.length())
}

///|
/// The shipped capability task set must stay complete: a task without a prompt,
/// acceptance criterion or checks would quietly weaken every later run (and the
/// plan requires the set to only grow, never shrink).
async test "live: the shipped capability task set is complete" {
  let dir = @path.Path::join(
    @utils.current_dir(),
    @path.Path("test/capability/tasks"),
  ).to_string()
  let tasks = load_harness_tasks(dir)
  @debug.assert_eq(tasks.length(), 4)
  let ids : Array[String] = []
  for task in tasks {
    assert_true(task.prompt != "")
    assert_true(task.acceptance != "")
    assert_true(task.checks.length() > 0)
    assert_true(task.seeds.length() > 0)
    assert_true(!ids.contains(task.id))
    assert_true(task.trials > 0)
    ids.push(task.id)
  }
}
