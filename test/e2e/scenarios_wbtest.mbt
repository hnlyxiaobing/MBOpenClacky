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
/// 断言退避间隔：request_times 相邻差值应约等于期望值（ms，含容差）。
fn assert_retry_intervals(
  times : Array[Int64],
  expected_ms : Array[Int],
  tolerance_ms : Int,
) -> Unit {
  if times.length() < expected_ms.length() + 1 {
    println(
      "FATAL: 请求数不足，无法断言退避间隔: \{times.length()}",
    )
    panic()
  }
  for i in 0..<expected_ms.length() {
    let delta = (times[i + 1] - times[i]).to_int()
    let lo = expected_ms[i] - tolerance_ms
    let hi = expected_ms[i] + tolerance_ms
    if delta < lo || delta > hi {
      println(
        "FATAL: 退避间隔越界: req\{i + 1}→req\{i + 2} = \{delta}ms，期望 [\{lo}, \{hi}]ms",
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
/// 005 的 fixture：15000 行重复内容（315000B，对齐 diff-harness FIXTURES）。
fn big_txt_content() -> String {
  Array::make(15000, "x = 1234567890abcdef\n").join("")
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
  // BUG-0042（兼引 BUG-0041 env overlay 缺口、BUG-0043 缺 10% 最小收益检查）:
  // MB needs_compression 语义/recent 守卫未对齐 ruby；且 BUG-0042 修复记录显示
  // 修复候选跑 005 场景超时（300s 未退出）。整剧本隔离，修复后移除编号即激活。
  // runner 自带 120s 超时保护（with_timeout_opt），闸门打开后也不会挂死套件。
  // 证据: diff-harness reports/BUGS.md BUG-0041/0042/0043；
  //       reports/BUG-0042_ANALYSIS.md；runs/005_compression_trigger/{ruby,moonbit}/
  if @diff.known_failure("BUG-0042") {
    return
  }
  let outcome = run_scenario(
    "005_compression_trigger",
    [("big.txt", big_txt_content())],
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
  // BUG-0037: ruby 退避固定 5s/5s，MB 指数退避 5s/10s。
  // 证据: reports/p3/009_diff.md（ruby 5.0s,5.0s vs moonbit 5.0s,10.0s）
  if @diff.known_failure("BUG-0037") {
    return
  }
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
async test "011 malformed_sse_chunk：等待 ruby 基线（暂不断言）" {
  // 011 从未在 diff-harness 执行过（runs/ 下无 011 目录，python mock server 尚不支持
  // 注入畸形 chunk）。按纪律禁止编造期望值：需先在 diff-harness 扩展 python mock server
  // 并跑 ruby 侧取得基线后，再回填本测试的断言。
  // 证据: diff-harness AGENTS.md 第 4 节"诚实标注不确定性"；scenarios/011_malformed_sse_chunk.json
  return
}

///|
async test "012 finish_stop_with_tool_calls：tool_calls 正常执行" {
  let outcome = run_scenario(
    "012_finish_stop_with_tool_calls",
    [("note.txt", "hello\n")],
    "读一下 note.txt 然后告诉我内容",
  )
  // 黄金断言点：ruby 2 请求、exit=0
  // 证据: diff-harness runs/012_finish_stop_with_tool_calls/ruby/
  assert_golden(outcome, golden("012_finish_stop_with_tool_calls"))
}

///|
async test "013 consecutive_failures_circuit_breaker：连续失败熔断" {
  // BUG-0039（兼引 BUG-0038 system prompt 中途切换）: ruby 10 次重试共 11 请求、
  // 干净失败 exit=1；MB 重试 13 次共 15 请求、exit=-1 异常终止。
  // 闸门后直接 return：当前行为下跑全量要 15 请求 × 指数退避（5→10→20→40→60s…），
  // 会挂住测试套件数分钟。
  // 证据: diff-harness reports/BUGS.md BUG-0038/0039；
  //       runs/013_consecutive_failures_circuit_breaker/{ruby,moonbit}/
  if @diff.known_failure("BUG-0039") {
    return
  }
  let outcome = run_scenario(
    "013_consecutive_failures_circuit_breaker",
    [("note.txt", "hello\n")],
    "读一下 note.txt 然后告诉我内容",
  )
  // ruby 基线：11 请求、exit=1（干净失败 ↔ outcome.status == "error"）
  assert_golden(outcome, golden("013_consecutive_failures_circuit_breaker"))
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
