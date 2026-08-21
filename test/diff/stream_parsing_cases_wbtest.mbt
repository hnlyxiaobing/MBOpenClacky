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
/// 投喂 SSE data 行序列并返回（响应 + 聚合器），用于断言 frames_seen /
/// bytes_seen / parse_failures / saw_done / approximate_output_tokens 统计面
/// （BUG-0006 修复后由 *_stats 套件触发）。
fn aggregate_with_stats(
  chunks : Array[String],
) -> (@client.LlmResponse, @client.OpenAiStreamAggregator) {
  let agg = @client.OpenAiStreamAggregator::new()
  for chunk in chunks {
    agg.handle(chunk)
  }
  (agg.to_response(), agg)
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
test "stream_005_malformed_json_stats" {
  // BUG-0006 修复后断言：畸形行被计入 parse_failures，不影响 frames_seen。
  // 冻结值（ruby_results.json stream-005）：
  //   parse_failures=1, frames_seen=4, bytes_seen=284,
  //   saw_done=true, approximate_output_tokens=2。
  let (resp, agg) = aggregate_with_stats([
    "{\"id\":\"chatcmpl-1\",\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\"},\"finish_reason\":null}]}",
    "this is not json", "{\"id\":\"chatcmpl-1\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"Hello\"},\"finish_reason\":null}]}",
    "{\"id\":\"chatcmpl-1\",\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"stop\"}]}",
    "[DONE]",
  ])
  assert_eq(resp.content, Some("Hello"))
  assert_eq(resp.finish_reason, Some("stop"))
  assert_eq(agg.frames_seen, 4)
  assert_eq(agg.bytes_seen, 284)
  assert_eq(agg.parse_failures, 1)
  assert_eq(agg.saw_done, true)
  assert_eq(agg.approximate_output_tokens(), 2)
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
test "stream_007_only_done_stats" {
  // BUG-0006 修复后断言：只投喂 [DONE]，frames_seen=0，bytes_seen 仍记录
  // 原始 payload 长度（含 `data:` 前缀与 `[DONE]` 文本）。
  // 冻结值（ruby_results.json stream-007）：
  //   saw_done=true, frames_seen=0, bytes_seen=6。
  let (_, agg) = aggregate_with_stats(["[DONE]"])
  assert_eq(agg.frames_seen, 0)
  assert_eq(agg.bytes_seen, 6)
  assert_eq(agg.saw_done, true)
  assert_eq(agg.parse_failures, 0)
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
test "stream_011_stats" {
  // BUG-0006 修复后断言：3 个有效 frame + [DONE]，输出 token 数 = 1
  // （"Hi" 一字，按 4 字符/token 估算四舍五入到 1）。
  // 冻结值（ruby_results.json stream-011）：
  //   frames_seen=3, bytes_seen=265, saw_done=true,
  //   approximate_output_tokens=1。
  let (resp, agg) = aggregate_with_stats([
    "{\"id\":\"chatcmpl-1\",\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\"},\"finish_reason\":null}]}",
    "{\"id\":\"chatcmpl-1\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"Hi\"},\"finish_reason\":null}]}",
    "{\"id\":\"chatcmpl-1\",\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"stop\"}]}",
    "[DONE]",
  ])
  assert_eq(resp.content, Some("Hi"))
  assert_eq(resp.finish_reason, Some("stop"))
  assert_eq(agg.frames_seen, 3)
  assert_eq(agg.bytes_seen, 265)
  assert_eq(agg.saw_done, true)
  assert_eq(agg.approximate_output_tokens(), 1)
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
test "stream_012_stats" {
  // BUG-0006 修复后断言：单条 data 行（无 [DONE]），saw_done=false，
  // bytes_seen 计数与 ruby_results.json 对齐。
  // 冻结值（ruby_results.json stream-012）：
  //   bytes_seen=89, frames_seen=1, saw_done=false,
  //   approximate_output_tokens=1。
  let (resp, agg) = aggregate_with_stats([
    "{\"id\":\"chatcmpl-1\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"Hi\"},\"finish_reason\":null}]}",
  ])
  assert_eq(resp.content, Some("Hi"))
  assert_true(resp.finish_reason is None)
  assert_eq(agg.frames_seen, 1)
  assert_eq(agg.bytes_seen, 89)
  assert_eq(agg.saw_done, false)
  assert_eq(agg.approximate_output_tokens(), 1)
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
test "stream_013_stats" {
  // BUG-0006 修复后断言：3 frame 累积 "Hello world"（11 字符/4=2.75 → 3 token），
  // 无 [DONE] → saw_done=false。
  // 冻结值（ruby_results.json stream-013）：
  //   approximate_output_tokens=3, frames_seen=3,
  //   bytes_seen=268, saw_done=false。
  let (resp, agg) = aggregate_with_stats([
    "{\"id\":\"chatcmpl-1\",\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\"},\"finish_reason\":null}]}",
    "{\"id\":\"chatcmpl-1\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"Hello world\"},\"finish_reason\":null}]}",
    "{\"id\":\"chatcmpl-1\",\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"stop\"}]}",
  ])
  assert_eq(resp.content, Some("Hello world"))
  assert_eq(resp.finish_reason, Some("stop"))
  assert_eq(agg.frames_seen, 3)
  assert_eq(agg.bytes_seen, 268)
  assert_eq(agg.saw_done, false)
  assert_eq(agg.approximate_output_tokens(), 3)
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
test "stream_019_multiple_parse_failures_stats" {
  // BUG-0006 修复后断言：3 条畸形行 + 1 个有效 frame + [DONE]，
  // parse_failures=3, frames_seen=4（仅有效 frame）。
  // 冻结值（ruby_results.json stream-019）：
  //   parse_failures=3, frames_seen=4, bytes_seen=122,
  //   saw_done=true, approximate_output_tokens=2。
  let (resp, agg) = aggregate_with_stats([
    "invalid1", "invalid2", "invalid3", "{\"id\":\"chatcmpl-1\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"Hello\"},\"finish_reason\":null}]}",
    "[DONE]",
  ])
  assert_eq(resp.content, Some("Hello"))
  assert_true(resp.finish_reason is None)
  assert_eq(agg.parse_failures, 3)
  assert_eq(agg.frames_seen, 4)
  assert_eq(agg.bytes_seen, 122)
  assert_eq(agg.saw_done, true)
  assert_eq(agg.approximate_output_tokens(), 2)
}

// ── stream-020 usage with cache tokens ───────────────────────────────────────

///|
test "stream_020_usage_cache_tokens" {
  let resp = aggregate([
    "{\"id\":\"chatcmpl-1\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"Hi\"},\"finish_reason\":null}]}",
    "{\"id\":\"chatcmpl-1\",\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"stop\"}]}",
    "{\"id\":\"chatcmpl-1\",\"choices\":[],\"usage\":{\"prompt_tokens\":100,\"completion_tokens\":10,\"prompt_tokens_details\":{\"cached_tokens\":50}}}",
  ])
  // 冻结期望（ruby_results.json stream-020）：prompt_tokens=100,
  // completion_tokens=10, prompt_tokens_details.cached_tokens=50
  // (Ruby 侧原样保留)。
  // MB 侧：top-level cache_read_input_tokens 优先；缺省时从
  // prompt_tokens_details.cached_tokens 兜底（fix for BUG-0051，see
  // diff-harness reports/BUGS.md）。
  assert_eq(resp.content, Some("Hi"))
  assert_eq(resp.finish_reason, Some("stop"))
  guard resp.usage is Some(usage) else { fail("expected usage") }
  assert_eq(usage.input_tokens, 100)
  assert_eq(usage.output_tokens, 10)
  assert_eq(usage.cache_read_input_tokens, 50)
}
