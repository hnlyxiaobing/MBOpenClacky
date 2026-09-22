///| `cmd eval --live` — model-driven capability evaluation (layer 8).
///
/// `--offline` answers "does the tool layer work on a scripted sequence"; this
/// path answers the question mock tests cannot: "can a real model drive the
/// tools to a correct result". Both read the same task schema and the same
/// `checks`, so the two score vectors stay comparable — only the source of the
/// steps differs (script vs model).
///
/// stdout carries the score JSON as its **last line** (the canonical copy is
/// also written to `<results_dir>/score.json`). It is not the *only* thing on
/// stdout: the streaming client emits a `[stream-summary]` diagnostic per call,
/// and that diagnostic goes to stdout even though its own comment and the spec
/// behind it say stderr (`lib/agent/llm_caller.mbt:685`, registered as a
/// known gap). Consumers should read the last line, or `score.json`.
///
/// The committed evidence is the markdown report (default
/// `docs/eval/<date>.md`); per-trial transcripts and the JSON copy land under
/// `_build/capability/results/<stamp>/`. The benchmark never runs in CI: real
/// models are stochastic and cost money (see `test/capability/README.md`).

///|
/// A resolved model for a live run, plus the provenance recorded in the
/// evidence so a result can be attributed without re-reading the environment.
pub(all) struct LiveModel {
  config : @config.AgentConfig
  /// Where the model came from, e.g. "MBOPENCLACKY_* env" / "config.toml".
  source : String
  model : String
  base_url : String
}

///|
/// First non-empty value among the given environment variables.
fn live_env_value(keys : Array[String]) -> String? {
  for key in keys {
    match @utils.env_var(key) {
      Some(value) =>
        if !value.trim().is_empty() {
          return Some(value.trim().to_owned())
        }
      None => ()
    }
  }
  None
}

///|
/// `MBOPENCLACKY_*` as an explicit override.
///
/// `AgentConfig::apply_env_overlay` only builds a model from these variables
/// when *no* model is configured anywhere, so on a machine that has a
/// `config.toml` they would be ignored — which would make the benchmark's model
/// depend on which config file happens to exist. A benchmark has to be
/// selectable, so the live path honours them first, using the same defaults and
/// the same `MBOPENCLACKY_ANTHROPIC_FORMAT` convention as the rest of the CLI
/// (set it to `false` for an OpenAI-compatible endpoint such as DeepSeek).
fn mbopenclacky_env_model() -> LiveModel? {
  match live_env_value(["MBOPENCLACKY_API_KEY"]) {
    None => None
    Some(api_key) => {
      let base_url = live_env_value(["MBOPENCLACKY_BASE_URL"]).unwrap_or(
        "https://api.anthropic.com",
      )
      let model_name = live_env_value(["MBOPENCLACKY_MODEL"]).unwrap_or(
        "claude-sonnet-4-5",
      )
      let anthropic_format = match
        live_env_value(["MBOPENCLACKY_ANTHROPIC_FORMAT"]) {
        Some(v) => v.to_lower() != "false"
        None => true
      }
      let config = @config.AgentConfig::default()
      config.models = [
        {
          id: "default",
          type_: Some("default"),
          api_key,
          base_url,
          model: model_name,
          anthropic_format,
          runtime_id: "default",
          media_type: None,
        },
      ]
      config.current_model_id = Some("default")
      Some({
        config,
        source: "MBOPENCLACKY_* env",
        model: model_name,
        base_url,
      })
    }
  }
}

///|
/// The model from the project's own configuration file / `CLACKY_*` env, i.e.
/// what `mbopenclacky -m` would use.
fn configured_live_model() -> LiveModel? {
  let config = @config.AgentConfig::load_default() catch {
    _ => @config.AgentConfig::default()
  }
  match config.current_model() {
    Some(model) =>
      Some({
        config,
        source: if config.env_source == "env" {
          "CLACKY_*/OPENCLACKY_* env"
        } else {
          "~/.mbopenclacky/config.toml"
        },
        model: model.model,
        base_url: model.base_url,
      })
    None => None
  }
}

///|
/// The DeepSeek fallback: a machine whose key lives in `DEEPSEEK_API_KEY` /
/// `DEEPSEEK` can run the benchmark without exporting anything else.
///
/// The defaults are verified against the provider rather than guessed:
/// `deepseek-flash` is the cheap tier and it does return `tool_calls` (both
/// checked with the live key), while `deepseek-chat` — the legacy preset's
/// default — is not served to every account. Both remain overridable.
fn deepseek_fallback() -> LiveModel? {
  match live_env_value(["DEEPSEEK_API_KEY", "DEEPSEEK"]) {
    None => None
    Some(api_key) => {
      let base_url = live_env_value(["DEEPSEEK_BASE_URL"]).unwrap_or(
        "https://api.deepseek.com",
      )
      let model_name = live_env_value(["DEEPSEEK_MODEL"]).unwrap_or(
        "deepseek-flash",
      )
      let config = @config.AgentConfig::default()
      config.models = [
        {
          id: "default",
          type_: Some("default"),
          api_key,
          base_url,
          model: model_name,
          anthropic_format: false,
          runtime_id: "default",
          media_type: None,
        },
      ]
      config.current_model_id = Some("default")
      Some({
        config,
        source: "DEEPSEEK_* env (fallback)",
        model: model_name,
        base_url,
      })
    }
  }
}

///|
/// Resolve the model for a live run.
///
/// Order: explicit `MBOPENCLACKY_*` env (so a benchmark can always be pointed
/// at a specific model), then the project configuration
/// (`~/.mbopenclacky/config.toml` / `CLACKY_*`), then the DeepSeek fallback.
/// Returns None when nothing is configured — the caller reports that honestly
/// instead of pretending a run happened.
pub fn resolve_live_model() -> LiveModel? {
  match mbopenclacky_env_model() {
    Some(found) => Some(found)
    None =>
      match configured_live_model() {
        Some(found) => Some(found)
        None => deepseek_fallback()
      }
  }
}

///|
/// Filesystem-safe form of an ISO timestamp (Windows rejects `:` in names).
fn live_stamp_slug(stamp : String) -> String {
  let out : Array[Char] = []
  for c in stamp.to_array() {
    if c == ':' {
      out.push('-')
    } else if c == ' ' {
      out.push('_')
    } else {
      out.push(c)
    }
  }
  String::from_array(out)
}

///|
/// Display a path with forward slashes: the report is committed evidence read
/// on any platform, and `@path` separators are platform-specific.
fn live_display_path(path : String) -> String {
  let out : Array[Char] = []
  for c in path.to_array() {
    if c == '\\' {
      out.push('/')
    } else {
      out.push(c)
    }
  }
  String::from_array(out)
}

///|
/// Provenance banner prepended to the committed report: without it the numbers
/// cannot be attributed later (which model, which task set, how many trials).
fn live_report_header(
  stamp : String,
  resolved : LiveModel,
  tasks_dir : String,
  task_count : Int,
  trials : Int,
) -> String {
  let lines : Array[String] = []
  lines.push(
    "> 真模型能力评测（层 8）。规程与判分口径见 `test/capability/README.md`；逐 trial transcript 落在 `_build/capability/results/`，不入库。",
  )
  lines.push(">")
  lines.push("- 运行时间：\{stamp}")
  lines.push("- 模型：`\{resolved.model}` @ `\{resolved.base_url}`")
  lines.push("- 配置来源：\{resolved.source}")
  lines.push(
    "- 任务集：`\{live_display_path(tasks_dir)}`（\{task_count} 条）",
  )
  lines.push("- 重复：每任务 \{trials} 次")
  lines.push(
    "- 工具面：限制为 `file_reader`/`write`/`edit`/`grep`/`glob`（无 shell、无网络）",
  )
  lines.push("- 不进 CI：真模型有随机性且产生费用")
  lines.push(
    "- 解读：任务集小且偏基础（单文件读改为主）。全通过只说明「链路 + 该模型可用」，不足以推断模型强；要形成区分度需按 `test/capability/README.md` 扩到 20~30 条并加入更难的类别。",
  )
  lines.push("")
  lines.push("")
  lines.join("\n")
}

///|
/// Run the model-driven benchmark: resolve the model, run every task `trials`
/// times through the real ReAct loop, then emit the evidence.
///
/// Exit code: 0 when the batch ran and no trial failed at the infrastructure
/// level; 1 when there is no model, no task set, or a trial's run ended in
/// `Error` (transport/auth/exhausted retries). A trial that ran but failed its
/// `checks` is *data*, not a command failure, so it does not set the exit code —
/// it is reported in the vector, the JSON and the markdown.
pub async fn run_live_eval(repo : String, sub : @clap.SimpleValue) -> Unit {
  // 1. Task set. Checked before the model so a bad invocation fails on input,
  // never on a paid request.
  let tasks_dir = match get_named_arg(sub, "tasks") {
    Some(dir) => dir
    None =>
      @path.Path::join(@path.Path(repo), @path.Path("test/capability/tasks")).to_string()
  }
  // A missing directory is reported by this command, not by the filesystem
  // layer (whose diagnostic would otherwise reach stderr and muddy the CLI's
  // clean-stderr contract).
  let tasks = if @fs.path_exists(tasks_dir) {
    @eval.load_harness_tasks(tasks_dir)
  } else {
    []
  }
  if tasks.length() == 0 {
    println("eval --live: no task files found in \{tasks_dir}")
    @sys.exit(1)
    return
  }
  let trials_override : Int? = match get_named_arg(sub, "trials") {
    Some(text) => Some(@string.parse_int(text.trim()) catch { _ => 0 })
    None => None
  }
  match trials_override {
    Some(n) =>
      if n <= 0 {
        println("eval --live: --trials must be >= 1")
        @sys.exit(2)
        return
      }
    None => ()
  }
  // 2. Model.
  let resolved = match resolve_live_model() {
    Some(found) => found
    None => {
      println(
        "eval --live: no model configured, so the capability benchmark was not run.",
      )
      println(
        "  set MBOPENCLACKY_API_KEY (optionally MBOPENCLACKY_BASE_URL / MBOPENCLACKY_MODEL;",
      )
      println(
        "  add MBOPENCLACKY_ANTHROPIC_FORMAT=false for an OpenAI-compatible endpoint),",
      )
      println(
        "  or export DEEPSEEK_API_KEY (defaults to https://api.deepseek.com + deepseek-flash),",
      )
      println("  or add a model to ~/.mbopenclacky/config.toml.")
      @sys.exit(1)
      return
    }
  }
  // 3. Output locations. Absolute: the runner moves the process cwd into each
  // trial sandbox, and `@utils.ensure_dir` creates the intermediate levels.
  let repo_abs = @path.Path::resolve(@path.Path(repo)).to_string()
  let stamp = @agent.ms_to_iso8601(@agent.current_time_ms())
  let sandbox_root = @path.Path::join(
    @path.Path(repo_abs),
    @path.Path("_build/capability/sandbox"),
  ).to_string()
  let results_dir = @path.Path::join(
    @path.Path(repo_abs),
    @path.Path("_build/capability/results/\{live_stamp_slug(stamp)}"),
  ).to_string()
  let out_dir = match get_named_arg(sub, "out") {
    Some(dir) => dir
    None =>
      @path.Path::join(@path.Path(repo_abs), @path.Path("docs/eval")).to_string()
  }
  @utils.ensure_dir(sandbox_root)
  @utils.ensure_dir(results_dir)
  @utils.ensure_dir(out_dir)
  // 4. Run.
  let runner = @eval.make_agent_live_runner(resolved.config)
  let report = @eval.run_live_batch(
    tasks, sandbox_root, results_dir, trials_override, runner,
  )
  // 5. Evidence.
  let trials = report.nominal_trials
  let score_json = report.to_score_json("live", trials)
  let date = if stamp.length() >= 10 {
    stamp[:10].to_owned()
  } else {
    "unknown"
  }
  let report_path = @path.Path::join(
    @path.Path(out_dir),
    @path.Path("\{date}.md"),
  ).to_string()
  let markdown = live_report_header(
      stamp,
      resolved,
      tasks_dir,
      tasks.length(),
      trials,
    ) +
    report.to_markdown("live", trials)
  @fs.write_string_to_file(report_path, markdown) catch {
    err =>
      println("eval --live: could not write report: \{@debug.to_string(err)}")
  }
  let json_path = @path.Path::join(
    @path.Path(results_dir),
    @path.Path("score.json"),
  ).to_string()
  let json_text = eval_attach_report_path(score_json, report_path).stringify()
  @fs.write_string_to_file(json_path, json_text) catch {
    _ => ()
  }
  println(json_text)
  if report.infrastructure_errors() > 0 {
    @sys.exit(1)
  }
}
