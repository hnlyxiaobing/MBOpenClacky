///| CLI contract probes (P0-3).
///
/// Runs the CLI as an **argv array** (never through a shell), asserting the
/// observable contract for each probe:
///
/// - exit code: zero / non-zero / an exact value
/// - stdout shape: empty / text / JSON / JSON-lines
/// - stdout content: required substrings
/// - stderr policy: clean, or must contain one of a set
/// - forbidden markers: `Failure(` / `Panic(` / `Raised at` never appear
///
/// The same probe set is executed against the **release native binary** and,
/// when `moon` is available, against `moon run cmd --`. Differences between
/// the two targets are reported rather than hidden (the `moon run` binary is
/// the debug build, so byte-identical output is not guaranteed).
///
/// Before probing, the assertion engine self-checks with synthetic samples
/// (`engine_cases`), covering the stdout shapes the live CLI has no
/// deterministic command for (empty / JSON-lines).
///
/// Usage:
///   mbopenclacky selftest [--bin <path>] [--repo <dir>] [--json]
///                         [--timeout-ms <n>] [--no-moon-run]

///|
/// Expected exit-code contract for a probe.
enum ExitExpect {
  /// Exit code must be exactly zero.
  Zero
  /// Exit code must be non-zero.
  NonZero
  /// Exit code must equal this value.
  Exact(Int)
}

///|
/// Expected stdout shape for a probe.
enum StdoutShape {
  /// stdout must be empty (after trimming).
  Empty
  /// stdout must be non-empty plain text.
  Text
  /// stdout must parse as a single JSON value.
  Json
  /// every non-empty stdout line must parse as JSON.
  JsonLines
}

///|
/// Expected stderr policy for a probe.
enum StderrExpect {
  /// stderr must be empty after trimming.
  Clean
  /// stderr must contain at least one of these substrings.
  Contains(Array[String])
}

///|
/// One CLI contract probe.
struct Probe {
  /// Stable probe name used in reports.
  name : String
  /// argv passed to the CLI (no shell interpretation).
  args : Array[String]
  /// Expected exit-code contract.
  exit_expect : ExitExpect
  /// Expected stdout shape.
  stdout_shape : StdoutShape
  /// Substrings that must all appear in stdout.
  stdout_contains : Array[String]
  /// Expected stderr policy.
  stderr_expect : StderrExpect
}

///|
/// Outcome of spawning and capturing one command.
struct CaptureResult {
  /// Whether the process was spawned at all.
  spawned : Bool
  /// Exit code (-1 when spawning failed).
  exit_code : Int
  /// Captured stdout.
  stdout : String
  /// Captured stderr.
  stderr : String
}

///|
/// Outcome of one probe against one target.
struct ProbeRun {
  /// Probe name.
  name : String
  /// Target label (e.g. "native", "moon-run").
  target : String
  /// Whether the probe was actually executed.
  executed : Bool
  /// Process exit code.
  exit_code : Int
  /// Captured stdout (trimmed for comparison).
  stdout : String
  /// Captured stderr (trimmed; surfaced in reports on failure and in diffs).
  stderr : String
  /// Human-readable contract violations (empty means the probe passed).
  failures : Array[String]
}

///|
/// One synthetic assertion-engine check.
struct EngineCase {
  /// What the case verifies.
  label : String
  /// Whether the helper classified the sample as expected.
  ok : Bool
}

///|
/// Markers that must never appear in CLI output (panic / internal failure
/// leakage). These are asserted for every probe, on both streams.
let forbidden_markers : Array[String] = [
  "Failure(", "Panic(", "Raised at", "unreachable", "Aborted",
]

///|
/// Default per-probe timeout in milliseconds. Prevents an accidental
/// interactive path from hanging CI forever.
let default_probe_timeout_ms : Int = 30_000

///|
/// Capture a command's exit code, stdout and stderr without a shell.
async fn capture_output(
  cmd : String,
  args : Array[String],
  cwd : String,
) -> CaptureResult {
  let captured : (Int, &@io.Data, &@io.Data)? = Some(
    @process.collect_output(cmd, args, cwd~),
  ) catch {
    _ => None
  }
  match captured {
    None => { spawned: false, exit_code: -1, stdout: "", stderr: "", }
    Some((code, out_data, err_data)) => {
      let stdout = out_data.text() catch { _ => "" }
      let stderr = err_data.text() catch { _ => "" }
      { spawned: true, exit_code: code, stdout, stderr, }
    }
  }
}

///|
/// Whether `text` parses as a single JSON value.
fn is_valid_json(text : String) -> Bool {
  let _ = @json.parse(text) catch { _ => return false }
  true
}

///|
/// Check stdout against the expected shape. Pure; unit-tested and exercised
/// by `engine_cases`.
fn check_stdout_shape(shape : StdoutShape, stdout : String) -> Array[String] {
  let failures : Array[String] = []
  let trimmed = stdout.trim().to_owned()
  match shape {
    Empty =>
      if trimmed.length() > 0 {
        failures.push("expected empty stdout, got \{trimmed.length()} bytes")
      }
    Text =>
      if trimmed.length() == 0 {
        failures.push("expected text stdout, got empty output")
      }
    Json =>
      if trimmed.length() == 0 {
        failures.push("expected JSON stdout, got empty output")
      } else if !is_valid_json(trimmed) {
        failures.push("stdout is not valid JSON")
      }
    JsonLines => {
      let mut saw_line = false
      for line in trimmed.split("\n") {
        let text = line.trim().to_owned()
        if text.length() == 0 {
          continue
        }
        saw_line = true
        if !is_valid_json(text) {
          failures.push("stdout line is not valid JSON")
          break
        }
      }
      if !saw_line {
        failures.push("expected JSON-lines stdout, got empty output")
      }
    }
  }
  failures
}

///|
/// Check an exit code against the expectation. Pure.
fn check_exit(expect : ExitExpect, code : Int) -> Array[String] {
  let failures : Array[String] = []
  match expect {
    Zero => if code != 0 { failures.push("expected exit 0, got \{code}") }
    NonZero => if code == 0 { failures.push("expected non-zero exit, got 0") }
    Exact(want) =>
      if code != want {
        failures.push("expected exit \{want}, got \{code}")
      }
  }
  failures
}

///|
/// Check stderr against the policy. Pure.
fn check_stderr(expect : StderrExpect, stderr : String) -> Array[String] {
  let failures : Array[String] = []
  match expect {
    Clean =>
      if stderr.trim().length() > 0 {
        failures.push("expected clean stderr, got: \{stderr.trim()}")
      }
    Contains(needles) => {
      let mut found = false
      for needle in needles {
        if stderr.contains(needle) {
          found = true
        }
      }
      if !found {
        failures.push("stderr missing any of: " + needles.join(", "))
      }
    }
  }
  failures
}

///|
/// Check required substrings and forbidden markers. Pure.
fn check_content(
  stdout_contains : Array[String],
  stdout : String,
  stderr : String,
) -> Array[String] {
  let failures : Array[String] = []
  for needle in stdout_contains {
    if !stdout.contains(needle) {
      failures.push("stdout missing required substring: \{needle}")
    }
  }
  for marker in forbidden_markers {
    if stdout.contains(marker) {
      failures.push("forbidden marker in stdout: \{marker}")
    }
    if stderr.contains(marker) {
      failures.push("forbidden marker in stderr: \{marker}")
    }
  }
  failures
}

///|
/// Synthetic samples for every assertion helper. The live CLI has no
/// deterministic command that emits empty stdout or JSON-lines, so those
/// shapes are verified here at runtime (and in `selftest_wbtest.mbt`).
fn engine_cases() -> Array[EngineCase] {
  let cases : Array[EngineCase] = []
  cases.push({
    label: "stdout empty / empty",
    ok: check_stdout_shape(Empty, "  \n\t").length() == 0,
  })
  cases.push({
    label: "stdout empty / non-empty",
    ok: check_stdout_shape(Empty, "x").length() > 0,
  })
  cases.push({
    label: "stdout text / text",
    ok: check_stdout_shape(Text, "hello").length() == 0,
  })
  cases.push({
    label: "stdout text / empty",
    ok: check_stdout_shape(Text, "   ").length() > 0,
  })
  cases.push({
    label: "stdout json / json",
    ok: check_stdout_shape(Json, "{\"a\":1}").length() == 0,
  })
  cases.push({
    label: "stdout json / not json",
    ok: check_stdout_shape(Json, "nope").length() > 0,
  })
  cases.push({
    label: "stdout json / empty",
    ok: check_stdout_shape(Json, "").length() > 0,
  })
  cases.push({
    label: "stdout jsonl / jsonl",
    ok: check_stdout_shape(JsonLines, "{\"a\":1}\n{\"b\":2}\n").length() == 0,
  })
  cases.push({
    label: "stdout jsonl / bad line",
    ok: check_stdout_shape(JsonLines, "{\"a\":1}\nnope\n").length() > 0,
  })
  cases.push({
    label: "stdout jsonl / empty",
    ok: check_stdout_shape(JsonLines, "").length() > 0,
  })
  cases.push({ label: "exit zero / 0", ok: check_exit(Zero, 0).length() == 0, })
  cases.push({ label: "exit zero / 1", ok: check_exit(Zero, 1).length() > 0, })
  cases.push({
    label: "exit non-zero / 1",
    ok: check_exit(NonZero, 1).length() == 0,
  })
  cases.push({
    label: "exit non-zero / 0",
    ok: check_exit(NonZero, 0).length() > 0,
  })
  cases.push({
    label: "exit exact 3 / 3",
    ok: check_exit(Exact(3), 3).length() == 0,
  })
  cases.push({
    label: "exit exact 3 / 4",
    ok: check_exit(Exact(3), 4).length() > 0,
  })
  cases.push({
    label: "stderr clean / empty",
    ok: check_stderr(Clean, "  ").length() == 0,
  })
  cases.push({
    label: "stderr clean / dirty",
    ok: check_stderr(Clean, "boom").length() > 0,
  })
  cases.push({
    label: "stderr contains / hit",
    ok: check_stderr(Contains(["boom"]), "a boom").length() == 0,
  })
  cases.push({
    label: "stderr contains / miss",
    ok: check_stderr(Contains(["boom"]), "quiet").length() > 0,
  })
  cases.push({
    label: "content present",
    ok: check_content(["hello"], "hello", "").length() == 0,
  })
  cases.push({
    label: "content missing",
    ok: check_content(["nope"], "hello", "").length() > 0,
  })
  cases.push({
    label: "content forbidden marker",
    ok: check_content([], "Failure(x)", "").length() > 0,
  })
  cases
}

///|
/// Run one probe against one target command.
async fn run_probe(
  target : String,
  cmd : String,
  prepend_args : Array[String],
  probe : Probe,
  repo : String,
  timeout_ms : Int,
) -> ProbeRun {
  let args : Array[String] = []
  for arg in prepend_args {
    args.push(arg)
  }
  for arg in probe.args {
    args.push(arg)
  }
  let captured = @async.with_timeout_opt(timeout_ms, () => {
    capture_output(cmd, args, repo)
  }) catch {
    _ => None
  }
  match captured {
    None =>
      {
        name: probe.name,
        target,
        executed: true,
        exit_code: -1,
        stdout: "",
        stderr: "",
        failures: ["timed out after \{timeout_ms} ms"],
      }
    Some(result) =>
      if !result.spawned {
        {
          name: probe.name,
          target,
          executed: false,
          exit_code: -1,
          stdout: "",
          stderr: "",
          failures: ["could not spawn '\{cmd}'"],
        }
      } else {
        let failures : Array[String] = []
        for failure in check_exit(probe.exit_expect, result.exit_code) {
          failures.push(failure)
        }
        for failure in check_stdout_shape(probe.stdout_shape, result.stdout) {
          failures.push(failure)
        }
        for failure in check_stderr(probe.stderr_expect, result.stderr) {
          failures.push(failure)
        }
        for
          failure in check_content(
            probe.stdout_contains,
            result.stdout,
            result.stderr,
          ) {
          failures.push(failure)
        }
        {
          name: probe.name,
          target,
          executed: true,
          exit_code: result.exit_code,
          stdout: result.stdout.trim().to_owned(),
          stderr: result.stderr.trim().to_owned(),
          failures,
        }
      }
  }
}

///|
/// The probe set. Coverage rationale:
///
/// - `help` / `version`: the two always-available entry points
/// - `list_sessions` / `list_sessions_json`: the session listing contract in
///   text and JSON form (deterministic, no model call)
/// - `unknown_flag` / `invalid_mode`: clap argument-validation failures.
///   clap reports its message on **stdout** (observed, upstream behaviour),
///   so the probe pins the observable contract rather than an aspirational
///   stderr policy.
/// - `mcp_unavailable`: a capability that is honestly reported as missing
///   must still exit non-zero so scripts can detect it
fn probe_set() -> Array[Probe] {
  [
    {
      name: "help",
      args: ["--help"],
      exit_expect: Zero,
      stdout_shape: Text,
      stdout_contains: ["Usage:", "mbopenclacky"],
      stderr_expect: Clean,
    },
    {
      name: "version",
      args: ["--version"],
      exit_expect: Zero,
      stdout_shape: Text,
      stdout_contains: ["MBOpenClacky v"],
      stderr_expect: Clean,
    },
    {
      name: "list_sessions",
      args: ["--list"],
      exit_expect: Zero,
      stdout_shape: Text,
      stdout_contains: ["session"],
      stderr_expect: Clean,
    },
    {
      name: "list_sessions_json",
      args: ["--list", "--json"],
      exit_expect: Zero,
      stdout_shape: Json,
      stdout_contains: ["\"sessions\"", "\"total\""],
      stderr_expect: Clean,
    },
    {
      name: "unknown_flag",
      args: ["--definitely-not-a-flag"],
      exit_expect: Exact(1),
      stdout_shape: Text,
      stdout_contains: ["InvalidArgumentName"],
      stderr_expect: Clean,
    },
    {
      name: "invalid_mode",
      args: ["--mode", "bogus"],
      exit_expect: Exact(1),
      stdout_shape: Text,
      stdout_contains: ["InvalidArgumentValue"],
      stderr_expect: Clean,
    },
    {
      name: "mcp_unavailable",
      args: ["mcp"],
      exit_expect: NonZero,
      stdout_shape: Text,
      stdout_contains: ["not yet available"],
      stderr_expect: Clean,
    },
  ]
}

///|
/// Read the module version from `moon.mod` so the `--version` probe can catch
/// a compiled-in version that drifted from the manifest. Returns None when the
/// manifest is not readable (the probe then checks the format only).
fn read_module_version(repo : String) -> String? {
  let manifest = @path.Path::join(repo, @path.Path("moon.mod")).to_string()
  let content = @fs.read_file_to_string(manifest) catch { _ => return None }
  for line in content.split("\n") {
    let text = line.trim().to_owned()
    if text.has_prefix("version") {
      let quoted = text.split("\"").collect()
      if quoted.length() >= 2 {
        return Some(quoted[1].to_owned())
      }
    }
  }
  None
}

///|
/// Candidate locations of the release native binary, relative to the repo
/// root. `moon build --target native --release cmd` places it under the
/// module-qualified path.
fn detect_binary(repo : String) -> String? {
  let candidates : Array[String] = [
    "_build/native/release/build/hnlyxiaobing/MBOpenClacky/cmd/cmd.exe", "_build/native/release/build/hnlyxiaobing/MBOpenClacky/cmd/cmd",
    "_build/native/release/build/cmd/cmd.exe", "_build/native/release/build/cmd/cmd",
  ]
  for candidate in candidates {
    let full = @path.Path::join(repo, @path.Path(candidate)).to_string()
    if @fs.path_exists(full) {
      return Some(full)
    }
  }
  None
}

///|
/// Render the probe runs as a human-readable report.
fn render_report(
  runs : Array[ProbeRun],
  engine : Array[EngineCase],
  note : String,
) -> String {
  let buffer : Array[String] = []
  buffer.push("CLI contract probes (P0-3)")
  if note.length() > 0 {
    buffer.push(note)
  }
  let mut engine_ok = 0
  for case in engine {
    if case.ok {
      engine_ok = engine_ok + 1
    }
  }
  buffer.push("")
  buffer.push(
    "assertion engine self-check: \{engine_ok}/\{engine.length()} cases",
  )
  for case in engine {
    if !case.ok {
      buffer.push("  FAIL \{case.label}")
    }
  }
  let mut current_target = ""
  for run in runs {
    if run.target != current_target {
      current_target = run.target
      buffer.push("")
      buffer.push("target: \{current_target}")
    }
    let status = if !run.executed {
      "SKIP"
    } else if run.failures.length() == 0 {
      "PASS"
    } else {
      "FAIL"
    }
    let detail = if run.failures.length() == 0 {
      ""
    } else {
      " — " + run.failures.join("; ")
    }
    buffer.push("  \{status} \{run.name} (exit \{run.exit_code})\{detail}")
    if run.failures.length() > 0 && run.stderr.length() > 0 {
      buffer.push("       stderr: \{run.stderr}")
    }
  }
  buffer.join("\n")
}

///|
/// Compare native and moon-run outcomes for the same probe name, returning
/// human-readable difference lines.
fn render_differences(runs : Array[ProbeRun]) -> Array[String] {
  let differences : Array[String] = []
  let native : Map[String, ProbeRun] = Map([])
  let moon : Map[String, ProbeRun] = Map([])
  for run in runs {
    if run.executed {
      if run.target == "native" {
        native[run.name] = run
      } else {
        moon[run.name] = run
      }
    }
  }
  for name, n in native {
    match moon.get(name) {
      None => differences.push("\{name}: only executed on native")
      Some(m) =>
        if n.exit_code != m.exit_code {
          differences.push(
            "\{name}: exit \{n.exit_code} (native) vs \{m.exit_code} (moon run)",
          )
        } else if n.stdout != m.stdout {
          differences.push("\{name}: stdout text differs (exit codes match)")
        } else if n.stderr != m.stderr {
          differences.push("\{name}: stderr text differs (exit codes match)")
        }
    }
  }
  differences
}

///|
/// Build the machine-readable JSON report.
fn render_json_report(
  runs : Array[ProbeRun],
  engine : Array[EngineCase],
  differences : Array[String],
  ok : Bool,
) -> String {
  let items : Array[Json] = []
  for run in runs {
    let failures : Array[Json] = []
    for failure in run.failures {
      failures.push(failure.to_json())
    }
    let item : Map[String, Json] = {
      "name": run.name.to_json(),
      "target": run.target.to_json(),
      "executed": run.executed.to_json(),
      "exit_code": run.exit_code.to_json(),
      "ok": (run.executed && run.failures.length() == 0).to_json(),
      "failures": Json::array(failures),
    }
    items.push(Json::object(item))
  }
  let cases : Array[Json] = []
  for case in engine {
    let item : Map[String, Json] = {
      "label": case.label.to_json(),
      "ok": case.ok.to_json(),
    }
    cases.push(Json::object(item))
  }
  let diffs : Array[Json] = []
  for difference in differences {
    diffs.push(difference.to_json())
  }
  let report : Map[String, Json] = {
    "ok": ok.to_json(),
    "engine_checks": Json::array(cases),
    "probes": Json::array(items),
    "differences": Json::array(diffs),
  }
  Json::object(report).stringify()
}

///|
/// `cmd selftest`: run the CLI contract probes and report.
pub async fn handle_selftest(sub : @clap.SimpleValue) -> Unit {
  let repo = get_named_arg(sub, "repo").unwrap_or(".")
  let json_output = sub.get_flag("json") == Some(true)
  let with_moon_run = sub.get_flag("no-moon-run") != Some(true)
  let timeout_ms = match get_named_arg(sub, "timeout-ms") {
    Some(text) =>
      @string.parse_int(text) catch {
        _ => default_probe_timeout_ms
      }
    None => default_probe_timeout_ms
  }
  let binary = match get_named_arg(sub, "bin") {
    Some(path) => path
    None =>
      match detect_binary(repo) {
        Some(path) => path
        None =>
          match detect_binary(".") {
            Some(path) => path
            None => {
              println(
                "selftest: release binary not found. Build it first:\n" +
                "  moon build --target native --release cmd\n" +
                "or pass --bin <path>.",
              )
              @sys.exit(2)
              return
            }
          }
      }
  }
  let module_version = read_module_version(repo)
  let engine = engine_cases()
  let runs : Array[ProbeRun] = []
  let probes = probe_set()
  // Primary target: the release native binary.
  for probe in probes {
    runs.push(run_probe("native", binary, [], probe, repo, timeout_ms))
  }
  // Secondary target: `moon run cmd --` (skipped when disabled or unavailable).
  let mut note = ""
  if with_moon_run {
    let mut unavailable = ""
    for probe in probes {
      let run = run_probe(
        "moon-run",
        "moon",
        ["run", "cmd", "--"],
        probe,
        repo,
        timeout_ms,
      )
      if !run.executed && unavailable.length() == 0 {
        unavailable = if run.failures.length() > 0 {
          run.failures[0]
        } else {
          "unavailable"
        }
      }
      runs.push(run)
    }
    if unavailable.length() > 0 {
      note = "note: `moon run cmd` target unavailable (\{unavailable})"
    }
  }
  // Version-drift check: the compiled-in version must match moon.mod.
  match module_version {
    Some(version) =>
      for run in runs {
        if run.name == "version" &&
          run.executed &&
          !run.stdout.contains(version) {
          run.failures.push(
            "compiled version does not match moon.mod (expected \{version})",
          )
        }
      }
    None => ()
  }
  let differences = if with_moon_run { render_differences(runs) } else { [] }
  let mut ok = true
  for case in engine {
    if !case.ok {
      ok = false
    }
  }
  for run in runs {
    if run.executed && run.failures.length() > 0 {
      ok = false
    }
  }
  if json_output {
    println(render_json_report(runs, engine, differences, ok))
  } else {
    println(render_report(runs, engine, note))
    println("")
    if differences.length() > 0 {
      println("native vs moon run differences:")
      for difference in differences {
        println("  - \{difference}")
      }
    } else if with_moon_run {
      println("native vs moon run differences: none")
    } else {
      println("native vs moon run comparison: skipped (--no-moon-run)")
    }
    let mut executed = 0
    let mut passed = 0
    for run in runs {
      if run.executed {
        executed = executed + 1
        if run.failures.length() == 0 {
          passed = passed + 1
        }
      }
    }
    println("")
    println("summary: \{passed}/\{executed} probes passed")
  }
  if !ok {
    @sys.exit(1)
  }
}
