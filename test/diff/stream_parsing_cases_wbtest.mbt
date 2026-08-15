/// # diff-harness 回归测试：stream_parsing 模块（stream-001 ~ stream-020）
///
/// 用例来源：diff-harness/cases/stream_parsing/test_cases.json；
/// 期望值冻结自 Ruby 实测 diff-harness/cases/stream_parsing/ruby_results.json。
/// 投喂入口：@client.OpenAiStreamAggregator::handle（逐条 SSE data 行）+
/// to_response 聚合结果。统计字段（frames_seen/bytes_seen/
/// approximate_output_tokens/parse_failures/saw_done）在 MB 侧 aggregator
/// 无对应 API，属 BUG-0006，统一放 *_stats_known_failure 测试隔离。

///|
/// 投喂 SSE data 行序列并返回聚合结果。
fn aggregate(chunks : Array[String]) -> @client.LlmResponse {
  let agg = @client.OpenAiStreamAggregator::new()
  for chunk in chunks {
    agg.handle(chunk)
  }
  agg.to_response()
}

///|
/// 断言单个 tool call 的 id/type/name/arguments。
fn assert_tool_call(
  tc : @message.ToolCall,
  id~ : String,
  name~ : String,
  arguments~ : String,
) -> Unit raise {
  assert_eq(tc.id, id)
  assert_eq(tc.type_, "function")
  assert_eq(tc.function.name, name)
  assert_eq(tc.function.arguments, arguments)
}

// ── stream-001 基本 content 拼接 ─────────────────────────────────────────────

///|
test "stream_001_basic_content" {
  let resp = aggregate([
    "{\"id\":\"chatcmpl-1\",\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\"},\"finish_reason\":null}]}",
    "{\"id\":\"chatcmpl-1\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"Hello\"},\"finish_reason\":null}]}",
    "{\"id\":\"chatcmpl-1\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\" world\"},\"finish_reason\":null}]}",
    "{\"id\":\"chatcmpl-1\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"!\"},\"finish_reason\":null}]}",
    "{\"id\":\"chatcmpl-1\",\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"stop\"}]}",
    "[DONE]",
  ])
  // 冻结期望（ruby_results.json stream-001）：content="Hello world!", finish_reason="stop"
  assert_eq(resp.content, Some("Hello world!"))
  assert_eq(resp.finish_reason, Some("stop"))
  assert_true(resp.tool_calls is None)
  assert_true(resp.reasoning_content is None)
}

// ── stream-002 tool_calls 增量组装 ───────────────────────────────────────────

///|
test "stream_002_tool_calls_incremental" {
  let resp = aggregate([
    "{\"id\":\"chatcmpl-1\",\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\"},\"finish_reason\":null}]}",
    "{\"id\":\"chatcmpl-1\",\"choices\":[{\"index\":0,\"delta\":{\"tool_calls\":[{\"index\":0,\"id\":\"call_1\",\"type\":\"function\",\"function\":{\"name\":\"read_file\",\"arguments\":\"\"}}]},\"finish_reason\":null}]}",
    "{\"id\":\"chatcmpl-1\",\"choices\":[{\"index\":0,\"delta\":{\"tool_calls\":[{\"index\":0,\"function\":{\"arguments\":\"{\\\"pa\"}}]},\"finish_reason\":null}]}",
    "{\"id\":\"chatcmpl-1\",\"choices\":[{\"index\":0,\"delta\":{\"tool_calls\":[{\"index\":0,\"function\":{\"arguments\":\"th\\\":\\\"test.txt\\\"}\"}}]},\"finish_reason\":null}]}",
    "{\"id\":\"chatcmpl-1\",\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"tool_calls\"}]}",
    "[DONE]",
  ])
  // 冻结期望（ruby_results.json stream-002）
  assert_true(resp.content is None)
  assert_eq(resp.finish_reason, Some("tool_calls"))
  guard resp.tool_calls is Some(calls) && calls.length() == 1 else {
    fail("expected exactly 1 tool call")
  }
  assert_tool_call(
    calls[0],
    id="call_1",
    name="read_file",
    arguments="{\"path\":\"test.txt\"}",
  )
}

// ── stream-003 reasoning_content 拼接 ────────────────────────────────────────

///|
test "stream_003_reasoning_content" {
  let resp = aggregate([
    "{\"id\":\"chatcmpl-1\",\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\"},\"finish_reason\":null}]}",
    "{\"id\":\"chatcmpl-1\",\"choices\":[{\"index\":0,\"delta\":{\"reasoning_content\":\"Let me\"},\"finish_reason\":null}]}",
    "{\"id\":\"chatcmpl-1\",\"choices\":[{\"index\":0,\"delta\":{\"reasoning_content\":\" think\"},\"finish_reason\":null}]}",
    "{\"id\":\"chatcmpl-1\",\"choices\":[{\"index\":0,\"delta\":{\"reasoning_content\":\"...\"},\"finish_reason\":null}]}",
    "{\"id\":\"chatcmpl-1\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"Here is my answer\"},\"finish_reason\":null}]}",
    "{\"id\":\"chatcmpl-1\",\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"stop\"}]}",
    "[DONE]",
  ])
  // 冻结期望（ruby_results.json stream-003）
  assert_eq(resp.content, Some("Here is my answer"))
  assert_eq(resp.reasoning_content, Some("Let me think..."))
  assert_eq(resp.finish_reason, Some("stop"))
}

// ── stream-004 usage 记录 ────────────────────────────────────────────────────

///|
test "stream_004_usage" {
  let resp = aggregate([
    "{\"id\":\"chatcmpl-1\",\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\"},\"finish_reason\":null}]}",
    "{\"id\":\"chatcmpl-1\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"Hi\"},\"finish_reason\":null}]}",
    "{\"id\":\"chatcmpl-1\",\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"stop\"}]}",
    "{\"id\":\"chatcmpl-1\",\"choices\":[],\"usage\":{\"prompt_tokens\":10,\"completion_tokens\":5}}",
  ])
  // 冻结期望（ruby_results.json stream-004）：prompt_tokens=10, completion_tokens=5
  assert_eq(resp.content, Some("Hi"))
  assert_eq(resp.finish_reason, Some("stop"))
  guard resp.usage is Some(usage) else { fail("expected usage") }
  assert_eq(usage.input_tokens, 10)
  assert_eq(usage.output_tokens, 5)
}

// ── stream-005 畸形 JSON 容错 ────────────────────────────────────────────────

///|
test "stream_005_malformed_json_core" {
  let resp = aggregate([
    "{\"id\":\"chatcmpl-1\",\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\"},\"finish_reason\":null}]}",
    "this is not json", "{\"id\":\"chatcmpl-1\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"Hello\"},\"finish_reason\":null}]}",
    "{\"id\":\"chatcmpl-1\",\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"stop\"}]}",
    "[DONE]",
  ])
  // 冻结期望（ruby_results.json stream-005）：畸形行被跳过，核心字段不受影响
  assert_eq(resp.content, Some("Hello"))
  assert_eq(resp.finish_reason, Some("stop"))
}

///|
test "stream_005_stats_known_failure" {
  // BUG-0006：OpenAiStreamAggregator 缺少统计面。
  // 证据：diff-harness/cases/stream_parsing/test_cases.json stream-005，
  // ruby_results.json 实测 parse_failures=1, frames_seen=4, bytes_seen=284,
  // saw_done=true, approximate_output_tokens=2。
  // 注：BUG-0006 台账只列了 frames_seen/bytes_seen/approximate_output_tokens，
  // parse_failures/saw_done 同属缺失统计面，一并挂在此编号下。
  if known_failure("BUG-0006") {
    return
  }
  // BUG-0006 修复后：在此补写对 aggregator 统计字段的真实断言（冻结值见上），
  // 并将本测试改名去掉 _known_failure 后缀。
  fail(
    "BUG-0006 已修复：请补写统计断言（parse_failures=1, frames_seen=4, bytes_seen=284, saw_done=true, approximate_output_tokens=2）",
  )
}

// ── stream-006 空 chunk 列表 ─────────────────────────────────────────────────

///|
test "stream_006_empty_chunks" {
  let resp = aggregate([])
  // 冻结期望（ruby_results.json stream-006）
  assert_true(resp.content is None)
  assert_true(resp.finish_reason is None)
  assert_true(resp.tool_calls is None)
  assert_true(resp.reasoning_content is None)
  assert_true(resp.usage is None)
}

// ── stream-007 只有 [DONE] ───────────────────────────────────────────────────

///|
test "stream_007_only_done_core" {
  let resp = aggregate(["[DONE]"])
  // 冻结期望（ruby_results.json stream-007）
  assert_true(resp.content is None)
  assert_true(resp.finish_reason is None)
  assert_true(resp.tool_calls is None)
}

///|
test "stream_007_stats_known_failure" {
  // BUG-0006：证据 test_cases.json stream-007，
  // ruby_results.json 实测 saw_done=true, frames_seen=0, bytes_seen=6。
  if known_failure("BUG-0006") {
    return
  }
  fail(
    "BUG-0006 已修复：请补写统计断言（saw_done=true, frames_seen=0, bytes_seen=6）",
  )
}

// ── stream-008 多个 tool_calls 并行 ──────────────────────────────────────────

///|
test "stream_008_parallel_tool_calls" {
  let resp = aggregate([
    "{\"id\":\"chatcmpl-1\",\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\"},\"finish_reason\":null}]}",
    "{\"id\":\"chatcmpl-1\",\"choices\":[{\"index\":0,\"delta\":{\"tool_calls\":[{\"index\":0,\"id\":\"call_1\",\"type\":\"function\",\"function\":{\"name\":\"read_file\",\"arguments\":\"{\\\"path\\\":\\\"a.txt\\\"}\"}}]},\"finish_reason\":null}]}",
    "{\"id\":\"chatcmpl-1\",\"choices\":[{\"index\":0,\"delta\":{\"tool_calls\":[{\"index\":1,\"id\":\"call_2\",\"type\":\"function\",\"function\":{\"name\":\"write_file\",\"arguments\":\"{\\\"path\\\":\\\"b.txt\\\"}\"}}]},\"finish_reason\":null}]}",
    "{\"id\":\"chatcmpl-1\",\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"tool_calls\"}]}",
    "[DONE]",
  ])
  // 冻结期望（ruby_results.json stream-008）
  assert_true(resp.content is None)
  assert_eq(resp.finish_reason, Some("tool_calls"))
  guard resp.tool_calls is Some(calls) && calls.length() == 2 else {
    fail("expected exactly 2 tool calls")
  }
  assert_tool_call(
    calls[0],
    id="call_1",
    name="read_file",
    arguments="{\"path\":\"a.txt\"}",
  )
  assert_tool_call(
    calls[1],
    id="call_2",
    name="write_file",
    arguments="{\"path\":\"b.txt\"}",
  )
}

// ── stream-009 tool_call JSON 跨 chunk 拆分 ──────────────────────────────────

///|
test "stream_009_tool_call_args_split" {
  let resp = aggregate([
    "{\"id\":\"chatcmpl-1\",\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\"},\"finish_reason\":null}]}",
    "{\"id\":\"chatcmpl-1\",\"choices\":[{\"index\":0,\"delta\":{\"tool_calls\":[{\"index\":0,\"id\":\"call_1\",\"type\":\"function\",\"function\":{\"name\":\"read_file\",\"arguments\":\"\"}}]},\"finish_reason\":null}]}",
    "{\"id\":\"chatcmpl-1\",\"choices\":[{\"index\":0,\"delta\":{\"tool_calls\":[{\"index\":0,\"function\":{\"arguments\":\"{\\\"path\\\":\\\"very_long_filename_that_gets_split_across_multiple_chunks.txt\\\"}\"}}]},\"finish_reason\":null}]}",
    "{\"id\":\"chatcmpl-1\",\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"tool_calls\"}]}",
    "[DONE]",
  ])
  // 冻结期望（ruby_results.json stream-009）
  assert_eq(resp.finish_reason, Some("tool_calls"))
  guard resp.tool_calls is Some(calls) && calls.length() == 1 else {
    fail("expected exactly 1 tool call")
  }
  assert_tool_call(
    calls[0],
    id="call_1",
    name="read_file",
    arguments="{\"path\":\"very_long_filename_that_gets_split_across_multiple_chunks.txt\"}",
  )
}

// ── stream-010 content 和 tool_calls 混合 ────────────────────────────────────

///|
test "stream_010_mixed_content_tool_calls" {
  let resp = aggregate([
    "{\"id\":\"chatcmpl-1\",\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\"},\"finish_reason\":null}]}",
    "{\"id\":\"chatcmpl-1\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"I'll help you. \"},\"finish_reason\":null}]}",
    "{\"id\":\"chatcmpl-1\",\"choices\":[{\"index\":0,\"delta\":{\"tool_calls\":[{\"index\":0,\"id\":\"call_1\",\"type\":\"function\",\"function\":{\"name\":\"read_file\",\"arguments\":\"{\\\"path\\\":\\\"test.txt\\\"}\"}}]},\"finish_reason\":null}]}",
    "{\"id\":\"chatcmpl-1\",\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"tool_calls\"}]}",
    "[DONE]",
  ])
  // 冻结期望（ruby_results.json stream-010）
  assert_eq(resp.content, Some("I'll help you. "))
  assert_eq(resp.finish_reason, Some("tool_calls"))
  guard resp.tool_calls is Some(calls) && calls.length() == 1 else {
    fail("expected exactly 1 tool call")
  }
  assert_tool_call(
    calls[0],
    id="call_1",
    name="read_file",
    arguments="{\"path\":\"test.txt\"}",
  )
}

// ── stream-011 frames_seen 统计（核心字段 + 统计 known-failure） ────────────

///|
test "stream_011_core" {
  let resp = aggregate([
    "{\"id\":\"chatcmpl-1\",\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\"},\"finish_reason\":null}]}",
    "{\"id\":\"chatcmpl-1\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"Hi\"},\"finish_reason\":null}]}",
    "{\"id\":\"chatcmpl-1\",\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"stop\"}]}",
    "[DONE]",
  ])
  // 冻结期望（ruby_results.json stream-011）
  assert_eq(resp.content, Some("Hi"))
  assert_eq(resp.finish_reason, Some("stop"))
}

///|
test "stream_011_stats_known_failure" {
  // BUG-0006：证据 test_cases.json stream-011，
  // ruby_results.json 实测 frames_seen=3, bytes_seen=265, saw_done=true,
  // approximate_output_tokens=1。
  if known_failure("BUG-0006") {
    return
  }
  fail(
    "BUG-0006 已修复：请补写统计断言（frames_seen=3, bytes_seen=265, saw_done=true, approximate_output_tokens=1）",
  )
}

// ── stream-012 bytes_seen 统计 ───────────────────────────────────────────────

///|
test "stream_012_core" {
  let resp = aggregate([
    "{\"id\":\"chatcmpl-1\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"Hi\"},\"finish_reason\":null}]}",
  ])
  // 冻结期望（ruby_results.json stream-012）：content="Hi", finish_reason=null
  assert_eq(resp.content, Some("Hi"))
  assert_true(resp.finish_reason is None)
}

///|
test "stream_012_stats_known_failure" {
  // BUG-0006：证据 test_cases.json stream-012（bytes_seen_min=70），
  // ruby_results.json 实测 bytes_seen=89, frames_seen=1, saw_done=false,
  // approximate_output_tokens=1。
  if known_failure("BUG-0006") {
    return
  }
  fail(
    "BUG-0006 已修复：请补写统计断言（frames_seen=1, bytes_seen=89, saw_done=false, approximate_output_tokens=1）",
  )
}

// ── stream-013 approximate_output_tokens 估算 ────────────────────────────────

///|
test "stream_013_core" {
  let resp = aggregate([
    "{\"id\":\"chatcmpl-1\",\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\"},\"finish_reason\":null}]}",
    "{\"id\":\"chatcmpl-1\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"Hello world\"},\"finish_reason\":null}]}",
    "{\"id\":\"chatcmpl-1\",\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"stop\"}]}",
  ])
  // 冻结期望（ruby_results.json stream-013）
  assert_eq(resp.content, Some("Hello world"))
  assert_eq(resp.finish_reason, Some("stop"))
}

///|
test "stream_013_stats_known_failure" {
  // BUG-0006：证据 test_cases.json stream-013（approximate_output_tokens_min=2），
  // ruby_results.json 实测 approximate_output_tokens=3, frames_seen=3,
  // bytes_seen=268, saw_done=false。
  if known_failure("BUG-0006") {
    return
  }
  fail(
    "BUG-0006 已修复：请补写统计断言（frames_seen=3, bytes_seen=268, saw_done=false, approximate_output_tokens=3）",
  )
}

// ── stream-014 多个 content chunk 累积 ───────────────────────────────────────

///|
test "stream_014_many_content_chunks" {
  let resp = aggregate([
    "{\"id\":\"chatcmpl-1\",\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\"},\"finish_reason\":null}]}",
    "{\"id\":\"chatcmpl-1\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"A\"},\"finish_reason\":null}]}",
    "{\"id\":\"chatcmpl-1\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"B\"},\"finish_reason\":null}]}",
    "{\"id\":\"chatcmpl-1\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"C\"},\"finish_reason\":null}]}",
    "{\"id\":\"chatcmpl-1\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"D\"},\"finish_reason\":null}]}",
    "{\"id\":\"chatcmpl-1\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"E\"},\"finish_reason\":null}]}",
    "{\"id\":\"chatcmpl-1\",\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"stop\"}]}",
    "[DONE]",
  ])
  // 冻结期望（ruby_results.json stream-014）
  assert_eq(resp.content, Some("ABCDE"))
  assert_eq(resp.finish_reason, Some("stop"))
}

// ── stream-015 tool_call arguments 跨多个 chunk ──────────────────────────────

///|
test "stream_015_tool_call_args_many_chunks" {
  let resp = aggregate([
    "{\"id\":\"chatcmpl-1\",\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\"},\"finish_reason\":null}]}",
    "{\"id\":\"chatcmpl-1\",\"choices\":[{\"index\":0,\"delta\":{\"tool_calls\":[{\"index\":0,\"id\":\"call_1\",\"type\":\"function\",\"function\":{\"name\":\"write_file\",\"arguments\":\"\"}}]},\"finish_reason\":null}]}",
    "{\"id\":\"chatcmpl-1\",\"choices\":[{\"index\":0,\"delta\":{\"tool_calls\":[{\"index\":0,\"function\":{\"arguments\":\"{\\\"\"}}]},\"finish_reason\":null}]}",
    "{\"id\":\"chatcmpl-1\",\"choices\":[{\"index\":0,\"delta\":{\"tool_calls\":[{\"index\":0,\"function\":{\"arguments\":\"path\"}}]},\"finish_reason\":null}]}",
    "{\"id\":\"chatcmpl-1\",\"choices\":[{\"index\":0,\"delta\":{\"tool_calls\":[{\"index\":0,\"function\":{\"arguments\":\"\\\":\\\"\"}}]},\"finish_reason\":null}]}",
    "{\"id\":\"chatcmpl-1\",\"choices\":[{\"index\":0,\"delta\":{\"tool_calls\":[{\"index\":0,\"function\":{\"arguments\":\"test\"}}]},\"finish_reason\":null}]}",
    "{\"id\":\"chatcmpl-1\",\"choices\":[{\"index\":0,\"delta\":{\"tool_calls\":[{\"index\":0,\"function\":{\"arguments\":\".txt\\\"}\"}}]},\"finish_reason\":null}]}",
    "{\"id\":\"chatcmpl-1\",\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"tool_calls\"}]}",
    "[DONE]",
  ])
  // 冻结期望（ruby_results.json stream-015）
  assert_eq(resp.finish_reason, Some("tool_calls"))
  guard resp.tool_calls is Some(calls) && calls.length() == 1 else {
    fail("expected exactly 1 tool call")
  }
  assert_tool_call(
    calls[0],
    id="call_1",
    name="write_file",
    arguments="{\"path\":\"test.txt\"}",
  )
}

// ── stream-016 只有 role chunk，无 content ───────────────────────────────────

///|
test "stream_016_role_only" {
  let resp = aggregate([
    "{\"id\":\"chatcmpl-1\",\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\"},\"finish_reason\":null}]}",
    "{\"id\":\"chatcmpl-1\",\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"stop\"}]}",
    "[DONE]",
  ])
  // 冻结期望（ruby_results.json stream-016）
  assert_true(resp.content is None)
  assert_eq(resp.finish_reason, Some("stop"))
}

// ── stream-017 empty choices 数组 ────────────────────────────────────────────

///|
test "stream_017_empty_choices" {
  let resp = aggregate([
    "{\"id\":\"chatcmpl-1\",\"choices\":[]}", "{\"id\":\"chatcmpl-1\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"Hello\"},\"finish_reason\":null}]}",
    "[DONE]",
  ])
  // 冻结期望（ruby_results.json stream-017）：content="Hello", finish_reason=null
  assert_eq(resp.content, Some("Hello"))
  assert_true(resp.finish_reason is None)
}

// ── stream-018 no choices key ────────────────────────────────────────────────

///|
test "stream_018_no_choices_key" {
  let resp = aggregate([
    "{\"id\":\"chatcmpl-1\"}", "{\"id\":\"chatcmpl-1\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"Hello\"},\"finish_reason\":null}]}",
    "[DONE]",
  ])
  // 冻结期望（ruby_results.json stream-018）：content="Hello", finish_reason=null
  assert_eq(resp.content, Some("Hello"))
  assert_true(resp.finish_reason is None)
}

// ── stream-019 multiple parse failures ───────────────────────────────────────

///|
test "stream_019_multiple_parse_failures_core" {
  let resp = aggregate([
    "invalid1", "invalid2", "invalid3", "{\"id\":\"chatcmpl-1\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"Hello\"},\"finish_reason\":null}]}",
    "[DONE]",
  ])
  // 冻结期望（ruby_results.json stream-019）：content="Hello", finish_reason=null
  assert_eq(resp.content, Some("Hello"))
  assert_true(resp.finish_reason is None)
}

///|
test "stream_019_stats_known_failure" {
  // BUG-0006：证据 test_cases.json stream-019，
  // ruby_results.json 实测 parse_failures=3, frames_seen=4, bytes_seen=122,
  // saw_done=true, approximate_output_tokens=2。
  if known_failure("BUG-0006") {
    return
  }
  fail(
    "BUG-0006 已修复：请补写统计断言（parse_failures=3, frames_seen=4, bytes_seen=122, saw_done=true, approximate_output_tokens=2）",
  )
}

// ── stream-020 usage with cache tokens ───────────────────────────────────────

///|
test "stream_020_usage_cache_tokens" {
  let resp = aggregate([
    "{\"id\":\"chatcmpl-1\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"Hi\"},\"finish_reason\":null}]}",
    "{\"id\":\"chatcmpl-1\",\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"stop\"}]}",
    "{\"id\":\"chatcmpl-1\",\"choices\":[],\"usage\":{\"prompt_tokens\":100,\"completion_tokens\":10,\"prompt_tokens_details\":{\"cached_tokens\":50}}}",
  ])
  // 冻结期望（ruby_results.json stream-020）：prompt_tokens=100, completion_tokens=10
  assert_eq(resp.content, Some("Hi"))
  assert_eq(resp.finish_reason, Some("stop"))
  guard resp.usage is Some(usage) else { fail("expected usage") }
  assert_eq(usage.input_tokens, 100)
  assert_eq(usage.output_tokens, 10)
  // 注意：Ruby 侧原样保留 usage 哈希（含 prompt_tokens_details.cached_tokens=50）；
  // MB 侧 Usage 归一化为 cache_read_input_tokens，且不读取
  // prompt_tokens_details.cached_tokens，该信息丢失（实测 cache_read_input_tokens=0）。
  // 已登记 BUG-0051（diff-harness reports/BUGS.md），修复后补 cached_tokens 断言。
}
