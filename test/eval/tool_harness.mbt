///| Deterministic tool harness (T7).
///
/// A harness task is a declarative script: a goal, an allowlisted tool
/// sequence, and machine-checkable assertions. The harness drives the *real*
/// `lib/tool` registry inside a sandbox directory, so a passing task means the
/// tool layer actually produced the artifact — no model, no network, and the
/// same input always yields the same report.
///
/// Task file shape (`test/eval/tasks/*.json`):
///
/// ```json
/// {
///   "id": "doc-note",
///   "goal": "Write a note and read it back",
///   "steps": [
///     { "tool": "write", "args": { "path": "{sandbox}/note.md", "content": "# Hi" } }
///   ],
///   "checks": [
///     { "kind": "file_exists", "path": "{sandbox}/note.md" },
///     { "kind": "file_contains", "path": "{sandbox}/note.md", "text": "# Hi" }
///   ]
/// }
/// ```
///
/// `{sandbox}` expands to the per-trial sandbox directory. Check kinds:
/// `file_exists`, `file_missing`, `file_contains`, `file_not_contains`.

///|
/// Tools a task file may drive. Anything outside this list is rejected before
/// execution, so a task can never reach the network, a shell, or a real repo.
let harness_tool_allowlist : Array[String] = [
  "read", "write", "edit", "grep", "glob",
]

///|
/// One declarative step: an allowlisted tool, its JSON arguments, and an
/// optional assertion on the tool's own output.
pub(all) struct HarnessStep {
  tool : String
  args : Map[String, Json]
  /// When non-empty, the step's output must contain this text.
  expect_contains : String
}

///|
/// One machine-checkable success criterion.
pub(all) struct HarnessCheck {
  kind : String
  path : String
  text : String
}

///|
/// A file the harness materializes in the sandbox *before* the steps run, so a
/// task can start from a given (e.g. broken) state.
pub(all) struct HarnessSeed {
  path : String
  content : String
}

///|
/// A harness task: a goal, optional seed fixtures, an ordered step script, and
/// its checks.
pub(all) struct HarnessTask {
  id : String
  goal : String
  seeds : Array[HarnessSeed]
  steps : Array[HarnessStep]
  checks : Array[HarnessCheck]
}

///|
/// Outcome of a single assertion.
pub(all) struct HarnessAssertion {
  description : String
  passed : Bool
  detail : String
}

///|
/// Outcome of running one task.
pub(all) struct HarnessTaskResult {
  task_id : String
  goal : String
  passed : Bool
  steps_run : Int
  assertions : Array[HarnessAssertion]
}

///|
/// Outcome of one harness batch.
pub(all) struct HarnessReport {
  results : Array[HarnessTaskResult]
}

// ── Parsing ─────────────────────────────────────────────────────────────────

///|
fn as_object(json : Json) -> Map[String, Json]? {
  match json {
    Object(fields) => Some(fields)
    _ => None
  }
}

///|
fn json_string(fields : Map[String, Json], key : String) -> String? {
  match fields.get(key) {
    Some(String(text)) => Some(text)
    _ => None
  }
}

///|
/// Parse one task file. Returns None when the document is not a task.
pub fn parse_harness_task(text : String) -> HarnessTask? {
  let parsed : Json = @json.parse(text) catch { _ => return None }
  let fields = match as_object(parsed) {
    Some(found) => found
    None => return None
  }
  let id = match json_string(fields, "id") {
    Some(found) => found
    None => return None
  }
  let goal = match json_string(fields, "goal") {
    Some(found) => found
    None => ""
  }
  let steps : Array[HarnessStep] = []
  match fields.get("steps") {
    Some(Array(items)) =>
      for item in items {
        match as_object(item) {
          Some(step_fields) =>
            match json_string(step_fields, "tool") {
              Some(tool) => {
                let args = match as_object(
                  step_fields.get("args").unwrap_or(Json::null()),
                ) {
                  Some(found) => found
                  None => Map([])
                }
                steps.push({
                  tool,
                  args,
                  expect_contains: json_string(
                    step_fields,
                    "expect_contains",
                  ).unwrap_or(""),
                })
              }
              None => ()
            }
          None => ()
        }
      }
    _ => ()
  }
  let checks : Array[HarnessCheck] = []
  match fields.get("checks") {
    Some(Array(items)) =>
      for item in items {
        match as_object(item) {
          Some(check_fields) =>
            match json_string(check_fields, "kind") {
              Some(kind) =>
                checks.push({
                  kind,
                  path: json_string(check_fields, "path").unwrap_or(""),
                  text: json_string(check_fields, "text").unwrap_or(""),
                })
              None => ()
            }
          None => ()
        }
      }
    _ => ()
  }
  let seeds : Array[HarnessSeed] = []
  match fields.get("seed") {
    Some(Array(items)) =>
      for item in items {
        match as_object(item) {
          Some(seed_fields) =>
            match json_string(seed_fields, "path") {
              Some(path) =>
                seeds.push({
                  path,
                  content: json_string(seed_fields, "content").unwrap_or(""),
                })
              None => ()
            }
          None => ()
        }
      }
    _ => ()
  }
  Some({ id, goal, seeds, steps, checks })
}

///|
/// Load every `.json` task in a directory, ordered by file name so the batch
/// is reproducible across filesystems.
pub fn load_harness_tasks(dir : String) -> Array[HarnessTask] {
  let names = @fs.read_dir(dir) catch { _ => return [] }
  let files : Array[String] = []
  for name in names {
    if name.has_suffix(".json") {
      files.push(name)
    }
  }
  files.sort()
  let tasks : Array[HarnessTask] = []
  for name in files {
    let path = @path.Path::join(dir, @path.Path(name)).to_string()
    let text = @fs.read_file_to_string(path) catch { _ => continue }
    match parse_harness_task(text) {
      Some(task) => tasks.push(task)
      None => ()
    }
  }
  tasks
}

// ── Execution ───────────────────────────────────────────────────────────────

///|
fn expand_sandbox(text : String, sandbox : String) -> String {
  text.split("{sandbox}").collect().join(sandbox)
}

///|
fn expand_args(args : Map[String, Json], sandbox : String) -> Map[String, Json] {
  let out : Map[String, Json] = Map([])
  for entry in args {
    out[entry.0] = match entry.1 {
      String(text) => Json::string(expand_sandbox(text, sandbox))
      other => other
    }
  }
  out
}

///|
fn is_allowlisted(tool : String) -> Bool {
  for allowed in harness_tool_allowlist {
    if allowed == tool {
      return true
    }
  }
  false
}

///|
fn evaluate_check(check : HarnessCheck, sandbox : String) -> HarnessAssertion {
  let path = expand_sandbox(check.path, sandbox)
  let exists = @fs.path_exists(path)
  match check.kind {
    "file_exists" =>
      {
        description: "file exists: \{check.path}",
        passed: exists,
        detail: if exists { "" } else { "missing" },
      }
    "file_missing" =>
      {
        description: "file absent: \{check.path}",
        passed: !exists,
        detail: if exists { "still present" } else { "" },
      }
    "file_contains" | "file_not_contains" => {
      let content = @fs.read_file_to_string(path) catch { _ => "" }
      let hit = content.contains(expand_sandbox(check.text, sandbox))
      let expect = check.kind == "file_contains"
      {
        description: "\{check.kind}: \{check.path}",
        passed: exists && hit == expect,
        detail: if !exists {
          "missing file"
        } else if hit == expect {
          ""
        } else {
          "content mismatch"
        },
      }
    }
    other => {
      description: "check kind '\{other}' is supported",
      passed: false,
      detail: "unknown check kind",
    }
  }
}

///|
/// Invoke one tool, converting a raised error into a failed `ToolResult` so a
/// misbehaving step is reported as a failed assertion rather than a crash.
async fn execute_tool(
  tool : @tool.AnyTool,
  args : Map[String, Json],
) -> @tool.ToolResult {
  @tool.Tool::execute(tool, args) catch {
    err => { content: "tool raised: " + @debug.to_string(err), is_error: true }
  }
}

///|
/// Run one task: execute its steps through the real tool registry inside
/// `sandbox`, then evaluate its checks.
pub async fn run_harness_task(
  task : HarnessTask,
  sandbox : String,
) -> HarnessTaskResult {
  let assertions : Array[HarnessAssertion] = []
  let registry = @tool.make_default_registry()
  let mut steps_run = 0
  for seed in task.seeds {
    let path = expand_sandbox(seed.path, sandbox)
    @fs.write_string_to_file(path, expand_sandbox(seed.content, sandbox)) catch {
      err =>
        assertions.push({
          description: "seed '\{seed.path}' is materialized",
          passed: false,
          detail: @debug.to_string(err),
        })
    }
  }
  for step in task.steps {
    let position = steps_run + 1
    if !is_allowlisted(step.tool) {
      assertions.push({
        description: "step \{position}: tool '\{step.tool}' is allowlisted",
        passed: false,
        detail: "tool not in the harness allowlist",
      })
      continue
    }
    match registry.get_resolved(step.tool) {
      Some(tool) => {
        let result = execute_tool(tool, expand_args(step.args, sandbox))
        steps_run = steps_run + 1
        if result.is_error {
          assertions.push({
            description: "step \{steps_run}: \{step.tool} ran without error",
            passed: false,
            detail: result.content,
          })
        } else if step.expect_contains != "" {
          let expected = expand_sandbox(step.expect_contains, sandbox)
          let hit = result.content.contains(expected)
          assertions.push({
            description: "step \{steps_run}: \{step.tool} output contains '\{step.expect_contains}'",
            passed: hit,
            detail: if hit { "" } else { "not found in tool output" },
          })
        }
      }
      None =>
        assertions.push({
          description: "step \{position}: tool '\{step.tool}' resolves",
          passed: false,
          detail: "no such tool in the default registry",
        })
    }
  }
  for check in task.checks {
    assertions.push(evaluate_check(check, sandbox))
  }
  let mut passed = true
  for assertion in assertions {
    if !assertion.passed {
      passed = false
    }
  }
  { task_id: task.id, goal: task.goal, passed, steps_run, assertions, }
}

///|
/// Run every task `trials` times, each trial in its own sandbox directory.
///
/// Repeating a task is a real assertion offline: a deterministic harness must
/// produce the same verdict every time, which is what `repeatability` scores.
pub async fn run_harness_batch(
  tasks : Array[HarnessTask],
  sandbox_root : String,
  trials : Int,
) -> HarnessReport {
  let results : Array[HarnessTaskResult] = []
  if trials <= 0 {
    return HarnessReport::{ results }
  }
  if !@fs.path_exists(sandbox_root) {
    @fs.create_dir(sandbox_root) catch { _ => () }
  }
  for task in tasks {
    for trial in 0..<trials {
      let sandbox = @path.Path::join(
        sandbox_root,
        @path.Path("\{task.id}-\{trial + 1}"),
      ).to_string()
      prepare_sandbox(sandbox)
      results.push(run_harness_task(task, sandbox))
    }
  }
  HarnessReport::{ results }
}

///|
/// Create a clean sandbox directory (removing a leftover one first).
fn prepare_sandbox(sandbox : String) -> Unit {
  if @fs.path_exists(sandbox) {
    @fs.remove_dir(sandbox) catch { _ => () }
  }
  @fs.create_dir(sandbox) catch { _ => () }
}

// ── Scoring ─────────────────────────────────────────────────────────────────

///|
/// The evaluation score vector: completion, verification discipline,
/// repeatability, and cost (always 0 offline — no model is called).
pub(all) struct EvalScoreVector {
  tasks : Int
  tasks_passed : Int
  assertions : Int
  assertions_passed : Int
  repeatable_tasks : Int
  trials : Int
  cost_usd : Double
}

///|
pub fn HarnessReport::score(self : HarnessReport, trials : Int) -> EvalScoreVector {
  let tasks : Array[String] = []
  let mut assertions = 0
  let mut assertions_passed = 0
  for result in self.results {
    let mut known = false
    for seen in tasks {
      if seen == result.task_id {
        known = true
      }
    }
    if !known {
      tasks.push(result.task_id)
    }
    for assertion in result.assertions {
      assertions = assertions + 1
      if assertion.passed {
        assertions_passed = assertions_passed + 1
      }
    }
  }
  let mut tasks_passed = 0
  let mut repeatable = 0
  for task_id in tasks {
    let mut runs = 0
    let mut ok = 0
    for result in self.results {
      if result.task_id == task_id {
        runs = runs + 1
        if result.passed {
          ok = ok + 1
        }
      }
    }
    if ok == runs {
      repeatable = repeatable + 1
    }
    if ok > 0 {
      tasks_passed = tasks_passed + 1
    }
  }
  {
    tasks: tasks.length(),
    tasks_passed,
    assertions,
    assertions_passed,
    repeatable_tasks: repeatable,
    trials,
    cost_usd: 0.0,
  }
}

///|
/// `completion_rate` = tasks with at least one passing run / tasks.
pub fn EvalScoreVector::completion_rate(self : EvalScoreVector) -> Double {
  if self.tasks == 0 {
    return 0.0
  }
  self.tasks_passed.to_double() / self.tasks.to_double()
}

///|
/// `verification_rate` = passing assertions / all assertions.
pub fn EvalScoreVector::verification_rate(self : EvalScoreVector) -> Double {
  if self.assertions == 0 {
    return 0.0
  }
  self.assertions_passed.to_double() / self.assertions.to_double()
}

///|
/// `repeatability` = tasks whose every trial agreed / tasks.
pub fn EvalScoreVector::repeatability(self : EvalScoreVector) -> Double {
  if self.tasks == 0 {
    return 0.0
  }
  self.repeatable_tasks.to_double() / self.tasks.to_double()
}

///|
/// The score vector as JSON — the machine-readable artifact `cmd eval` emits.
pub fn HarnessReport::to_score_json(
  self : HarnessReport,
  mode : String,
  trials : Int,
) -> Json {
  let score = self.score(trials)
  let results : Array[Json] = []
  for result in self.results {
    let mut passed_assertions = 0
    for assertion in result.assertions {
      if assertion.passed {
        passed_assertions = passed_assertions + 1
      }
    }
    results.push(
      Json::object({
        "task_id": result.task_id.to_json(),
        "passed": Json::boolean(result.passed),
        "steps_run": result.steps_run.to_json(),
        "assertions": result.assertions.length().to_json(),
        "assertions_passed": passed_assertions.to_json(),
      }),
    )
  }
  Json::object({
    "mode": mode.to_json(),
    "trials": trials.to_json(),
    "tasks": score.tasks.to_json(),
    "tasks_passed": score.tasks_passed.to_json(),
    "assertions": score.assertions.to_json(),
    "assertions_passed": score.assertions_passed.to_json(),
    "completion_rate": Json::number(score.completion_rate()),
    "verification_rate": Json::number(score.verification_rate()),
    "repeatability": Json::number(score.repeatability()),
    "cost_usd": Json::number(score.cost_usd),
    "results": Json::array(results),
  })
}

///|
/// A human-readable report body for `docs/eval/<date>.md`.
pub fn HarnessReport::to_markdown(
  self : HarnessReport,
  mode : String,
  trials : Int,
) -> String {
  let score = self.score(trials)
  let lines : Array[String] = []
  lines.push("# cmd eval report（\{mode}）")
  lines.push("")
  lines.push(
    "| 任务 | 步骤 | 断言 | 通过 | 本次结果 |",
  )
  lines.push("|---|---|---|---|---|")
  for result in self.results {
    let mut passed_assertions = 0
    for assertion in result.assertions {
      if assertion.passed {
        passed_assertions = passed_assertions + 1
      }
    }
    lines.push(
      "| \{result.task_id} | \{result.steps_run} | \{result.assertions.length()} | \{passed_assertions} | \{if result.passed { "PASS" } else { "FAIL" }} |",
    )
  }
  lines.push("")
  lines.push("## 评分向量")
  lines.push("")
  lines.push("| 维度 | 值 |")
  lines.push("|---|---|")
  lines.push(
    "| 完成率（tasks with a passing run / tasks） | \{score.completion_rate()} |",
  )
  lines.push(
    "| 验证纪律（passing assertions / assertions） | \{score.verification_rate()} |",
  )
  lines.push(
    "| 可重复性（trials 全部一致的任务 / tasks，trials=\{trials}） | \{score.repeatability()} |",
  )
  lines.push("| 成本（USD，offline 不调用模型） | \{score.cost_usd} |")
  lines.push("")
  lines.push("## 断言明细")
  lines.push("")
  for result in self.results {
    lines.push("### \{result.task_id}（\{result.goal}）")
    for assertion in result.assertions {
      lines.push(
        "- [\{if assertion.passed { "x" } else { " " }}] \{assertion.description}\{if assertion.detail == "" { "" } else { " — " + assertion.detail }}",
      )
    }
    lines.push("")
  }
  lines.join("\n")
}