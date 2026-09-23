///|
/// Journey runner core (Layer 9): executes one journey inside a task group
/// with the mock upstream, sandbox, and watchdogs; accumulates assertion
/// results; builds the UnifiedReport for the batch.

///|
/// Batch-level runner options.
pub(all) struct JourneyOptions {
  /// Substring filter on scenario ids (empty = run all).
  filter : String
  /// Keep evidence bundles for green journeys too.
  keep_all : Bool
  /// Print live progress lines (manual runs).
  verbose : Bool
}

///|
/// Per-journey outcome: reporting + ledger input.
pub(all) struct JourneyOutcome {
  scenario_id : String
  area : String
  title : String
  description : String
  passed : Bool
  error : String
  duration_ms : Double
  /// Evidence bundle dir relative to the repo ("" when none kept).
  evidence_dir : String
  /// Individual assertion results (steps + final).
  assertions : Array[@eval.EvalAssertionResult]
}

///|
/// Mutable per-journey execution state shared by the step drivers.
pub(all) struct JourneyState {
  ctx : JourneyContext
  mock : @e2e.MockLlmServer
  /// Current child process (server or CLI).
  mut child : ChildHandle?
  /// Current WebSocket journal (web journeys).
  mut journal : WsJournal?
  /// TUI simulator (tui journeys).
  mut tui : @test_tui.TuiEvalSimulator?
  /// Last HTTP response (web steps).
  mut last_http_status : Int
  mut last_http_body : String
  mut last_http_headers : Array[(String, String)]
  /// Last exited child's outputs (cli/persistence steps).
  mut last_exit_code : Int?
  mut last_stdout : String
  mut last_stderr : String
  /// Per-child output log for evidence: (label, exit, stdout, stderr).
  child_outputs : Array[(String, Int, String, String)]
  /// REST request log (one JSON object per line, evidence).
  rest_log : Array[String]
  /// Accumulated assertion results.
  assertions : Array[@eval.EvalAssertionResult]
  /// Fatal step error (aborts remaining steps).
  mut error : String
  /// Phase/step trace (evidence + failure localization).
  trace : Array[String]
  /// TUI screenshot counter for evidence naming.
  mut screenshot_count : Int
  /// Scenario permission mode (drives the in-process TUI agent config).
  mut permission_mode : String
  /// Number of TuiState.messages already mirrored into the output buffer
  /// (headless stand-in for the controller's AgentOutputSync).
  mut tui_messages_synced : Int
}

///|
fn new_journey_state(
  ctx : JourneyContext,
  mock : @e2e.MockLlmServer,
  permission_mode : String,
) -> JourneyState {
  let state : JourneyState = {
    ctx,
    mock,
    child: None,
    journal: None,
    tui: None,
    last_http_status: 0,
    last_http_body: "",
    last_http_headers: [],
    last_exit_code: None,
    last_stdout: "",
    last_stderr: "",
    child_outputs: [],
    rest_log: [],
    assertions: [],
    error: "",
    trace: [],
    screenshot_count: 0,
    permission_mode,
    tui_messages_synced: 0,
  }
  state
}

///|
/// Record a child's final output into the state (called by wait/kill paths).
fn record_child_output(
  state : JourneyState,
  label : String,
  code : Int,
  stdout : String,
  stderr : String,
) -> Unit {
  state.last_exit_code = Some(code)
  state.last_stdout = stdout
  state.last_stderr = stderr
  state.child_outputs.push((label, code, stdout, stderr))
}

///|
/// Execute one step; fatal errors set state.error and stop the journey.
async fn execute_step(
  group : @async.TaskGroup[Unit],
  state : JourneyState,
  phase_name : String,
  step : JourneyStep,
) -> Unit {
  if state.error.length() > 0 {
    return
  }
  match step.action {
    SpawnServer => spawn_server_step(group, state, phase_name)
    Http(verb~, path~, body~, capture~, headers~, timeout_ms~) =>
      http_step(
        state, verb, path, body, capture, headers, timeout_ms, phase_name,
      )
    WsConnect(url~) => ws_connect_step(group, state, url, phase_name)
    WsSend(frame~) => ws_send_step(state, frame, phase_name)
    WsWaitEvent(event~, timeout_ms~) =>
      ws_wait_event_step(state, event, timeout_ms, phase_name)
    KillChild => kill_child_step(state, phase_name)
    SpawnCli(message~, json_output~, mode~, cont~, extra_args~) =>
      spawn_cli_step(
        group, state, message, json_output, mode, cont, extra_args, phase_name,
      )
    SpawnBin(args~) => spawn_bin_step(group, state, args, phase_name)
    WaitChild(timeout_ms~, capture~) =>
      wait_child_step(state, timeout_ms, capture, phase_name)
    KillChildMidRun(after_mock_request~) =>
      kill_child_mid_run_step(state, after_mock_request, phase_name)
    TuiNew(cols~, rows~) => tui_new_step(group, state, cols, rows, phase_name)
    TuiType(text~) => tui_type_step(state, text, phase_name)
    TuiPress(key~) => tui_press_step(state, key, phase_name)
    TuiSend(text~, timeout_ms~) =>
      tui_send_step(group, state, text, timeout_ms, phase_name)
    TuiScreenshot(name~) => tui_screenshot_step(state, name, phase_name)
    Assert(assertions~) =>
      for kind in assertions {
        let result = evaluate_journey_assertion(state, kind)
        state.assertions.push(result)
        if !result.passed {
          state.trace.push(
            "assert failed (\{phase_name}): \{result.description} — \{result.detail}",
          )
        }
      }
  }
}

///|
/// Teardown: kill any surviving child, close the ws connection. The
/// journal object stays in state — its recorded frames feed the final
/// assertions and the evidence bundle after teardown.
async fn teardown_journey(state : JourneyState) -> Unit {
  match state.journal {
    Some(j) => j.close()
    None => ()
  }
  match state.child {
    Some(child) => {
      let (code, stdout, stderr) = child.kill_and_collect()
      record_child_output(state, child.label, code, stdout, stderr)
      state.child = None
    }
    None => ()
  }
}

///|
/// Run one journey scenario. Timeout is enforced INSIDE the task group
/// (scenario_runner pattern) so mock.shutdown() always runs.
async fn run_single_journey(
  scenario : JourneyScenario,
  repo_abs : String,
  bin_path : String,
  stamp : String,
  options : JourneyOptions,
) -> JourneyOutcome {
  let start_ms = @agent.current_time_ms()
  // Holder filled by the happy path; empty id marks "group aborted".
  let outcome_holder = Ref({
    scenario_id: "",
    area: scenario.area,
    title: scenario.title,
    description: scenario.description,
    passed: false,
    error: "",
    duration_ms: 0.0,
    evidence_dir: "",
    assertions: [],
  })
  @async.with_task_group(async fn(group) {
    let port = choose_free_port(scenario.server_port)
    let ctx = create_journey_context(
      repo_abs,
      bin_path,
      scenario.id,
      stamp,
      port,
    )
    let mock = @e2e.MockLlmServer::new(scenario.llm_steps)
    group.spawn_bg(async fn() { mock.serve() })
    write_seed_config(ctx, mock.port(), scenario.permission_mode)
    seed_workspace_files(ctx, scenario.seed)
    let state = new_journey_state(ctx, mock, scenario.permission_mode)
    // Phases/steps under the journey watchdog.
    match
      @async.with_timeout_opt(scenario.timeout_ms, () => {
        for phase in scenario.phases {
          state.trace.push("phase: \{phase.name}")
          for step in phase.steps {
            execute_step(group, state, phase.name, step)
            if state.error.length() > 0 {
              break
            }
          }
          if state.error.length() > 0 {
            break
          }
        }
      }) {
      Some(_) => ()
      None =>
        state.error = "journey timed out after \{scenario.timeout_ms}ms (killed)"
    }
    // Always teardown and shut down the mock, timeout or not.
    teardown_journey(state)
    mock.shutdown()
    // Final assertions (filesystem/state checks; stable post-teardown).
    for kind in scenario.assertions {
      state.assertions.push(evaluate_journey_assertion(state, kind))
    }
    let passed = state.error.is_empty() &&
      state.assertions.length() > 0 &&
      state.assertions.all(fn(a) { a.passed })
    // Evidence is always written; retention removes it for green runs.
    write_journey_evidence(state, scenario.id, passed, state.error)
    if passed && !options.keep_all {
      remove_journey_dir(ctx)
    }
    let duration_ms = (@agent.current_time_ms() - start_ms).to_double()
    let evidence_dir = if passed && !options.keep_all {
      ""
    } else {
      "\{ctx.run_dir}"
    }
    outcome_holder.val = {
      scenario_id: scenario.id,
      area: scenario.area,
      title: scenario.title,
      description: scenario.description,
      passed,
      error: state.error,
      duration_ms,
      evidence_dir,
      assertions: state.assertions,
    }
  })
  let duration_ms = (@agent.current_time_ms() - start_ms).to_double()
  let outcome = outcome_holder.val
  // A task-group crash aborts before the holder is filled: fall back.
  if outcome.scenario_id.length() == 0 {
    {
      scenario_id: scenario.id,
      area: scenario.area,
      title: scenario.title,
      description: scenario.description,
      passed: false,
      error: "journey aborted unexpectedly",
      duration_ms,
      evidence_dir: "",
      assertions: [],
    }
  } else {
    outcome
  }
}

///|
/// Load journey files (with names) from a directory.
fn load_journey_files(dir_path : String) -> Array[(String, String)] {
  let out : Array[(String, String)] = []
  let entries = @fs.read_dir(dir_path) catch { _ => return out }
  for name in entries {
    let path = @path.Path::join(@path.Path(dir_path), @path.Path(name)).to_string()
    if path.has_suffix(".json") {
      let content = @fs.read_file_to_string(path) catch { _ => continue }
      out.push((name, content))
    }
  }
  out
}

///|
/// Run a batch of journey scenarios and produce the unified report.
pub async fn run_journey_batch(
  repo_abs : String,
  scenarios_dir : String,
  bin_path : String,
  options : JourneyOptions,
) -> (@eval.UnifiedReport, Array[JourneyOutcome]) {
  let stamp = journey_stamp_now()
  let outcomes : Array[JourneyOutcome] = []
  for entry in load_journey_files(scenarios_dir) {
    let (filename, text) = entry
    let outcome = match parse_journey_scenario(text) {
      Ok(scenario) => {
        if options.filter.length() > 0 && !scenario.id.contains(options.filter) {
          continue
        }
        if options.verbose {
          println("journey: \{scenario.id} (\{scenario.area}) ...")
        }
        run_single_journey(scenario, repo_abs, bin_path, stamp, options)
      }
      Err(msg) =>
        // A broken scenario file is a failed journey, not a silent skip.
        {
          scenario_id: filename,
          area: "(parse)",
          title: filename,
          description: "scenario file failed to parse",
          passed: false,
          error: msg,
          duration_ms: 0.0,
          evidence_dir: "",
          assertions: [],
        }
    }
    outcomes.push(outcome)
    if options.verbose {
      let status = if outcome.passed { "PASS" } else { "FAIL" }
      println(
        "journey: \{outcome.scenario_id} \{status}\{if outcome.error.length() > 0 { " — " + outcome.error } else { "" }}",
      )
    }
  }
  let results : Array[@eval.UnifiedSuiteResult] = []
  let mut passed_count = 0
  for o in outcomes {
    if o.passed {
      passed_count = passed_count + 1
    }
    let assertions : Array[@eval.UnifiedAssertionResult] = []
    for a in o.assertions {
      let ua : @eval.UnifiedAssertionResult = {
        description: a.description,
        passed: a.passed,
        detail: a.detail,
      }
      assertions.push(ua)
    }
    results.push({
      name: o.scenario_id,
      passed: o.passed,
      assertions,
      error: o.error,
      duration_ms: o.duration_ms,
      metadata: Json::object({
        "area": o.area.to_json(),
        "title": o.title.to_json(),
        "description": o.description.to_json(),
        "evidence_dir": o.evidence_dir.to_json(),
      }),
    })
  }
  let report : @eval.UnifiedReport = {
    suite_name: "journey",
    kind: @eval.UnifiedTestKind::Journey,
    timestamp: stamp,
    results,
    summary: {
      total: outcomes.length(),
      passed: passed_count,
      failed: outcomes.length() - passed_count,
    },
  }
  (report, outcomes)
}

///|
/// Remove a journey run dir (evidence + sandbox) — green-run retention.
/// Recursive, best-effort; failures are ignored.
fn remove_journey_dir(ctx : JourneyContext) -> Unit {
  remove_dir_recursive(ctx.run_dir)
}

///|
fn remove_dir_recursive(dir : String) -> Unit {
  let entries = @fs.read_dir(dir) catch { _ => return }
  for entry in entries {
    let path = "\{dir}/\{entry}"
    let is_dir : Bool = @fs.is_dir(path) catch { _ => false }
    if is_dir {
      remove_dir_recursive(path)
    } else {
      @fs.remove_file(path) catch {
        _ => ()
      }
    }
  }
  @fs.remove_dir(dir) catch {
    _ => ()
  }
}
