///| Model-driven capability harness (layer 8).
///
/// The deterministic harness in `tool_harness.mbt` answers "does the tool layer
/// work on a scripted sequence". This layer answers the question it cannot:
/// "can a real model actually drive the tools to a correct result".
///
/// Both layers share one task schema (`test/eval/tasks/` plus the
/// `prompt`/`acceptance`/`trials` fields, see `test/capability/README.md`), one
/// sandbox convention (`{sandbox}` expansion) and one set of `checks`, so the
/// two score vectors stay comparable.
///
/// The model call itself is injected as an `async (String, String) -> LiveRunOutcome`
/// runner. That keeps the whole driver — per-trial sandboxes, repetition,
/// assertion evaluation, scoring, reporting — deterministic and network-free
/// under test, while `make_agent_live_runner` supplies the real ReAct loop.

///|
/// Tools a live trial may expose, by canonical registry name. Deliberately
/// identical to the offline allowlist so both layers measure the same surface.
///
/// The live registry is rebuilt from these names rather than relying on
/// `Agent.allowed_tools`: `allowed_tools` only filters the definitions sent to
/// the model, while tool *execution* resolves through the registry
/// (`ToolRegistry::get_resolved`). Under `auto_approve` every registered tool
/// runs without confirmation, so the registry is the surface that must be
/// narrowed — otherwise a hallucinated `terminal` call would execute a shell
/// command on the host.
pub let live_tool_allowlist : Array[String] = [
  "file_reader", "write", "edit", "grep", "glob",
]

///|
/// What one model-driven trial produced. Built by the runner, so a fake runner
/// in tests can produce any outcome without a network.
pub(all) struct LiveRunOutcome {
  /// `RunStatus` of the agent run ("Success"/"Error"/"Interrupted").
  status : String
  iterations : Int
  cost_usd : Double
  /// `cost_source` of the run: `Api`/`Price`/`Default`/`Estimated`.
  cost_source : String
  prompt_tokens : Int
  completion_tokens : Int
  /// Compact, ordered log of the tool calls the model made.
  tool_steps : Array[String]
  transcript : String
  /// Diagnostic text when the run itself failed (not when checks failed).
  error : String?
}

///|
/// An outcome for a trial that could not be run at all (no model configured,
/// runner raised). Reported as an infrastructure failure, never as a pass.
pub fn LiveRunOutcome::infrastructure_failure(
  reason : String,
) -> LiveRunOutcome {
  {
    status: "Error",
    iterations: 0,
    cost_usd: 0.0,
    cost_source: "none",
    prompt_tokens: 0,
    completion_tokens: 0,
    tool_steps: [],
    transcript: "",
    error: Some(reason),
  }
}

///|
/// One task × one trial.
pub(all) struct LiveTrialResult {
  task_id : String
  goal : String
  /// 1-based trial index.
  trial : Int
  /// Every assertion passed (checks + seed materialization).
  passed : Bool
  assertions : Array[HarnessAssertion]
  outcome : LiveRunOutcome
  /// Where the full transcript was written ("" when not persisted).
  transcript_path : String
}

///|
/// One model-driven batch.
pub(all) struct LiveReport {
  results : Array[LiveTrialResult]
  /// Repetition count reported in the score vector.
  nominal_trials : Int
}

///|
/// Trials whose agent run failed outright (transport, auth, exhausted retries).
/// These make the command fail; failed *checks* do not.
pub fn LiveReport::infrastructure_errors(self : LiveReport) -> Int {
  let mut count = 0
  for result in self.results {
    if result.outcome.status == "Error" {
      count = count + 1
    }
  }
  count
}

///|
pub fn LiveReport::total_cost(self : LiveReport) -> Double {
  let mut total = 0.0
  for result in self.results {
    total = total + result.outcome.cost_usd
  }
  total
}

///|
/// The live report projected onto the shared score vector. `HarnessTaskResult`
/// carries no cost, so the summed cost is passed alongside.
pub fn LiveReport::as_harness_report(self : LiveReport) -> HarnessReport {
  let results : Array[HarnessTaskResult] = []
  for result in self.results {
    results.push({
      task_id: result.task_id,
      goal: result.goal,
      passed: result.passed,
      steps_run: result.outcome.tool_steps.length(),
      assertions: result.assertions,
    })
  }
  HarnessReport::{ results, }
}

///|
/// Run every task `trials` times through `runner`, each trial in its own
/// sandbox (seeded from the task's `seed` fixtures) and with its own transcript
/// file under `transcripts_dir`.
///
/// `trials_override` (from `--trials`) wins over the task's own `trials` field;
/// a task with neither runs 3 times.
pub async fn run_live_batch(
  tasks : Array[HarnessTask],
  sandbox_root : String,
  transcripts_dir : String,
  trials_override : Int?,
  runner : async (String, String) -> LiveRunOutcome,
) -> LiveReport {
  let results : Array[LiveTrialResult] = []
  for dir in [sandbox_root, transcripts_dir] {
    if !@fs.path_exists(dir) {
      @fs.create_dir(dir) catch {
        _ => ()
      }
    }
  }
  let mut nominal = 0
  for task in tasks {
    let trials = match trials_override {
      Some(n) => n
      None => if task.trials > 0 { task.trials } else { 3 }
    }
    if trials <= 0 {
      continue
    }
    if trials > nominal {
      nominal = trials
    }
    for trial in 1..<=trials {
      let sandbox = @path.Path::join(
        sandbox_root,
        @path.Path("\{task.id}-\{trial}"),
      ).to_string()
      prepare_sandbox(sandbox)
      let assertions = materialize_seeds(task, sandbox)
      let outcome = if task.prompt == "" {
        assertions.push({
          description: "task '\{task.id}' declares a prompt",
          passed: false,
          detail: "no prompt in the task file",
        })
        LiveRunOutcome::infrastructure_failure(
          "task '\{task.id}' has no prompt",
        )
      } else {
        runner(task.prompt, sandbox)
      }
      for assertion in evaluate_checks(task, sandbox) {
        assertions.push(assertion)
      }
      let mut passed = true
      for assertion in assertions {
        if !assertion.passed {
          passed = false
        }
      }
      let transcript_path = @path.Path::join(
        transcripts_dir,
        @path.Path("\{task.id}-\{trial}.txt"),
      ).to_string()
      write_transcript(transcript_path, task, trial, outcome)
      results.push({
        task_id: task.id,
        goal: task.goal,
        trial,
        passed,
        assertions,
        outcome,
        transcript_path,
      })
    }
  }
  { results, nominal_trials: nominal, }
}

///|
/// Persist one trial's transcript beside the results. A write failure is
/// reported on stdout by the caller through the outcome, but is not fatal —
/// the transcript is evidence, not the verdict.
fn write_transcript(
  path : String,
  task : HarnessTask,
  trial : Int,
  outcome : LiveRunOutcome,
) -> Unit {
  let lines : Array[String] = [
    "# task \{task.id} (trial \{trial})",
    "",
    "goal: \{task.goal}",
    "acceptance: \{task.acceptance}",
    "prompt: \{task.prompt}",
    "",
    "status: \{outcome.status}",
    "iterations: \{outcome.iterations}",
    "cost_usd: \{outcome.cost_usd} (\{outcome.cost_source})",
    "tokens: prompt=\{outcome.prompt_tokens} completion=\{outcome.completion_tokens}",
  ]
  match outcome.error {
    Some(err) => lines.push("error: \{err}")
    None => ()
  }
  lines.push("")
  lines.push("## tool calls")
  if outcome.tool_steps.length() == 0 {
    lines.push("(none)")
  } else {
    for step in outcome.tool_steps {
      lines.push("- \{step}")
    }
  }
  lines.push("")
  lines.push("## transcript")
  lines.push(outcome.transcript)
  @fs.write_string_to_file(path, lines.join("\n")) catch {
    _ => ()
  }
}

///|
/// Machine-readable artifact for stdout: the shared score vector plus the
/// live-only detail (per-trial status/cost/tools, infrastructure failures).
pub fn LiveReport::to_score_json(
  self : LiveReport,
  mode : String,
  trials : Int,
) -> Json {
  let base = self
    .as_harness_report()
    .to_score_json(mode, trials, cost_usd=self.total_cost())
  let fields = match base {
    Object(found) => found
    other => return other
  }
  let mut prompt_tokens = 0
  let mut completion_tokens = 0
  let mut cost_source = "none"
  let trials_json : Array[Json] = []
  for result in self.results {
    prompt_tokens = prompt_tokens + result.outcome.prompt_tokens
    completion_tokens = completion_tokens + result.outcome.completion_tokens
    cost_source = result.outcome.cost_source
    let failures : Array[Json] = []
    for assertion in result.assertions {
      if !assertion.passed {
        let detail = if assertion.detail == "" {
          ""
        } else {
          " — " + assertion.detail
        }
        failures.push(Json::string(assertion.description + detail))
      }
    }
    trials_json.push(
      Json::object({
        "task_id": result.task_id.to_json(),
        "trial": result.trial.to_json(),
        "passed": Json::boolean(result.passed),
        "status": result.outcome.status.to_json(),
        "iterations": result.outcome.iterations.to_json(),
        "cost_usd": Json::number(result.outcome.cost_usd),
        "tool_calls": Json::array(
          result.outcome.tool_steps.map(fn(step) { Json::string(step) }),
        ),
        "failures": Json::array(failures),
        "transcript_path": result.transcript_path.to_json(),
      }),
    )
  }
  fields["infrastructure_errors"] = self.infrastructure_errors().to_json()
  fields["prompt_tokens"] = prompt_tokens.to_json()
  fields["completion_tokens"] = completion_tokens.to_json()
  fields["cost_source"] = cost_source.to_json()
  fields["trials_detail"] = Json::array(trials_json)
  Json::object(fields)
}

///|
/// Committed evidence for a live run: per-trial outcomes, the score vector and
/// the failure text, with the tool sequence so a failure can be attributed
/// without re-running.
pub fn LiveReport::to_markdown(
  self : LiveReport,
  mode : String,
  trials : Int,
) -> String {
  let score = self.as_harness_report().score(trials, cost_usd=self.total_cost())
  let lines : Array[String] = []
  lines.push("# cmd eval report（\{mode}）")
  lines.push("")
  lines.push(
    "| 任务 | trial | 状态 | 迭代 | 工具调用 | 成本(USD) | 断言 | 结果 |",
  )
  lines.push("|---|---|---|---|---|---|---|---|")
  for result in self.results {
    let mut passed_assertions = 0
    for assertion in result.assertions {
      if assertion.passed {
        passed_assertions = passed_assertions + 1
      }
    }
    lines.push(
      "| \{result.task_id} | \{result.trial} | \{result.outcome.status} | \{result.outcome.iterations} | \{result.outcome.tool_steps.length()} | \{result.outcome.cost_usd} | \{passed_assertions}/\{result.assertions.length()} | \{if result.passed { "PASS" } else { "FAIL" }} |",
    )
  }
  lines.push("")
  lines.push("## 评分向量")
  lines.push("")
  lines.push("| 维度 | 值 |")
  lines.push("|---|---|")
  lines.push(
    "| 完成率（至少一次通过的任务 / 任务数） | \{score.completion_rate()} |",
  )
  lines.push(
    "| 验证纪律（通过断言 / 全部断言） | \{score.verification_rate()} |",
  )
  lines.push(
    "| 可重复性（trials 全部一致的任务 / 任务数，trials=\{trials}） | \{score.repeatability()} |",
  )
  let mut prompt_total = 0
  let mut completion_total = 0
  for result in self.results {
    prompt_total = prompt_total + result.outcome.prompt_tokens
    completion_total = completion_total + result.outcome.completion_tokens
  }
  lines.push(
    "| 成本（USD，模型估算，cost_source） | \{score.cost_usd} |",
  )
  lines.push(
    "| token 用量（prompt + completion 合计） | \{prompt_total} + \{completion_total} |",
  )
  lines.push(
    "| 基础设施失败 trial 数（传输/auth/重试耗尽） | \{self.infrastructure_errors()} |",
  )
  lines.push("")
  lines.push(
    "> 完成率按「至少一次通过」计（真模型有随机性），可重复性才要求 trial 全部一致。",
  )
  if score.cost_usd == 0.0 && prompt_total > 0 {
    lines.push(">")
    lines.push(
      "> 成本为 0 是因为该模型没有定价条目（`cost_source` 已如实标注）；token 用量是本次运行的真实成本代理。",
    )
  }
  lines.push("")
  lines.push("## 逐 trial 明细")
  lines.push("")
  for result in self.results {
    let verdict = if result.passed { "PASS" } else { "FAIL" }
    lines.push("### \{result.task_id} · trial \{result.trial}（\{verdict}）")
    lines.push(
      "- 状态 `\{result.outcome.status}`，迭代 \{result.outcome.iterations}，成本 \{result.outcome.cost_usd}（\{result.outcome.cost_source}），token \{result.outcome.prompt_tokens}+\{result.outcome.completion_tokens}",
    )
    match result.outcome.error {
      Some(err) => lines.push("- 运行错误：\{err}")
      None => ()
    }
    if result.outcome.tool_steps.length() == 0 {
      lines.push("- 工具调用：无")
    } else {
      for step in result.outcome.tool_steps {
        lines.push("- 工具：`\{step}`")
      }
    }
    if result.transcript_path != "" {
      lines.push("- transcript：`\{result.transcript_path}`")
    }
    for assertion in result.assertions {
      if !assertion.passed {
        let detail = if assertion.detail == "" {
          ""
        } else {
          " — " + assertion.detail
        }
        lines.push("- [ ] " + assertion.description + detail)
      }
    }
    lines.push("")
  }
  lines.join("\n")
}

// ── Real runner ─────────────────────────────────────────────────────────────

///|
/// Build the real, model-driven runner: a fresh `Agent` per trial, pinned to
/// `sandbox` as its working directory, with a registry narrowed to
/// `live_tool_allowlist` and every observable event captured for the report.
///
/// `chdir` (default true) moves the *process* working directory into the sandbox
/// for the duration of the trial, because the file tools resolve relative paths
/// against the process cwd — the same reason `cmd` chdirs for `--path`. The
/// default is what a live run needs: the model emits paths like `config.yaml`.
/// A caller that must not move the process cwd (a test running concurrently
/// with other cwd-sensitive work) passes `chdir=false` and drives the model
/// with absolute paths instead.
pub fn make_agent_live_runner(
  config : @config.AgentConfig,
  chdir? : Bool = true,
) -> async (String, String) -> LiveRunOutcome {
  // The eval owns this config: a live trial must never block on a confirmation
  // prompt (there is no TTY to answer it).
  config.permission_mode = @config.AutoApprove
  async fn(prompt : String, sandbox : String) -> LiveRunOutcome {
    let model = match config.current_model() {
      Some(found) => found
      None =>
        return LiveRunOutcome::infrastructure_failure(
          "no model configured: set MBOPENCLACKY_API_KEY/BASE_URL/MODEL, or DEEPSEEK_API_KEY",
        )
    }
    let api_type = if model.anthropic_format {
      @config.AnthropicMessages
    } else {
      @config.Providers::api_type_for_model(model.base_url, model.model)
    }
    let client = @client.Client::new(
      model.api_key,
      model.base_url,
      model.model,
      api_type,
    )
    let agent = @agent.Agent::new(
      @agent.generate_session_id(),
      "Capability Eval",
      sandbox,
      client,
      config,
    )
    agent.tool_registry = live_registry()
    let transcript : Array[String] = []
    let tool_steps : Array[String] = []
    let tokens : Array[Int] = [0, 0]
    agent.hook_manager.register(fn(evt : @agent.HookEvent) {
      match evt {
        @agent.StreamChunk(text) => transcript.push(text)
        @agent.ToolExecuting(name, args) =>
          tool_steps.push("\{name} \{truncate_text(args, 120)}")
        @agent.ToolExecuted(_name, entry) =>
          if entry.is_error {
            tool_steps.push("!! error: \{truncate_text(entry.content, 160)}")
          }
        @agent.UsageUpdated(data) => {
          tokens[0] = tokens[0] + data.prompt_tokens
          tokens[1] = tokens[1] + data.completion_tokens
        }
        @agent.ErrorOccurred(message) =>
          transcript.push("\n[error] \{message}\n")
        @agent.WarningOccurred(message) =>
          transcript.push("\n[warn] \{message}\n")
        @agent.AfterIteration(number) =>
          transcript.push("\n── iteration \{number} ──\n")
        _ => ()
      }
    })
    let original_dir = @utils.current_dir()
    if chdir {
      @utils.change_dir(sandbox)
    }
    let result = agent.run(prompt) catch {
      err => {
        if chdir {
          @utils.change_dir(original_dir)
        }
        let text = @debug.to_string(err)
        return LiveRunOutcome::{
          status: "Error",
          iterations: agent.iterations,
          cost_usd: agent.total_cost,
          cost_source: @agent.CostSource::to_string_value(agent.cost_source),
          prompt_tokens: tokens[0],
          completion_tokens: tokens[1],
          tool_steps,
          transcript: transcript.join(""),
          error: Some(text),
        }
      }
    }
    if chdir {
      @utils.change_dir(original_dir)
    }
    {
      status: result.status.to_string_value(),
      iterations: result.iterations,
      cost_usd: result.total_cost_usd,
      cost_source: @agent.CostSource::to_string_value(result.cost_source),
      prompt_tokens: tokens[0],
      completion_tokens: tokens[1],
      tool_steps,
      transcript: transcript.join(""),
      error: result.error,
    }
  }
}

///|
/// The default registry narrowed to `live_tool_allowlist`.
fn live_registry() -> @tool.ToolRegistry {
  let full = @tool.make_default_registry()
  let restricted = @tool.ToolRegistry::new()
  for name in live_tool_allowlist {
    match full.get_resolved(name) {
      Some(tool) => restricted.register(tool)
      None => ()
    }
  }
  restricted
}

///|
/// Char-safe truncation for log lines (MoonBit strings are indexed by code
/// unit, so slicing at a byte offset would split multibyte characters).
fn truncate_text(text : String, limit : Int) -> String {
  let chars = text.to_array()
  if chars.length() <= limit {
    return text.split("\n").collect().join(" ")
  }
  let head : Array[Char] = []
  for i = 0; i < limit; i = i + 1 {
    head.push(chars[i])
  }
  String::from_array(head) + "…"
}
