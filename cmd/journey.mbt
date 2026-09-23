///| `cmd journey` — user-journey E2E runner (Layer 9).
///
/// Drives the REAL compiled binary through complete user journeys (web WS
/// chat, TUI interaction, CLI one-shot tasks, session persistence across
/// restarts) against a scripted mock LLM upstream, with sandboxed
/// per-journey homes, three-level watchdogs, evidence bundles under
/// `_build/journey/`, and a committed failure ledger.
///
/// Exit codes (stable for schedulers):
///   0 = all journeys green   1 = ≥1 journey failed (product red)
///   2 = usage error          3 = infrastructure error (runner broken)

///|
/// Resolve the binary under test: `--bin` flag > release build output.
fn journey_resolve_bin(sub : @clap.SimpleValue, repo : String) -> String? {
  match get_named_arg(sub, "bin") {
    Some(bin) => Some(bin)
    None => detect_binary(repo)
  }
}

///|
/// Fail-fast probe: the binary must at least report its version. Distingu
/// ishes "runner broken" (exit 3) from "product red" (exit 1).
async fn journey_probe_bin(bin : String) -> Bool {
  match
    @async.with_timeout_opt(10_000, () => {
      let (code, _out, _err) = @process.collect_output(bin, ["--version"])
      code
    }) {
    Some(code) => code == 0
    None => false
  }
}

///|
async fn handle_journey(sub : @clap.SimpleValue) -> Unit {
  let repo_arg = get_named_arg(sub, "repo").unwrap_or(".")
  // Absolute: scheduled runs must not depend on the invoking CWD.
  let repo_abs = @path.Path::resolve(@path.Path(repo_arg)).to_string()
  // ── Binary under test ──────────────────────────────────────────────
  let bin = match journey_resolve_bin(sub, repo_abs) {
    Some(bin) => bin
    None => {
      println(
        "journey: release binary not found — run `moon build --target native --release cmd` first (or pass --bin)",
      )
      @sys.exit(3)
      return
    }
  }
  if !journey_probe_bin(bin) {
    println("journey: binary probe failed: \{bin} --version")
    @sys.exit(3)
    return
  }
  // ── Scenarios ──────────────────────────────────────────────────────
  let scenarios_dir = match get_named_arg(sub, "scenarios") {
    Some(dir) => dir
    None =>
      @path.Path::join(
        @path.Path(repo_abs),
        @path.Path("test/journey/scenarios"),
      ).to_string()
  }
  if !@fs.path_exists(scenarios_dir) {
    println("journey: scenarios directory not found: \{scenarios_dir}")
    @sys.exit(2)
    return
  }
  let filter = get_named_arg(sub, "filter").unwrap_or("")
  let keep_all = sub.get_flag("keep-all") == Some(true)
  let verbose = sub.get_flag("verbose") == Some(true)
  let format = parse_output_format(sub)
  let out_dir = match get_named_arg(sub, "out") {
    Some(dir) => dir
    None =>
      @path.Path::join(@path.Path(repo_abs), @path.Path("_build/journey")).to_string()
  }
  let options : @test_journey.JourneyOptions = { filter, keep_all, verbose, }
  // ── Run ─────────────────────────────────────────────────────────────
  let (report, outcomes) = @test_journey.run_journey_batch(
    repo_abs, scenarios_dir, bin, options,
  )
  // ── Report ─────────────────────────────────────────────────────────
  let report_path = write_unified_report(report, format, out_dir, "journey")
  if format == "json" {
    println(
      eval_attach_report_path(
        @eval.render_unified_report_json(report),
        report_path,
      ).stringify(),
    )
  } else if format == "markdown" {
    println(@eval.render_unified_report_markdown(report))
  } else {
    println(@eval.render_unified_report_text(report))
  }
  println("")
  println("Report saved to: \{report_path}")
  // Failure evidence pointers (visible without opening the report).
  for o in outcomes {
    if !o.passed && o.evidence_dir.length() > 0 {
      println("Evidence: \{o.evidence_dir}")
    }
  }
  // ── Ledger (task: docs/journey-failures.md maintenance) ─────────────
  journey_update_ledger(repo_abs, outcomes)
  if report.summary.failed > 0 {
    @sys.exit(1)
  }
}

///|
/// Update the committed failure ledger from this run's outcomes.
/// Open failures are upserted; scenarios that went green close their open
/// entries (the fix loop). Ledger write failures never affect exit codes.
fn journey_update_ledger(
  repo_abs : String,
  outcomes : Array[@test_journey.JourneyOutcome],
) -> Unit {
  let ledger_path = @path.Path::join(
    @path.Path(repo_abs),
    @path.Path("docs/journey-failures.md"),
  ).to_string()
  @test_journey.ensure_journey_ledger(ledger_path)
  match @test_journey.update_journey_ledger(ledger_path, outcomes, repo_abs~) {
    Ok(true) =>
      println("Ledger updated: docs/journey-failures.md (git diff to review)")
    Ok(false) => ()
    Err(msg) => println("journey: ledger update failed: \{msg}")
  }
}
