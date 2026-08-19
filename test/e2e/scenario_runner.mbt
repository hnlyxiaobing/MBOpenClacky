///| Scenario Runner —— diff-harness `scripts/run_scenario.py` 的 MoonBit 移植版。
///
/// 在测试进程内完成整条链路：
///   建临时工作目录并写入 fixture 文件
///   → 起 raw TCP mock server（随机端口）回放剧本
///   → 用 base_url 注入构造真实 Client + Agent（AutoApprove，对齐 ruby 非交互模式）
///   → agent.run(prompt) 跑完整 ReAct 循环
///   → 收集：mock 记录的请求体序列（含到达时间）、工作目录文件终态、最终回复
///
/// 与 diff-harness 的刻意差异：
/// - diff-harness 以子进程跑 agent、cwd=workdir，工具的相对路径按进程 CWD 解析；
///   本 runner 与被测 agent 同进程（CWD=项目根），因此回放前把剧本 tool_calls
///   arguments 里的相对 path 重写为临时目录下的绝对路径（runner 侧的适配，
///   对齐 diff-harness 的 workdir 语义，不改变被测行为）。
/// - HOME / USERPROFILE 指向临时目录，避免读写真实用户配置与会话目录
///   （对齐 diff-harness 的 HOME 隔离）。
/// - 带超时保护（默认 120s），防止压缩等未对齐路径挂死整个测试套件。

///|
/// 一次剧本运行的采集结果。
pub(all) struct ScenarioOutcome {
  /// mock server 记录的请求体原文（JSON 字符串），按到达顺序。
  requests : Array[String]
  /// 每个请求的到达时间（ms），用于退避间隔断言。
  request_times : Array[Int64]
  /// 运行结局："success" / "error" / "timeout"。
  /// 对应 diff-harness 的 exit_code：ruby exit=0 ↔ success；exit=1 ↔ error。
  status : String
  /// 最后一条 assistant 消息的文本（agent 的最终回复）。
  final_text : String
  /// 工作目录文件终态 {相对路径: 内容}（清理前采集）。
  final_files : Map[String, String]
}

///|
/// 临时目录唯一名序号。
let dir_serial : Ref[Int] = { val: 0 }

///|
/// 取 JSON 对象的字段（非废弃 API 的本地封装；core/json 的 Json::value 已废弃）。
fn jget(json : Json, key : String) -> Json? {
  if json is Object(obj) {
    obj.get(key)
  } else {
    None
  }
}

///|
/// 取 JSON 字符串值（Json::as_string 已废弃）。
fn jstr(json : Json) -> String? {
  if json is String(s) {
    Some(s)
  } else {
    None
  }
}

///|
/// 取 JSON 数值（Json::as_number 已废弃）。
fn jnum(json : Json) -> Double? {
  if json is Number(n, ..) {
    Some(n)
  } else {
    None
  }
}

///|
/// 取 JSON 数组（Json::as_array 已废弃）。
fn jarr(json : Json) -> Array[Json]? {
  if json is Array(arr) {
    Some(arr)
  } else {
    None
  }
}

///|
/// 取 JSON 对象（Json::as_object 已废弃）。
fn jobj(json : Json) -> Map[String, Json]? {
  if json is Object(obj) {
    Some(obj)
  } else {
    None
  }
}

///|
/// 系统临时目录（统一为正斜杠）。
fn temp_base() -> String {
  let raw = match @env.get_env_var("TEMP") {
    Some(t) => t
    None =>
      match @env.get_env_var("TMPDIR") {
        Some(t) => t
        None => "/tmp"
      }
  }
  raw.replace_all(old="\\", new="/")
}

///|
/// 读取剧本 JSON，返回 steps 数组（元素含 response 字段）。
fn load_scenario_steps(name : String) -> Array[Json] {
  let path = "test/e2e/scenarios/\{name}.json"
  let text = @fs.read_file_to_string(path) catch {
    _ => {
      println(
        "FATAL: 无法读取剧本文件 \{path}（moon test 的 CWD 应为项目根）",
      )
      panic()
    }
  }
  let json = @json.parse(text) catch { _ => panic() }
  match jget(json, "steps") {
    Some(s) =>
      match jarr(s) {
        Some(arr) => arr
        None => panic()
      }
    None => panic()
  }
}

///|
/// 判断路径是否为绝对路径（POSIX 以 / 开头；Windows 带盘符冒号或以 \ 开头）。
fn is_abs_path(p : String) -> Bool {
  p.has_prefix("/") || p.has_prefix("\\") || p.contains(":")
}

///|
/// 把剧本 tool_calls arguments 里的相对 path 重写为 workdir 下的绝对路径
/// （就地修改 JSON；对齐 diff-harness 中 agent 子进程 cwd=workdir 的语义）。
fn rewrite_step_paths(steps : Array[Json], workdir : String) -> Unit {
  for step in steps {
    guard jget(step, "response") is Some(resp) else { continue }
    guard jget(resp, "tool_calls") is Some(tcs_json) else { continue }
    guard jarr(tcs_json) is Some(tcs) else { continue }
    for tc in tcs {
      guard jobj(tc) is Some(tc_obj) else { continue }
      guard tc_obj.get("arguments") is Some(args_json) else { continue }
      guard jobj(args_json) is Some(args) else { continue }
      if args.get("path") is Some(p) && jstr(p) is Some(ps) {
        if !is_abs_path(ps) {
          args["path"] = "\{workdir}/\{ps}".to_json()
        }
      }
    }
  }
}

///|
/// 跑一个剧本，采集链路产物。
///
/// - `name`：剧本名（不含 .json），剧本文件为 test/e2e/scenarios/<name>.json。
/// - `files`：工作目录初始文件 {相对路径: 内容}（对齐 diff-harness FIXTURES）。
/// - `prompt`：用户提示词。
/// - `configure`：剧本级配置改写（如 005 的 compression_threshold=1）。
/// - `timeout_ms`：超时保护；超时记为 status="timeout"（对齐 diff-harness exit=-1）。
pub async fn run_scenario(
  name : String,
  files : Array[(String, String)],
  prompt : String,
  configure? : (@config.AgentConfig) -> Unit = fn(_) { () },
  timeout_ms? : Int = 120_000,
) -> ScenarioOutcome {
  // ── 1. 准备干净工作目录与隔离 HOME ────────────────────────────────
  dir_serial.val = dir_serial.val + 1
  let stamp = "\{now_ms()}_\{dir_serial.val}"
  let workdir = "\{temp_base()}/mbe2e_\{name}_\{stamp}"
  let home = "\{temp_base()}/mbe2e_home_\{name}_\{stamp}"
  @fs.create_dir(workdir) catch {
    _ => panic()
  }
  @fs.create_dir(home) catch {
    _ => ()
  }
  @env.set_env_var("HOME", home)
  @env.set_env_var("USERPROFILE", home)
  for f in files {
    let (rel, content) = f
    @fs.write_string_to_file("\{workdir}/\{rel}", content) catch {
      _ => panic()
    }
  }
  // ── 2. 加载剧本并重写相对路径 ─────────────────────────────────────
  let steps = load_scenario_steps(name)
  rewrite_step_paths(steps, workdir)
  // ── 3. 起 mock server，构造真实 Client + Agent ────────────────────
  let server = MockLlmServer::new(steps)
  let client = @client.Client::new(
    "mock-key",
    "http://127.0.0.1:\{server.port()}",
    "mock-model",
    @config.OpenAICompletions,
  )
  let config = @config.AgentConfig::default()
  config.permission_mode = @config.AutoApprove
  config.memory_update_enabled = false
  configure(config)
  let agent = @agent.Agent::new("e2e-\{name}", "e2e", workdir, client, config)
  // ── 4. 跑完整 ReAct 循环（带超时保护）─────────────────────────────
  let mut status = "success"
  @async.with_task_group(async fn(group) {
    group.spawn_bg(async fn() { server.serve() })
    let result = @async.with_timeout_opt(timeout_ms, async fn() {
      agent.run(prompt)
    }) catch {
      @async.TimeoutError => {
        status = "timeout"
        None
      }
      _ => {
        // agent 失败（如熔断后 raise）：对齐 diff-harness 的 exit=1
        status = "error"
        None
      }
    }
    match result {
      Some(r) => if r.status != @agent.Success { status = "error" }
      None => ()
    }
    server.shutdown()
  })
  // ── 5. 采集产物 ───────────────────────────────────────────────────
  let requests : Array[String] = []
  let request_times : Array[Int64] = []
  for r in server.requests {
    requests.push(r.body)
    request_times.push(r.at_ms)
  }
  let mut final_text = ""
  for m in agent.history.all() {
    if m.role == @message.Assistant {
      final_text = @agent.content_to_text(m.content)
    }
  }
  // 采集工作目录文件终态（在清理之前）
  let final_files : Map[String, String] = Map([])
  let entries = @fs.read_dir(workdir) catch { _ => [] }
  for entry in entries {
    let content = @fs.read_file_to_string("\{workdir}/\{entry}") catch {
      _ => continue
    }
    final_files[entry] = content
  }
  // ── 6. 清理临时目录（尽力而为，失败不阻塞测试）────────────────────
  cleanup_dir(workdir)
  cleanup_dir(home)
  { requests, request_times, status, final_text, final_files }
}

///|
/// 删除目录下的所有文件后删除目录（仅处理一层，失败静默）。
fn cleanup_dir(dir : String) -> Unit {
  let entries = @fs.read_dir(dir) catch { _ => return }
  for entry in entries {
    @fs.remove_file("\{dir}/\{entry}") catch {
      _ => ()
    }
  }
  @fs.remove_dir(dir) catch {
    _ => ()
  }
}

///|
/// 从最后一个请求的 messages 中提取完整的 assistant tool 调用名序列。
/// （请求体是累积历史，最后一个请求包含全部轮次。）
pub fn tool_sequence_of(requests : Array[String]) -> Array[String] {
  let seq : Array[String] = []
  if requests.is_empty() {
    return seq
  }
  let last = @json.parse(requests[requests.length() - 1]) catch {
    _ => return seq
  }
  guard jget(last, "messages") is Some(msgs_json) else { return seq }
  guard jarr(msgs_json) is Some(msgs) else { return seq }
  for m in msgs {
    guard jget(m, "role") is Some(r) && jstr(r) == Some("assistant") else {
      continue
    }
    guard jget(m, "tool_calls") is Some(tcs_json) else { continue }
    guard jarr(tcs_json) is Some(tcs) else { continue }
    for tc in tcs {
      guard jget(tc, "function") is Some(f) else { continue }
      if jget(f, "name") is Some(n) && jstr(n) is Some(name) {
        seq.push(name)
      }
    }
  }
  seq
}

///|
/// 断言辅助：读取终态文件内容。
pub fn ScenarioOutcome::file(self : ScenarioOutcome, rel : String) -> String? {
  self.final_files.get(rel)
}
