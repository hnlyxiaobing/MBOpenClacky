///|
/// Journey E2E scenario model (Layer 9, `cmd journey`).
///
/// A journey drives the REAL compiled binary through a complete user flow:
/// multiple phases, each a sequence of steps (spawn child processes, HTTP
/// requests over real sockets, WebSocket frames, TUI simulator actions),
/// with mock-upstream LLM scripting reused verbatim from test/e2e.

///|
/// One executable step inside a journey phase.
pub(all) enum StepAction {
  /// Spawn the web server child: `bin server --host 127.0.0.1 --port {port}`.
  SpawnServer
  /// One HTTP request over a real socket. `capture` names a top-level
  /// response JSON field stored as a `{capture:<name>}` placeholder.
  Http(
    verb~ : String,
    path~ : String,
    body~ : String,
    capture~ : String,
    headers~ : Array[(String, String)],
    timeout_ms~ : Int
  )
  /// Open the WebSocket journal connection (url may use `{port}`).
  WsConnect(url~ : String)
  /// Send a JSON frame over the WebSocket connection.
  WsSend(frame~ : Json)
  /// Block until an event with the given `type_name()` is journaled.
  WsWaitEvent(event~ : String, timeout_ms~ : Int)
  /// Terminate the current child process (hard kill).
  KillChild
  /// Spawn a CLI child: `bin -m <message> ...` (or `--continue` when cont).
  SpawnCli(
    message~ : String,
    json_output~ : Bool,
    mode~ : String,
    cont~ : Bool,
    extra_args~ : Array[String]
  )
  /// Spawn the binary with arbitrary args (e.g. `inspect <file>`,
  /// `--version`). Args go through placeholder expansion.
  SpawnBin(args~ : Array[String])
  /// Wait for the current CLI child to exit and collect its output.
  /// `capture` names a field extracted from the last stdout JSON line
  /// (e.g. session_id) into a `{capture:<name>}` placeholder.
  WaitChild(timeout_ms~ : Int, capture~ : String)
  /// Hard-kill the child after mock upstream request N arrives (crash sim).
  KillChildMidRun(after_mock_request~ : Int)
  /// Create the in-process TUI simulator (real agent, mock upstream).
  TuiNew(cols~ : Int, rows~ : Int)
  /// Type text into the simulator input area.
  TuiType(text~ : String)
  /// Press a special key in the simulator.
  TuiPress(key~ : String)
  /// Submit a message through the REAL ReAct loop (mock upstream).
  TuiSend(text~ : String, timeout_ms~ : Int)
  /// Capture a simulator screenshot into the evidence bundle.
  TuiScreenshot(name~ : String)
  /// Evaluate assertions against the current journey context.
  Assert(assertions~ : Array[@eval.AssertionKind])
}

///|
pub(all) struct JourneyStep {
  action : StepAction
}

///|
pub(all) struct JourneyPhase {
  name : String
  steps : Array[JourneyStep]
}

///|
pub(all) struct JourneyScenario {
  /// Stable scenario identifier (ledger key).
  id : String
  title : String
  /// Journey area: "web" | "cli" | "tui".
  area : String
  /// Human-readable journey description (goes into failure records).
  description : String
  /// Journey-level watchdog timeout in ms.
  timeout_ms : Int
  /// Advisory web server port (runner probes and retries on conflict).
  server_port : Int
  /// Permission mode seeded into the sandbox config
  /// ("auto_approve" | "confirm_safes" | "confirm_all").
  permission_mode : String
  /// Workspace seed files {relative path: content}.
  seed : Array[(String, String)]
  /// Mock LLM upstream script steps (MockLlmServer replay format, verbatim).
  llm_steps : Array[Json]
  /// Ordered phases of the journey.
  phases : Array[JourneyPhase]
  /// Final assertions evaluated after the last phase.
  assertions : Array[@eval.AssertionKind]
}

// ── JSON helpers (local, non-deprecated wrappers) ───────────────────────────

///|
fn get_str(fields : Map[String, Json], key : String) -> String {
  match fields.get(key) {
    Some(String(s)) => s
    _ => ""
  }
}

///|
fn get_int(fields : Map[String, Json], key : String, default : Int) -> Int {
  match fields.get(key) {
    Some(Number(n, ..)) => n.to_int()
    _ => default
  }
}

///|
fn get_bool(fields : Map[String, Json], key : String) -> Bool {
  match fields.get(key) {
    Some(True) => true
    _ => false
  }
}

///|
/// Parse one step object into a StepAction.
fn parse_step_action(fields : Map[String, Json]) -> Result[StepAction, String] {
  let action = get_str(fields, "action")
  if action.is_empty() {
    return Err("step missing \"action\"")
  }
  match action {
    "spawn_server" => Ok(SpawnServer)
    "http" => {
      let headers : Array[(String, String)] = []
      match fields.get("headers") {
        Some(Array(items)) =>
          for item in items {
            if item is Object(h) {
              let name = get_str(h, "name")
              let value = get_str(h, "value")
              if !name.is_empty() {
                headers.push((name, value))
              }
            }
          }
        _ => ()
      }
      Ok(
        Http(
          verb=get_str(fields, "method"),
          path=get_str(fields, "path"),
          body=get_str(fields, "body"),
          capture=get_str(fields, "capture"),
          headers~,
          timeout_ms=get_int(fields, "timeout_ms", 10_000),
        ),
      )
    }
    "ws_connect" => Ok(WsConnect(url=get_str(fields, "url")))
    "ws_send" =>
      match fields.get("frame") {
        Some(frame) =>
          if frame is Object(_) {
            Ok(WsSend(frame~))
          } else {
            Err("ws_send requires a JSON object \"frame\"")
          }
        None => Err("ws_send requires a JSON object \"frame\"")
      }
    "ws_wait_event" =>
      Ok(
        WsWaitEvent(
          event=get_str(fields, "event"),
          timeout_ms=get_int(fields, "timeout_ms", 10_000),
        ),
      )
    "kill_child" => Ok(KillChild)
    "spawn_cli" => {
      let extra_args : Array[String] = []
      match fields.get("extra_args") {
        Some(Array(items)) =>
          for item in items {
            if item is String(s) {
              extra_args.push(s)
            }
          }
        _ => ()
      }
      Ok(
        SpawnCli(
          message=get_str(fields, "message"),
          json_output=get_bool(fields, "json"),
          mode=get_str(fields, "mode"),
          cont=get_bool(fields, "continue"),
          extra_args~,
        ),
      )
    }
    "wait_child" =>
      Ok(
        WaitChild(
          timeout_ms=get_int(fields, "timeout_ms", 60_000),
          capture=get_str(fields, "capture"),
        ),
      )
    "spawn_bin" => {
      let args : Array[String] = []
      match fields.get("args") {
        Some(Array(items)) =>
          for item in items {
            if item is String(s) {
              args.push(s)
            }
          }
        _ => ()
      }
      Ok(SpawnBin(args~))
    }
    "kill_child_mid_run" =>
      Ok(
        KillChildMidRun(
          after_mock_request=get_int(fields, "after_mock_request", 1),
        ),
      )
    "tui_new" =>
      Ok(
        TuiNew(
          cols=get_int(fields, "cols", 100),
          rows=get_int(fields, "rows", 30),
        ),
      )
    "tui_type" => Ok(TuiType(text=get_str(fields, "text")))
    "tui_press" => Ok(TuiPress(key=get_str(fields, "key")))
    "tui_send" =>
      Ok(
        TuiSend(
          text=get_str(fields, "text"),
          timeout_ms=get_int(fields, "timeout_ms", 60_000),
        ),
      )
    "tui_screenshot" => Ok(TuiScreenshot(name=get_str(fields, "name")))
    "assert" => {
      let assertions : Array[@eval.AssertionKind] = []
      match fields.get("assertions") {
        Some(Array(items)) =>
          for item in items {
            match @eval.parse_assertion_kind(item) {
              Some(kind) => assertions.push(kind)
              None => return Err("unparsable assertion in step")
            }
          }
        _ => ()
      }
      Ok(Assert(assertions~))
    }
    _ => Err("unknown action \"\{action}\"")
  }
}

///|
/// Parse a journey scenario from JSON text.
pub fn parse_journey_scenario(text : String) -> Result[JourneyScenario, String] {
  let json = @json.parse(text) catch { _ => return Err("invalid JSON") }
  guard json is Object(root) else {
    return Err("scenario must be a JSON object")
  }
  let id = get_str(root, "id")
  if id.is_empty() {
    return Err("scenario missing \"id\"")
  }
  let timeout_ms = {
    let t = get_int(root, "timeout_ms", 0)
    if t > 0 {
      t
    } else {
      120_000
    }
  }
  let server_port = {
    let p = get_int(root, "server_port", 0)
    if p > 0 && p < 65_536 {
      p
    } else {
      17_471
    }
  }
  let seed : Array[(String, String)] = []
  match root.get("seed") {
    Some(Array(items)) =>
      for item in items {
        if item is Object(f) {
          let path = get_str(f, "path")
          if !path.is_empty() {
            seed.push((path, get_str(f, "content")))
          }
        }
      }
    _ => ()
  }
  let llm_steps : Array[Json] = []
  match root.get("llm_steps") {
    Some(Array(items)) =>
      for item in items {
        llm_steps.push(item)
      }
    _ => ()
  }
  let phases : Array[JourneyPhase] = []
  match root.get("phases") {
    Some(Array(items)) =>
      for item in items {
        guard item is Object(po) else { continue }
        let name = get_str(po, "name")
        let steps : Array[JourneyStep] = []
        match po.get("steps") {
          Some(Array(step_items)) =>
            for si in step_items {
              guard si is Object(so) else { continue }
              match parse_step_action(so) {
                Ok(action) => steps.push({ action, })
                Err(msg) => return Err("phase \{name}: \{msg}")
              }
            }
          _ => ()
        }
        phases.push({ name, steps, })
      }
    _ => ()
  }
  let assertions : Array[@eval.AssertionKind] = []
  match root.get("assertions") {
    Some(Array(items)) =>
      for item in items {
        match @eval.parse_assertion_kind(item) {
          Some(kind) => assertions.push(kind)
          None => return Err("unparsable journey-level assertion")
        }
      }
    _ => ()
  }
  let scenario : JourneyScenario = {
    id,
    title: get_str(root, "title"),
    area: get_str(root, "area"),
    description: get_str(root, "description"),
    timeout_ms,
    server_port,
    permission_mode: get_str(root, "permission_mode"),
    seed,
    llm_steps,
    phases,
    assertions,
  }
  Ok(scenario)
}

///|
/// Load and parse all journey scenario files in a directory.
/// Files that fail to parse become explicit Err entries (the runner turns
/// them into failed suites instead of silently dropping them).
pub fn load_journey_scenarios(
  dir_path : String,
) -> Array[Result[JourneyScenario, String]] {
  let out : Array[Result[JourneyScenario, String]] = []
  for text in @eval.load_scenario_files(dir_path) {
    out.push(parse_journey_scenario(text))
  }
  out
}
