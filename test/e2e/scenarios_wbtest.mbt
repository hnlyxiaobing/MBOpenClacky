///| 链路层回归测试 —— diff-harness P3 剧本的 MB 侧内生移植。
///
/// 每个剧本一个 async test：测试内起真实 TCP mock server（随机端口）回放剧本，
/// 用 base_url 注入构造真实 Client + Agent，跑完整 ReAct 循环，
/// 断言点来自冻结的 ruby 基线（见 golden.mbt）。
///
/// known-failure 纪律（继承 diff-harness AGENTS.md 与 test/diff/known_failure.mbt）：
/// - 未修复 BUG 对应的断言用 `if @diff.known_failure("BUG-NNNN") { return }` 隔离；
/// - 禁止无编号隔离；每处闸门注释引用 BUG 编号与 diff-harness 证据；
/// - BUG 修复并从 known_failure_bug_ids 移除编号后，断言自动生效。

///|
/// 通用断言：完成状态 + 请求数 + 工具序列 + 文件终态 + 最终回复。
fn assert_golden(outcome : ScenarioOutcome, g : Golden) -> Unit raise {
  let expected_status = if g.expect_success { "success" } else { "error" }
  @debug.assert_eq(outcome.status, expected_status)
  @debug.assert_eq(outcome.requests.length(), g.request_count)
  if !g.tool_sequence.is_empty() {
    @debug.assert_eq(tool_sequence_of(outcome.requests), g.tool_sequence)
  }
  for f in g.final_files {
    let (rel, content) = f
    @debug.assert_eq(outcome.file(rel), Some(content))
  }
  if g.final_text.length() > 0 {
    @debug.assert_eq(outcome.final_text, g.final_text)
  }
}

///|
/// 断言退避间隔：request_times 相邻差值应处于合理量级窗口内。
///
/// 端到端场景不依赖 wall-clock 精确值：在 CI 等受限环境下，`@async.sleep`
/// 的实际等待会因 CPU 争抢而膨胀（实测 5s 退避可膨胀至 ~14s；CI run
/// 32232679372 实测 10.3s）。因此这里只断言"退避确实发生且量级合理"
/// （[2s, 20s]）——既排除退避失效（≈0ms 立即重试），也排除指数退避失控
/// （第 2 次即 10s、第 3 次 20s，挂死风险）。
/// 固定 5s 退避的精确断言由 lib/agent/llm_caller_wbtest.mbt 的
/// "retry_delay_ms fixed 5s" 单元测试承担（无 wall-clock 依赖）。
///
/// `expected_ms`/`tolerance_ms` 参数保留以兼容调用点；窗口取全局
/// [min_ms, max_ms] 边界（预期值 5s 与真实膨胀都在窗口内）。
fn assert_retry_intervals(
  times : Array[Int64],
  expected_ms : Array[Int],
  _tolerance_ms : Int,
) -> Unit {
  if times.length() < expected_ms.length() + 1 {
    println(
      "FATAL: 请求数不足，无法断言退避间隔: \{times.length()}",
    )
    panic()
  }
  let min_ms = 2000
  let max_ms = 20000
  for i in 0..<expected_ms.length() {
    let delta = (times[i + 1] - times[i]).to_int()
    if delta < min_ms || delta > max_ms {
      println(
        "FATAL: 退避间隔越界: req\{i + 1}→req\{i + 2} = \{delta}ms，期望量级 [\{min_ms}, \{max_ms}]ms，times=\{Repr(times)}",
      )
      panic()
    }
  }
}

///|
/// 断言所有以 "{" 开头的 tool 消息内容是合法 JSON（ruby 的工具错误结果为
/// 标准 JSON；MB 的 `{error: ...}` 缺引号非合法 JSON —— BUG-0040）。
fn assert_tool_results_valid_json(requests : Array[String]) -> Unit {
  for req in requests {
    let body = @json.parse(req) catch { _ => continue }
    guard jget(body, "messages") is Some(msgs_json) else { continue }
    guard jarr(msgs_json) is Some(msgs) else { continue }
    for m in msgs {
      guard jget(m, "role") is Some(r) && jstr(r) == Some("tool") else {
        continue
      }
      guard jget(m, "content") is Some(c) && jstr(c) is Some(content) else {
        continue
      }
      if content.has_prefix("{") && !@json.valid(content) {
        println("FATAL: tool_result 非合法 JSON: \{content}")
        panic()
      }
    }
  }
}

///|
/// 断言所有请求中的 system 消息内容逐字节一致（system prompt 会话内稳定性）。
/// BUG-0038 回归：013 剧本的"prompt 中途切换"实为 diff-harness 记录污染
/// （req_0009+ 系 ruby 进程跑 014 场景误写入 013 目录），产品侧不存在突变
/// 路径；本断言固化"连续失败重试全程 system prompt 不变"这一真实不变量。
fn assert_system_prompt_stable(requests : Array[String]) -> Unit {
  let mut first : String? = None
  for req in requests {
    let body = @json.parse(req) catch { _ => continue }
    guard jget(body, "messages") is Some(msgs_json) else { continue }
    guard jarr(msgs_json) is Some(msgs) else { continue }
    for m in msgs {
      guard jget(m, "role") is Some(r) && jstr(r) == Some("system") else {
        continue
      }
      guard jget(m, "content") is Some(c) && jstr(c) is Some(content) else {
        continue
      }
      match first {
        None => first = Some(content)
        Some(f0) =>
          if content != f0 {
            println(
              "FATAL: system prompt 会话内发生变化（BUG-0038 回归）",
            )
            panic()
          }
      }
    }
  }
  if first is None {
    println(
      "FATAL: 请求中未找到 system 消息，无法断言 prompt 稳定性",
    )
    panic()
  }
}

///|
/// 断言请求体携带 observability 字段（spec 2026-08-18_23 / BUG-0034 / BUG-0035）。
///
/// - 每个 user 消息必须含 `display_text` 与 `display_files` 键（可为 null；
///   spec 选项 A：user 始终序列化，对齐 Ruby hash-passthrough）。
/// - 每个非首次请求中的 assistant 消息必须含非 null 的 `latency` 键
///   （react 在 LLM 返回后挂上，反映本次调用端到端耗时）。
///
/// 此断言不校验 latency 的具体值（量级由各 LLM 后端的 timing 决定），
/// 只校验"字段被正确写入并出现在出站请求体里"这一链路事实。
fn assert_observability_fields(requests : Array[String]) -> Unit {
  for ri, req in requests {
    let body = @json.parse(req) catch { _ => continue }
    guard jget(body, "messages") is Some(msgs_json) else { continue }
    guard jarr(msgs_json) is Some(msgs) else { continue }
    for m in msgs {
      guard jget(m, "role") is Some(r) && jstr(r) is Some(role) else {
        continue
      }
      if role == "user" {
        // user 消息始终携带 display_text / display_files（可为 null）
        guard jget(m, "display_text") is Some(_) else {
          println(
            "FATAL: req\{ri} user 消息缺 display_text 字段（spec 2026-08-18_23 选项 A）",
          )
          panic()
        }
        guard jget(m, "display_files") is Some(_) else {
          println(
            "FATAL: req\{ri} user 消息缺 display_files 字段（spec 2026-08-18_23 选项 A）",
          )
          panic()
        }
      } else if role == "assistant" && ri > 0 {
        // 非首次请求里的 assistant 消息是历史 LLM 返回，必须已挂 latency
        guard jget(m, "latency") is Some(lat) else {
          println(
            "FATAL: req\{ri} assistant 消息缺 latency 字段（BUG-0034 回归）",
          )
          panic()
        }
        if lat is Json::Null {
          println("FATAL: req\{ri} assistant 消息 latency 为 null")
          panic()
        }
      }
    }
  }
}

///|
async test "001 read_edit_file：读文件→编辑→回复完成" {
  let outcome = run_scenario(
    "001_read_edit_file",
    [("config.yaml", "server:\n  host: 0.0.0.0\n  port: 8080\n")],
    "把 config.yaml 里的端口改成 9090",
  )
  // 黄金断言点：ruby 3 请求、exit=0、config.yaml 端口改为 9090
  // 证据: diff-harness runs/001_read_edit_file/ruby/
  assert_golden(outcome, golden("001_read_edit_file"))
  // BUG-0034 / BUG-0035 回归：出站请求必须带 observability 字段
  assert_observability_fields(outcome.requests)
}

///|
async test "002 stream_cut_retry：断流后重试并恢复" {
  let outcome = run_scenario(
    "002_stream_cut_retry",
    [("README.md", "# demo\n")],
    "读一下 README.md 然后告诉我完成了",
  )
  let g = golden("002_stream_cut_retry")
  // BUG-0032 已修复：stream_cut 断流 → UpstreamTruncatedError → 重试管道
  // （ruby 4 请求；MB 现为 4 请求：断流→429→tool_calls→完成）。
  // 证据: diff-harness reports/BUGS.md BUG-0032；
  //       runs/002_stream_cut_retry/{ruby,moonbit}/requests/（ruby 4 请求 vs MB 修复前 1 请求）
  assert_golden(outcome, g)
  // BUG-0023: ruby 退避固定 5s（req1→req2、req2→req3 各 ~5s），MB 指数退避。
  // 证据: reports/p3/002_stream_cut_retry_diff.md（ruby 间隔 5.0s, 5.0s）
  // 注：此处为量级断言（退避生效且未失控）；固定 5s 的精确验证在
  // llm_caller_wbtest.mbt（retry_delay_ms 单测，无 wall-clock 依赖）。
  if @diff.known_failure("BUG-0023") {
    return
  }
  assert_retry_intervals(outcome.request_times, [5000, 5000], 1500)
}

///|
async test "003 multi_turn_tool_sequence：read→edit→read 验证→完成" {
  let outcome = run_scenario(
    "003_multi_turn_tool_sequence",
    [("app.conf", "[app]\ndebug=false\nverbose=true\n")],
    "把 app.conf 里的 debug 改成 true，改完再读一次确认",
  )
  // 黄金断言点：ruby 4 请求、exit=0、app.conf debug=true
  // 证据: diff-harness runs/003_multi_turn_tool_sequence/ruby/
  assert_golden(outcome, golden("003_multi_turn_tool_sequence"))
  // BUG-0034 / BUG-0035 回归：多轮场景下 observability 字段必须全程携带
  assert_observability_fields(outcome.requests)
}

///|
async test "004 parallel_tool_calls：单响应内两个并行 tool_calls" {
  let outcome = run_scenario(
    "004_parallel_tool_calls",
    [("a.txt", "alpha\n"), ("b.txt", "beta\n")],
    "对比 a.txt 和 b.txt 的内容",
  )
  // 黄金断言点：ruby 2 请求、exit=0、文件无变化
  // 证据: diff-harness runs/004_parallel_tool_calls/ruby/
  assert_golden(outcome, golden("004_parallel_tool_calls"))
}

///|
async test "005 compression_trigger：上下文压缩触发" {
  // BUG-0042 已修复（spec 2026-08-18_09_p5-compression-trigger-semantics.md）：
  // needs_compression 取 max(previous_total_tokens, estimate)；recent 守卫对
  // >2000 字符 tool_result 放行（模拟 ruby truncate_tool_result 副作用）。
  // 超时风险已隔离：当前基线（内生 runner + 120s 超时保护）实测不复现旧
  // diff-harness 的 300s 挂死（旧证据来自已删除 runs/ 目录的修复候选）。
  // 证据: diff-harness reports/BUGS.md BUG-0041/0042/0043；
  //       reports/BUG-0042_ANALYSIS.md；runs/005_compression_trigger/{ruby,moonbit}/
  // fixture 磁盘化（spec 2026-08-18_22 决策 5）：读取 test/e2e/fixtures/big.txt
  // （315000B，与 diff-harness FIXTURES 逐字节一致：15000 行 "x = 1234567890abcdef\n"），
  // 消除内存生成的编码/换行差异面；字节数断言兜底。
  let big_fixture = @fs.read_file_to_string("test/e2e/fixtures/big.txt") catch {
    _ => {
      println(
        "FATAL: 无法读取 test/e2e/fixtures/big.txt（moon test 的 CWD 应为项目根）",
      )
      panic()
    }
  }
  @debug.assert_eq(big_fixture.length(), 315000)
  let outcome = run_scenario(
    "005_compression_trigger",
    [("big.txt", big_fixture)],
    "读一下 big.txt 的全部内容，然后告诉我行数",
    configure=fn(config) {
      // BUG-0041 修复后：MBOPENCLACKY_COMPRESSION_THRESHOLD 经
      // apply_env_overlay 生效（对齐 diff-harness 的 MBOPENCLACKY_* 注入通路；
      // 此前经 CLACKY_COMPRESSION_THRESHOLD 绕过，见 spec 2026-08-18_07）。
      @env.set_env_var("MBOPENCLACKY_COMPRESSION_THRESHOLD", "1")
      config.compression_threshold = config.apply_env_overlay().compression_threshold
    },
    timeout_ms=120_000,
  )
  let g = golden("005_compression_trigger")
  assert_golden(outcome, g)
  // big.txt 315000B 无变化（ruby fs_after size=315000）
  match outcome.file("big.txt") {
    Some(content) => {
      @debug.assert_eq(content.length(), 315000)
      assert_true(content.has_prefix("x = 1234567890abcdef\n"))
    }
    None => {
      println("FATAL: big.txt 缺失")
      panic()
    }
  }
}

///|
async test "008 http_429_retry_after：429 限流重试" {
  let outcome = run_scenario(
    "008_http_429_retry_after",
    [("note.txt", "hello\n")],
    "读一下 note.txt 然后告诉我内容",
  )
  // 黄金断言点：ruby 3 请求（1 次重试）、exit=0。
  // 注：ruby 未消费 Retry-After（固定 5s，见 reports/p3/008_diff.md），
  // MB 同为 5s（指数退避第一次也是 5s），两侧间隔一致，故本剧本无 gated 断言。
  // 证据: diff-harness runs/008_http_429_retry_after/ruby/
  assert_golden(outcome, golden("008_http_429_retry_after"))
}

///|
async test "009 http_500_retry：500 重试两次后恢复" {
  let outcome = run_scenario(
    "009_http_500_retry",
    [("note.txt", "hello\n")],
    "读一下 note.txt 然后告诉我内容",
  )
  // 绿：ruby 4 请求（2 次重试）、exit=0、最终成功 —— MB 当前行为一致。
  // 证据: diff-harness runs/009_http_500_retry/ruby/
  assert_golden(outcome, golden("009_http_500_retry"))
  // BUG-0037 已修复（spec 2026-08-18_08）：retry_delay_ms 固定 5s，
  // 退避间隔 ruby/MB 均为 5s/5s。证据: reports/p3/009_diff.md
  // 注：此处为量级断言（退避生效且未失控）；固定 5s 的精确验证在
  // llm_caller_wbtest.mbt（retry_delay_ms 单测，无 wall-clock 依赖）。
  assert_retry_intervals(outcome.request_times, [5000, 5000], 1500)
}

///|
async test "010 tool_call_args_truncated：空 arguments 恢复" {
  let outcome = run_scenario(
    "010_tool_call_args_truncated",
    [],
    "写文件 out.txt，内容是 hello world",
  )
  let g = golden("010_tool_call_args_truncated")
  // 绿：ruby 3 请求、exit=0、out.txt="hello world"（11B）、最终回复 —— MB 当前一致
  // （MB 走"执行空参数→工具报错→下一轮"路径，与 ruby 的截断重试殊途同归，请求数相同）。
  // 证据: diff-harness runs/010_tool_call_args_truncated/{ruby,moonbit}/
  @debug.assert_eq(outcome.status, "success")
  @debug.assert_eq(outcome.requests.length(), g.request_count)
  @debug.assert_eq(outcome.file("out.txt"), Some("hello world"))
  @debug.assert_eq(outcome.final_text, g.final_text)
  // BUG-0040: MB 工具错误 tool_result 非标准 JSON（{error: ...} 缺引号）。
  // 证据: diff-harness reports/BUGS.md BUG-0040（明确涉及 010 的 write_file 空参数错误）；
  //       runs/010_tool_call_args_truncated/moonbit/requests/req_0002.json
  if @diff.known_failure("BUG-0040") {
    return
  }
  assert_tool_results_valid_json(outcome.requests)
}

///|
async test "011 malformed_sse_chunk：畸形帧容错并正常完成" {
  // 011 从未在 diff-harness 执行过（runs/ 下无 011 目录；python mock server 无畸形注入
  // 能力，见 spec 2026-08-18_22 现状分析）。本剧本经 MB mock 的 malformed 类型重写为
  // "正常流中混入畸形帧 + 收尾"：A 级期望值从两侧解析器源码静态推导——
  //   Ruby: client.rb#drain_sse_frames（无 data: 前缀的帧 data_lines 为空 → 不 yield）
  //         + openai_stream_aggregator.rb#parse_or_nil（非法 JSON 计数后返回 nil 跳过，
  //         不中断流；仅 finish_reason 缺失才 raise UpstreamTruncatedError）。
  //   MB:   lib/client/stream.mbt#parse_single_frame（无 data: 行 → None 丢弃）
  //         + OpenAiStreamAggregator::handle_delta（JSON 解析失败 → 返回 "" 跳过）。
  // 结论（A 级）：畸形帧被跳过、正常 content 帧累积、收尾帧携带 finish_reason=stop →
  // 1 请求、exit=0（success）、最终回复为 content 帧原文。
  let outcome = run_scenario(
    "011_malformed_sse_chunk",
    [],
    "读一下文件，然后把内容告诉我",
  )
  @debug.assert_eq(outcome.status, "success")
  @debug.assert_eq(outcome.requests.length(), 1)
  @debug.assert_eq(outcome.final_text, "文件内容是 hello。")
}

///|
async test "012 finish_stop_with_tool_calls：stop+tool_calls 正常执行（suspicious 仅日志）" {
  let outcome = run_scenario(
    "012_finish_stop_with_tool_calls",
    [("note.txt", "hello\n")],
    "读一下 note.txt 然后告诉我内容",
  )
  // 剧本刺激已修正：tool_calls 步骤补 finish_reason="stop"（此前 mock 硬编码
  // "tool_calls"，stop+tool_calls 并存从未真实下发）。
  // A 级期望值（2 请求、exit=0）从 ruby 源码静态推导：
  //   - llm_caller.rb#detect_upstream_truncation! 仅对截断 arguments
  //     （空/"{}"/非法 JSON）抛 UpstreamTruncatedError；本剧本 arguments 合法 → 不抛。
  //   - llm_caller.rb L404-444 的 suspicious（finish_reason=stop + tool_calls）只是
  //     Clacky::Logger.warn 诊断日志，不触发重试。
  //   - 因此 stop+合法 tool_calls → agent 正常执行 read_file → 2 请求、exit=0。
  // MB 侧 check_stream_truncation（lib/agent/llm_caller.mbt）同源：finish_reason 存在
  // 且 arguments 合法 → 不抛，react 循环执行工具。与 ruby 行为一致。
  // 黄金断言点：ruby 2 请求、exit=0（runs/012_finish_stop_with_tool_calls/ruby/，
  // 修正刺激前的 2 请求基线在修正后经源码推导保持不变）。
  // 证据: openclacky/lib/clacky/agent/llm_caller.rb L404-444、L695-745
  assert_golden(outcome, golden("012_finish_stop_with_tool_calls"))
}

///|
async test "013 consecutive_failures_circuit_breaker：连续失败熔断" {
  // BUG-0039 已修复（spec 2026-08-18_08）：
  // 任务包 1 复现定位结论——"MB 15 请求"系 diff-harness 运行记录污染：
  // runs/013 moonbit 的 req_0009~0015 是后续 014 场景进程的请求误写入
  // （system prompt 与 session context 完全不同、user prompt 为 014 文案）。
  // MB 真实行为：指数退避 5+10+20+40+60+60+60=255s 后第 8 个请求 sleep 60s
  // 时被 harness 300s 超时杀掉（exit=-1）——无额外重试路径。
  // 退避改固定 5s 后：10 次重试共 11 请求 ≈50s 内完成、raise 干净失败 exit=1，
  // 与 ruby 一致。
  // 证据: diff-harness runs/013_consecutive_failures_circuit_breaker/
  //       {ruby,moonbit}/requests/（污染分析见本 spec 现状分析）
  let outcome = run_scenario(
    "013_consecutive_failures_circuit_breaker",
    [("note.txt", "hello\n")],
    "读一下 note.txt 然后告诉我内容",
  )
  // ruby 基线：11 请求、exit=1（干净失败 ↔ outcome.status == "error"）
  assert_golden(outcome, golden("013_consecutive_failures_circuit_breaker"))
  // BUG-0038 已关闭（spec 2026-08-18_19）：非产品缺陷——"req9 起 system
  // prompt 突变"系 diff-harness 记录污染（req_0009+ 为 ruby 进程跑 014 场景
  // 误写入 013 目录，session context 工作目录为 /tmp/diffharness_ruby_*、
  // user 文案为 014 的"先读一下 nonexistent.txt..."；013 真实请求
  // req_0001~0008 的 system prompt 逐字节一致）。此处固化回归断言：
  // 连续失败重试全程 system prompt 逐字节一致。
  // 证据: diff-harness runs/013_consecutive_failures_circuit_breaker/moonbit/requests/
  assert_system_prompt_stable(outcome.requests)
}

///|
async test "014 tool_execution_failure_recovery：工具失败后恢复" {
  let outcome = run_scenario(
    "014_tool_execution_failure_recovery",
    [("note.txt", "hello\n")],
    "先读一下 nonexistent.txt，再读一下 note.txt",
  )
  // 绿：ruby 3 请求、exit=0、恢复后读取成功 —— MB 当前一致。
  // 证据: diff-harness runs/014_tool_execution_failure_recovery/{ruby,moonbit}/
  assert_golden(outcome, golden("014_tool_execution_failure_recovery"))
  // BUG-0040: MB 工具错误 tool_result 非标准 JSON（{error: ...} 缺引号）；
  // ruby 为标准 JSON {"path":...,"content":null,"error":"File not found: ..."}。
  // 证据: diff-harness reports/BUGS.md BUG-0040；
  //       runs/014_tool_execution_failure_recovery/moonbit/requests/req_0002.json
  if @diff.known_failure("BUG-0040") {
    return
  }
  assert_tool_results_valid_json(outcome.requests)
}
