/// # diff-harness 回归测试：error_retry 模块（retry-001 ~ retry-020）
///
/// 迁移自 diff-harness（D:/MoonBit/diff-harness）`cases/error_retry/test_cases.json`。
/// 期望值可信度分级：
/// - A 级（P3 链路实测佐证）：固定 5s 退避（剧本 002/008/009 ruby 实测）、
///   max_retries=10（剧本 013 ruby 共 11 请求）。按 Ruby 冻结。
/// - B 级（仅 Ruby 源码静态分析，未经实测）：其余 retry-* 用例，注释逐条标注
///   「期望值源自 Ruby 源码静态分析（diff-harness cases/error_retry），未经实测」。
///
/// 入口可达性说明（读代码核实）：
/// - `retry_delay_ms` 是 lib/agent 的包内私有函数，test/diff 跨包不可达；
///   退避序列（retry-005~009）只能断言 pub 常量（retry_base_delay_ms /
///   retry_max_delay_ms），指数形态已由 lib/agent/llm_caller_wbtest.mbt 冻结。
/// - HTTP 状态码 → RetryableError/BadRequestError 的分类逻辑内联在
///   llm_caller.mbt 的 call_llm_async / call_llm_stream_async（429/5xx →
///   RetryableError，其余 → BadRequestError），没有纯函数入口，单测不可达；
///   本文件只能覆盖其上游 map_http_error 的消息映射。
/// - 平台 HTTP 的真实重试/failover 发生在网上，单测不可达；只能断言
///   PlatformHttpConfig 的公开结构（域名数、max_retries 默认值）。
///
/// BUG 台账：diff-harness/reports/BUGS.md；证据：cases/error_retry/test_cases.json。

///|
/// 构造一个走 mock 路径的测试 Agent（不触网）。
fn retry_make_agent() -> @agent.Agent {
  let client = @client.Client::new(
    "test-key",
    "https://api.example.com",
    "test-model",
    @config.OpenAICompletions,
  )
  @agent.Agent::new(
    "diff-session",
    "diff-agent",
    "/tmp/diff",
    client,
    @config.AgentConfig::default(),
  )
}

///|
/// 构造 mock LLM 响应。
fn mock_resp(
  content : String,
  reasoning_content? : String? = None,
) -> @client.LlmResponse {
  {
    content: Some(content),
    reasoning_content,
    tool_calls: None,
    finish_reason: Some("stop"),
    usage: None,
    latency: None,
  }
}

// ── retry_trigger ────────────────────────────────────────────────────────────

///|
/// retry-001：429 错误应触发重试。
/// A 级期望值（P3 剧本 008 ruby 实测 429 重试）。
/// green：map_http_error 把 429 映射为限流错误消息。
/// 注：429 → RetryableError 的分类内联于 llm_caller.mbt（单测不可达），
/// MB 与 Ruby 均会重试 429，链路层由 P3 剧本 008/009 覆盖。
test "retry_001_http_429_retryable" {
  match @client.map_http_error(429, "{\"error\":{\"message\":\"slow down\"}}") {
    Some(msg) => assert_true(msg.contains("Rate limit"))
    None => abort("429 should map to an error")
  }
}

///|
/// retry-002：500 错误应触发重试。
/// A 级期望值（P3 剧本 009 ruby 实测 5xx 重试）。
/// green：map_http_error 把 5xx 映射为服务不可用消息。
/// 注：5xx → RetryableError 的分类内联于 llm_caller.mbt（单测不可达）。
test "retry_002_http_500_retryable" {
  match @client.map_http_error(500, "internal error") {
    Some(msg) => assert_true(msg.contains("temporarily unavailable"))
    None => abort("500 should map to an error")
  }
}

///|
/// retry-003：400 错误不应触发重试。
/// 期望值源自 Ruby 源码静态分析（diff-harness cases/error_retry），未经实测。
/// green：map_http_error 把普通 400 映射为客户端请求错误消息。
/// 注：400 → BadRequestError（不重试）的分类内联于 llm_caller.mbt（单测不可达）。
test "retry_003_http_400_not_retryable" {
  match
    @client.map_http_error(400, "{\"error\":{\"message\":\"bad request\"}}") {
    Some(msg) => assert_true(msg.contains("Client request error"))
    None => abort("400 should map to an error")
  }
}

///|
/// retry-004：402 错误处理差异。
/// 期望值源自 Ruby 源码静态分析（diff-harness cases/error_retry），未经实测：
/// Ruby 将 402 视为 RetryableError（insufficient_credit，可重试）。
/// MB 实际行为：map_http_error 映射为账单类消息，内联分类抛 BadRequestError
/// （不重试）——BUG-0024 known-failure。
/// 注：重试分类无纯函数入口，修复 BUG-0024 后需在本包可观测的入口上补断言。
test "retry_004_http_402_classification" {
  // green：消息映射（MB 当前行为）
  match @client.map_http_error(402, "{\"error\":{\"message\":\"pay up\"}}") {
    Some(msg) => assert_true(msg.contains("Billing"))
    None => abort("402 should map to an error")
  }
  // BUG-0024：Ruby 冻结值——402 为 RetryableError（可重试）；
  // MB 实际为 BadRequestError（不可重试），分类内联于 llm_caller.mbt 不可达。
  // 证据：cases/error_retry/test_cases.json retry-004
  if known_failure("BUG-0024") {
    return
  }
  // 修复后在此断言 402 的可重试分类（需要 lib 侧提供可观测入口）。
}

///|
/// retry-013：空响应（无 content 和 tool_calls）应触发重试。
/// 期望值源自 Ruby 源码静态分析（diff-harness cases/error_retry），未经实测：
/// Ruby 检测空响应并抛 RetryableError 重试。
/// 代码核实结论：BUG-0025 所记"未实现"已过时——MB 已在 react_loop_async
/// 实现空响应检测（空 content 时注入 user 消息重新提问，最多 3 次后报错）；
/// 机制是 react 层重新提问而非 LLM 调用层 RetryableError，但"空响应触发
/// 重试"的语义已覆盖。本用例按已实现写 green 断言。
async test "retry_013_empty_response_triggers_reask" {
  let agent = retry_make_agent()
  agent.mock_responses.push(mock_resp(""))
  agent.mock_responses.push(mock_resp("Here is the answer"))
  let result = agent.run("question") catch { _ => abort("unexpected error") }
  assert_true(result.status == @agent.Success)
  assert_eq(result.iterations, 2)
}

///|
/// retry-014：只有 thinking 没有 content 的静默响应应触发重试。
/// 期望值源自 Ruby 源码静态分析（diff-harness cases/error_retry），未经实测：
/// Ruby 检测 thinking-mode 静默响应并抛 RetryableError 重试。
/// 代码核实结论：BUG-0026 所记"未实现"已过时——MB 的 react_loop_async
/// 只看 content 是否为空，thinking-only 响应按空响应路径重试（已有
/// lib/agent/agent_wbtest.mbt "thinking_silent_response_retries" 佐证）。
/// 本用例按已实现写 green 断言。
async test "retry_014_thinking_silent_response_triggers_reask" {
  let agent = retry_make_agent()
  agent.mock_responses.push(
    mock_resp("", reasoning_content=Some("thinking hard...")),
  )
  agent.mock_responses.push(mock_resp("Done thinking"))
  let result = agent.run("question") catch { _ => abort("unexpected error") }
  assert_true(result.status == @agent.Success)
  assert_eq(result.iterations, 2)
}

///|
/// retry-015：400 + body 含 ThrottlingException 应触发重试。
/// 期望值源自 Ruby 源码静态分析（diff-harness cases/error_retry），未经实测：
/// Ruby 视为 RetryableError。
/// green：map_http_error 对该 body 给出限流类消息（MB 确实检查
/// ThrottlingException）。
/// 注意（与用例 verdict=match 不符的发现）：MB 的重试分类只看状态码
/// （llm_caller.mbt: 429/5xx → RetryableError），400 一律 BadRequestError，
/// 即 MB 实际不会重试该错误；分类逻辑无纯函数入口，无法在单测断言，
/// 此差异台账未立项（needs-investigation）。
test "retry_015_http_400_throttling_exception_message" {
  let body = "{\"error\":{\"message\":\"ThrottlingException: rate exceeded\"}}"
  match @client.map_http_error(400, body) {
    Some(msg) => assert_true(msg.contains("Rate limit or service issue"))
    None => abort("400 should map to an error")
  }
}

// ── backoff_strategy ─────────────────────────────────────────────────────────

///|
/// retry-005：第 1 次重试的延迟。
/// A 级期望值（P3 剧本 002 ruby 实测固定 5s）：delay=5000。
/// green：MB 第 1 次延迟等于 base（5000），与 Ruby 一致。
/// 注：retry_delay_ms 为 lib/agent 私有函数不可达，以 pub 常量
/// retry_base_delay_ms 承接（retry_delay_ms(1) == retry_base_delay_ms）。
test "retry_005_first_retry_delay" {
  assert_eq(@agent.retry_base_delay_ms, 5000)
}

///|
/// retry-006：第 2 次重试的延迟。
/// A 级期望值（P3 剧本 002 ruby 实测固定 5s）：Ruby delay=5000。
/// 已修复（BUG-0023，spec 2026-08-18_08）：retry_delay_ms 固定返回 5000，
/// 退避序列 [5000, 5000, ...] 由 lib/agent/llm_caller_wbtest.mbt
/// "retry_delay_ms fixed 5s" 冻结；此处 pub 常量承接。
test "retry_006_second_retry_delay" {
  assert_eq(@agent.retry_base_delay_ms, 5000)
}

///|
/// retry-007：第 3 次重试的延迟。已修复（BUG-0023）：固定 5000。
/// A 级期望值（P3 剧本 002 ruby 实测固定 5s）。
test "retry_007_third_retry_delay" {
  assert_eq(@agent.retry_base_delay_ms, 5000)
}

///|
/// retry-008：第 4 次重试的延迟。已修复（BUG-0023）：固定 5000。
/// A 级期望值（P3 剧本 002 ruby 实测固定 5s）。
test "retry_008_fourth_retry_delay" {
  assert_eq(@agent.retry_base_delay_ms, 5000)
}

///|
/// retry-009：第 5 次重试的延迟。已修复（BUG-0023）：固定 5000（Ruby 无上限概念）。
/// A 级期望值（P3 剧本 002 ruby 实测固定 5s）。
test "retry_009_fifth_retry_delay_capped" {
  assert_eq(@agent.retry_base_delay_ms, 5000)
  // retry_max_delay_ms 保留为兼容常量（Ruby 无此概念）；固定 5s 后不再触及上限。
  assert_eq(@agent.retry_max_delay_ms, 60000)
}

// ── retry_limits / url_fallback ──────────────────────────────────────────────

///|
/// retry-010：最大重试次数。
/// A 级期望值（P3 剧本 013 ruby 实测共 11 请求 = 1 + 10 次重试）：max_retries=10。
/// green：pub 常量断言。
test "retry_010_max_retries" {
  assert_eq(@agent.max_retries, 10)
}

///|
/// retry-011：连续 3 次失败后触发 fallback。
/// 期望值源自 Ruby 源码静态分析（diff-harness cases/error_retry），未经实测。
/// green：pub 常量 retries_before_fallback=3。状态机迁移由
/// lib/agent/llm_caller_wbtest.mbt 覆盖（record_retryable_failure 私有不可达）。
test "retry_011_fallback_threshold" {
  assert_eq(@agent.retries_before_fallback, 3)
}

///|
/// retry-012：fallback 激活 30 分钟后进入探测状态。
/// 期望值源自 Ruby 源码静态分析（diff-harness cases/error_retry），未经实测。
/// green：pub 常量 fallback_cooldown_seconds=1800。冷却迁移由
/// lib/agent/llm_caller_wbtest.mbt "check_fallback_cooldown_*" 覆盖。
test "retry_012_fallback_cooldown" {
  assert_eq(@agent.fallback_cooldown_seconds, 1800)
}

// ── error_handling ───────────────────────────────────────────────────────────

///|
/// retry-016：HTML 响应处理差异。
/// 期望值源自 Ruby 源码静态分析（diff-harness cases/error_retry），未经实测：
/// Ruby 不特殊检测 HTML（UnknownError）；MB 检测 HTML 并抛 AgentError
/// （不可重试）——BUG-0027 wontfix（MB 更严格，可保留），冻结 MB 当前行为。
test "retry_016_html_response_detection" {
  // wontfix（BUG-0027）：冻结 MB 的 HTML 检测行为。
  assert_true(@client.is_html_response("<html><body>Error</body></html>"))
  assert_true(@client.is_html_response("<!DOCTYPE html><html></html>"))
  assert_true(!@client.is_html_response("{\"error\":\"x\"}"))
  assert_eq(
    @client.extract_error_message("<html><body>Error</body></html>"),
    "Invalid API endpoint or server error (received HTML instead of JSON)",
  )
}

// ── context_overflow ─────────────────────────────────────────────────────────

///|
/// retry-017：context overflow 恢复 - 标准模式 pop 1 条消息。
/// 期望值源自 Ruby 源码静态分析（diff-harness cases/error_retry），未经实测。
/// green：标准模式 pop 1 条（两侧一致）。
/// BUG-0028 known-failure：Ruby pop 后调用 compress_messages_if_needed，
/// MB 仅 compression_level+1 不调压缩；压缩调用在 handle_context_overflow
/// 内不可由本包观测，修复后需在 lib/agent 侧补断言完成闭环。
test "retry_017_overflow_standard_pop_one" {
  let agent = retry_make_agent()
  agent.history.push(@message.Message::system("sys"))
  for _ in 0..<5 {
    agent.history.push(@message.Message::user("u"))
  }
  let removed = agent.handle_context_overflow(@agent.Standard)
  assert_true(removed)
  assert_eq(agent.history.length(), 5)
  // BUG-0028：Ruby 冻结值——pop 后调用压缩（compress_after_pop=true）。
  // 证据：cases/error_retry/test_cases.json retry-017
  if known_failure("BUG-0028") {
    return
  }
  // 压缩调用不可由本包观测（见文件头说明），修复后在 lib/agent 侧补断言。
}

///|
/// retry-018：context overflow 恢复 - 激进模式 pop 约一半消息。
/// 期望值源自 Ruby 源码静态分析（diff-harness cases/error_retry），未经实测。
/// green（100 条时两侧一致）：pop removable/2 = 50。
/// BUG-0029 known-failure：Ruby 激进模式 pop 上限 64 条；MB 无上限，
/// 200 条可删时 MB pop 100（剩 101），Ruby 冻结值 pop 64（剩 137）。
test "retry_018_overflow_aggressive_pop_half" {
  let agent = retry_make_agent()
  agent.history.push(@message.Message::system("sys"))
  for _ in 0..<100 {
    agent.history.push(@message.Message::user("u"))
  }
  let removed = agent.handle_context_overflow(@agent.Aggressive)
  assert_true(removed)
  assert_eq(agent.history.length(), 51)
  // BUG-0029：Ruby 冻结值——激进模式 pop 上限 64（201 条历史 pop 64 剩 137）。
  // 证据：cases/error_retry/test_cases.json retry-018
  if known_failure("BUG-0029") {
    return
  }
  let agent2 = retry_make_agent()
  agent2.history.push(@message.Message::system("sys"))
  for _ in 0..<200 {
    agent2.history.push(@message.Message::user("u"))
  }
  agent2.handle_context_overflow(@agent.Aggressive) |> ignore
  assert_eq(agent2.history.length(), 137)
}

// ── platform_http ────────────────────────────────────────────────────────────

///|
/// retry-019：平台 HTTP 同域重试次数。
/// 期望值源自 Ruby 源码静态分析（diff-harness cases/error_retry），未经实测：
/// Ruby 无同域重试（1 次尝试）；MB max_retries=2（共 3 次尝试）——
/// BUG-0030 wontfix（MB 改进，可保留），冻结 MB 当前行为。
/// 注：真实同域重试发生在网上（单测不可达），此处冻结公开配置结构。
test "retry_019_platform_same_host_retries" {
  let config = @client.PlatformHttpConfig::new(primary_host="p.example.com")
  // wontfix（BUG-0030）：冻结 MB 默认值 max_retries=2（即同域共 3 次尝试）。
  assert_eq(config.max_retries, 2)
}

///|
/// retry-020：平台 HTTP 域名 failover 数量。
/// 期望值源自 Ruby 源码静态分析（diff-harness cases/error_retry），未经实测：
/// Ruby 有 3 个域名（primary + secondary + fallback）；
/// MB 有 2 个（primary + fallback）——BUG-0031 known-failure。
/// 注：真实 failover 发生在网上（单测不可达），此处对公开配置结构计数。
test "retry_020_platform_failover_domains" {
  let config = @client.PlatformHttpConfig::new(
    primary_host="p.example.com",
    fallback_host="f.example.com",
  )
  let mb_domains = [config.primary_host, config.fallback_host]
    .iter()
    .filter(fn(h) { h.length() > 0 })
    .count()
  // green：冻结 MB 当前行为（2 个域名）
  assert_eq(mb_domains, 2)
  // BUG-0031：Ruby 冻结值——3 个域名（primary + secondary + fallback）。
  // 证据：cases/error_retry/test_cases.json retry-020
  if known_failure("BUG-0031") {
    return
  }
  assert_eq(mb_domains, 3)
}
