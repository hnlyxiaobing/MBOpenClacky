///| `cmd eval` — Unified evaluation runner.
///
/// Dispatches to one of four eval backends based on flags:
///   --tui <dir>     → TUI headless eval (test/tui)
///   --web <dir>     → Web API eval (test/web)
///   --offline       → Deterministic tool harness (test/eval/tool_harness)
///   --live          → Model-driven capability benchmark (test/eval/live_harness)
///
/// All backends produce a unified report via the shared renderers in eval_engine.
/// `--format` selects output: text (default), json, markdown.

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
fn parse_output_format(sub : @clap.SimpleValue) -> String {
  match get_named_arg(sub, "format") {
    Some(f) => {
      let trimmed = f.trim().to_owned().to_lower()
      if trimmed == "json" || trimmed == "markdown" {
        trimmed
      } else {
        "text"
      }
    }
    None => "text"
  }
}

///|
fn write_unified_report(
  report : @eval.UnifiedReport,
  format : String,
  out_dir : String,
  suite_name : String,
) -> String {
  let stamp = @agent.ms_to_iso8601(@agent.current_time_ms())
  let date = if stamp.length() >= 10 {
    stamp[:10].to_owned()
  } else {
    "unknown"
  }
  let ext = if format == "json" {
    "json"
  } else if format == "markdown" {
    "md"
  } else {
    "txt"
  }
  let report_path = @path.Path::join(
    out_dir,
    @path.Path("\{suite_name}_\{date}.\{ext}"),
  ).to_string()
  if !@fs.path_exists(out_dir) {
    @fs.create_dir(out_dir) catch {
      _ => ()
    }
  }
  let content = if format == "json" {
    @eval.render_unified_report_json(report).stringify()
  } else if format == "markdown" {
    @eval.render_unified_report_markdown(report)
  } else {
    @eval.render_unified_report_text(report)
  }
  @fs.write_string_to_file(report_path, content) catch {
    err => println("eval: could not write report: \{@debug.to_string(err)}")
  }
  report_path
}

///|
async fn handle_eval(sub : @clap.SimpleValue) -> Unit {
  let repo = get_named_arg(sub, "repo").unwrap_or(".")
  let format = parse_output_format(sub)
  let out_dir = match get_named_arg(sub, "out") {
    Some(dir) => dir
    None => @path.Path::join(repo, @path.Path("_build/eval")).to_string()
  }
  // ── TUI eval ──────────────────────────────────────────────────────────
  match get_named_arg(sub, "tui") {
    Some(dir) => {
      println("Running TUI eval scenarios from: \{dir}")
      let batch = @test_tui.run_eval_scenarios(dir)
      let report = batch.to_unified_report(suite_name="tui")
      let report_path = write_unified_report(report, format, out_dir, "tui")
      if format == "json" {
        println(
          eval_attach_report_path(
            @eval.render_unified_report_json(report),
            report_path,
          ).stringify(),
        )
      } else {
        println(@eval.render_unified_report_text(report))
      }
      println("")
      println("Report saved to: \{report_path}")
      if batch.failed_count > 0 {
        @sys.exit(1)
      }
      return
    }
    None => ()
  }
  // ── Web eval ──────────────────────────────────────────────────────────
  match get_named_arg(sub, "web") {
    Some(dir) => {
      println("Running Web API eval scenarios from: \{dir}")
      let batch = @test_web.run_web_eval_scenarios(dir)
      let report = batch.to_unified_report(suite_name="web")
      let report_path = write_unified_report(report, format, out_dir, "web")
      if format == "json" {
        println(
          eval_attach_report_path(
            @eval.render_unified_report_json(report),
            report_path,
          ).stringify(),
        )
      } else {
        println(@eval.render_unified_report_text(report))
      }
      println("")
      println("Report saved to: \{report_path}")
      if batch.failed_count > 0 {
        @sys.exit(1)
      }
      return
    }
    None => ()
  }
  // ── Harness offline / live ────────────────────────────────────────────
  let mode = match eval_mode(sub) {
    Some(offline) => offline
    None => {
      println("eval: --offline and --live are mutually exclusive")
      @sys.exit(2)
      return
    }
  }
  if !mode {
    run_live_eval(repo, sub)
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
  let tasks = if @fs.path_exists(tasks_dir) {
    @eval.load_harness_tasks(tasks_dir)
  } else {
    []
  }
  if tasks.length() == 0 {
    println("eval: no task files found in \{tasks_dir}")
    @sys.exit(1)
    return
  }
  let sandbox_root = eval_sandbox_root(repo)
  let report = @eval.run_harness_batch(tasks, sandbox_root, trials)
  let score = report.score(trials)
  // Human-readable report. The offline run is a repeatable gate, so its report
  // defaults under _build/ and leaves the worktree clean; the live run (whose
  // evidence is worth committing) defaults to docs/eval/ instead. `--out`
  // overrides either default.
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
