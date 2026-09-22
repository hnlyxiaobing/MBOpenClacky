///| `cmd eval` — Agent capability evaluation (P2 / G1).
///
/// `--offline` drives the deterministic tool harness in `test/eval/tasks/`
/// through the real tool registry: no model, no network, reproducible scoring.
/// Tasks are run `--trials` times (default 2, i.e. the plan's 3×2 batch) so
/// repeatability is measured rather than assumed.
///
/// stdout carries exactly one JSON object — the score vector — so a contract
/// probe can assert its shape. The human-readable report goes to
/// `_build/eval/<date>.md` (overridable with `--out`): the offline run is a
/// repeatable gate, so it keeps its artifact out of the worktree.
///
/// `--live` is the model-driven path. It is **not wired in this build**: it
/// exits 1 with an actionable message and is registered as `open` in
/// `docs/known-gaps.md` ("harness 就绪、真模型未执行", decision D1 fallback).

///|
/// Create (if needed) `<repo>/_build/eval_sandbox` and return it. A fresh clone
/// has no `_build/`, and `@fs.create_dir` does not create parents, so the two
/// levels are created explicitly.
fn eval_sandbox_root(repo : String) -> String {
  let build_dir = @path.Path::join(repo, @path.Path("_build")).to_string()
  if !@fs.path_exists(build_dir) {
    @fs.create_dir(build_dir) catch {
      _ => ()
    }
  }
  let root = @path.Path::join(build_dir, @path.Path("eval_sandbox")).to_string()
  if !@fs.path_exists(root) {
    @fs.create_dir(root) catch {
      _ => ()
    }
  }
  root
}

///|
/// Metadata attached to the score JSON so stdout stays a single JSON document.
fn eval_attach_report_path(json : Json, path : String) -> Json {
  match json {
    Object(fields) => {
      fields["report_path"] = path.to_json()
      Json::object(fields)
    }
    other => other
  }
}

///|
/// Interpret a `--offline` / `--live` selection. Returns None when the two are
/// contradictory.
fn eval_mode(sub : @clap.SimpleValue) -> Bool? {
  let offline = sub.get_flag("offline") == Some(true)
  let live = sub.get_flag("live") == Some(true)
  if offline && live {
    None
  } else if live {
    Some(false)
  } else {
    Some(true)
  }
}

///|
async fn handle_eval(sub : @clap.SimpleValue) -> Unit {
  let repo = get_named_arg(sub, "repo").unwrap_or(".")
  let mode = match eval_mode(sub) {
    Some(offline) => offline
    None => {
      println("eval: --offline and --live are mutually exclusive")
      @sys.exit(2)
      return
    }
  }
  if !mode {
    println(
      "eval --live: the model-driven path is not implemented in this build;",
    )
    println(
      "  the deterministic harness is available now:  mbopenclacky eval --offline --repo .",
    )
    println(
      "  Status is registered in docs/known-gaps.md (真模型评测波动: harness 就绪、真模型未执行).",
    )
    @sys.exit(1)
    return
  }
  let trials = match get_named_arg(sub, "trials") {
    Some(text) => @string.parse_int(text.trim()) catch { _ => 2 }
    None => 2
  }
  if trials <= 0 {
    println("eval: --trials must be >= 1")
    @sys.exit(2)
    return
  }
  let tasks_dir = match get_named_arg(sub, "tasks") {
    Some(dir) => dir
    None => @path.Path::join(repo, @path.Path("test/eval/tasks")).to_string()
  }
  let tasks = @eval.load_harness_tasks(tasks_dir)
  if tasks.length() == 0 {
    println("eval: no task files found in \{tasks_dir}")
    @sys.exit(1)
    return
  }
  let sandbox_root = eval_sandbox_root(repo)
  let report = @eval.run_harness_batch(tasks, sandbox_root, trials)
  let score = report.score(trials)
  // Human-readable report. The offline run is a repeatable gate, so its report
  // defaults under _build/ and leaves the worktree clean; a live run (whose
  // evidence is worth committing) is expected to default to docs/eval/ once
  // that path is wired. `--out <dir>` overrides either default.
  let out_dir = match get_named_arg(sub, "out") {
    Some(dir) => dir
    None => @path.Path::join(repo, @path.Path("_build/eval")).to_string()
  }
  let stamp = @agent.ms_to_iso8601(@agent.current_time_ms())
  let date = if stamp.length() >= 10 {
    stamp[:10].to_owned()
  } else {
    "unknown"
  }
  let report_path = @path.Path::join(out_dir, @path.Path("\{date}.md")).to_string()
  if !@fs.path_exists(out_dir) {
    @fs.create_dir(out_dir) catch {
      _ => ()
    }
  }
  let markdown = report.to_markdown("offline", trials)
  @fs.write_string_to_file(report_path, markdown) catch {
    err => println("eval: could not write report: \{@debug.to_string(err)}")
  }
  // stdout = the score vector, and nothing else.
  println(
    eval_attach_report_path(
      report.to_score_json("offline", trials),
      report_path,
    ).stringify(),
  )
  let clean = score.tasks == score.tasks_passed &&
    score.assertions == score.assertions_passed &&
    score.repeatable_tasks == score.tasks
  if !clean {
    @sys.exit(1)
  }
}
