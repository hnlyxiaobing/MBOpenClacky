/// # diff-harness 回归测试：context_compression 模块（token-001 ~ token-030）
///
/// 用例来源：diff-harness/cases/context_compression/test_cases.json；
/// 期望值冻结自 Ruby 实测 diff-harness/cases/context_compression/ruby_results.json
/// （cases 下 mb_results.json 为 Python 模拟，不可信，未采用）。
///
/// 入口说明（test/diff 为外部包，只能调 pub API）：
/// - 内容级估算（token-001~005）：@agent.estimate_history_tokens 单消息历史，
///   其 message_token_estimate 不含 per-message overhead，等价于内容级估算。
/// - 消息级估算（token-006~009）：@message.MessageHistory::estimate_tokens
///   （lib/message/history.mbt 的 estimate_token_count/estimate_message_tokens
///   均非 pub，无法直接调用，这是最近的 pub 包装）。
/// - 其余：lib/agent/compressor.mbt 与 compressor_helper.mbt 的 pub 函数。

///|
/// 构造带 tool_calls 的 assistant 消息。
fn assistant_with_tool_calls(
  content : String,
  calls : Array[@message.ToolCall],
) -> @message.Message {
  let msg = @message.Message::assistant(content)
  msg.tool_calls = Some(calls)
  msg
}

///|
/// 构造任意 content 的消息（内部字段一律 None）。
fn msg_of(
  role : @message.Role,
  content : @message.MessageContent,
) -> @message.Message {
  {
    role,
    content,
    tool_calls: None,
    tool_call_id: None,
    name: None,
    reasoning_content: None,
    task_id: None,
    created_at: None,
    system_injected: None,
    memory_update: None,
    subagent_instructions: None,
    subagent_result: None,
    token_usage: None,
    compressed_summary: None,
    transient: None,
  }
}

///|
/// 消息级 token 估算（含 per-message overhead），经 MessageHistory pub 包装。
fn message_tokens(msg : @message.Message) -> Int {
  @message.MessageHistory::from_messages([msg]).estimate_tokens()
}

///|
/// 取消息列表的 role 字符串序列。
fn roles_of(messages : Array[@message.Message]) -> Array[String] {
  let roles : Array[String] = []
  for m in messages {
    roles.push(m.role.to_string_value())
  }
  roles
}

// ── token-001 空字符串 token 估算 ────────────────────────────────────────────

///|
test "token_001_empty_string" {
  // 冻结期望（ruby_results.json token-001）：0
  assert_eq(@agent.estimate_history_tokens([@message.Message::user("")]), 0)
}

// ── token-002 纯 ASCII 文本 ──────────────────────────────────────────────────

///|
test "token_002_ascii_text" {
  // 冻结期望（ruby_results.json token-002）：8（ceil(29/4)）
  assert_eq(
    @agent.estimate_history_tokens([
      @message.Message::user("Hello, world! This is a test."),
    ]),
    8,
  )
}

// ── token-003 纯中文文本（BUG-0009） ─────────────────────────────────────────

///|
test "token_003_cjk_text_known_failure" {
  // BUG-0009：token 估算不区分 CJK 字符。
  // 证据：diff-harness/cases/context_compression/test_cases.json token-003；
  // ruby_results.json 实测 10（14 个 CJK 字符按 ceil(14/1.5)）；
  // MB 实测 4（统一 (14+3)/4）。
  if known_failure("BUG-0009") {
    return
  }
  assert_eq(
    @agent.estimate_history_tokens([
      @message.Message::user("你好世界这是一段中文测试文本"),
    ]),
    10,
  )
}

// ── token-004 混合中英文文本（BUG-0009） ─────────────────────────────────────

///|
test "token_004_mixed_text_known_failure" {
  // BUG-0009：证据 test_cases.json token-004；
  // ruby_results.json 实测 6（13 ASCII / 4 CJK 分别计价后合并 ceil）；
  // MB 实测 5（统一 (17+3)/4）。
  if known_failure("BUG-0009") {
    return
  }
  assert_eq(
    @agent.estimate_history_tokens([
      @message.Message::user("Hello 你好 World 世界"),
    ]),
    6,
  )
}

// ── token-005 长 ASCII 文本 ──────────────────────────────────────────────────

///|
test "token_005_long_ascii" {
  // 冻结期望（ruby_results.json token-005）：31（ceil(123/4)）
  assert_eq(
    @agent.estimate_history_tokens([
      @message.Message::user(
        "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.",
      ),
    ]),
    31,
  )
}

// ── token-006 包含 tool_calls 的消息（BUG-0010） ─────────────────────────────

///|
test "token_006_tool_calls_known_failure" {
  // BUG-0010：tool_calls 估算每个 call 多加 50 tokens。
  // 证据：test_cases.json token-006；ruby_results.json 实测 16
  // （4 overhead + content 4 + name 3 + arguments 5）。
  // MB 实测 66（多 50）。
  if known_failure("BUG-0010") {
    return
  }
  let msg = assistant_with_tool_calls("Let me help you.", [
    @message.ToolCall::new("call_1", "read_file", "{\"path\": \"test.txt\"}"),
  ])
  assert_eq(message_tokens(msg), 16)
}

// ── token-007 多个 tool_calls（BUG-0010） ────────────────────────────────────

///|
test "token_007_multiple_tool_calls_known_failure" {
  // BUG-0010：证据 test_cases.json token-007；ruby_results.json 实测 31。
  // MB 实测 131（每个 call 多 50，共多 100）。
  if known_failure("BUG-0010") {
    return
  }
  let msg = assistant_with_tool_calls("I'll do multiple things.", [
    @message.ToolCall::new("call_1", "read_file", "{\"path\": \"a.txt\"}"),
    @message.ToolCall::new(
      "call_2", "write_file", "{\"path\": \"b.txt\", \"content\": \"hello\"}",
    ),
  ])
  assert_eq(message_tokens(msg), 31)
}

// ── token-008 图片内容（BUG-0048） ───────────────────────────────────────────

///|
test "token_008_image_content_known_failure" {
  // BUG-0048：图片消息 token 估算差异。
  // 证据：diff-harness/cases/context_compression/test_cases.json token-008 +
  // ruby_results.json 实测 8（4 overhead + 文本 5 个 CJK 字符 ceil(5/1.5)=4；
  // 图片块无 text 字段计 0）。MB 实测 106（4 + (5+3)/4=2 + 图片固定 100）。
  // 注意：BUGS.md BUG-0048 备注——cases 原 notes 称"两侧都按 100"与 Ruby 实测
  // 矛盾（疑 Ruby driver 口径问题），修复前先核实 Ruby 侧真实计算路径；
  // 断言暂按 Ruby 实测值 8 冻结。
  if known_failure("BUG-0048") {
    return
  }
  let msg = msg_of(
    @message.Role::User,
    @message.MessageContent::Blocks([
      @message.ContentBlock::Text({ text: "看这张图片" }),
      @message.ContentBlock::Image({
        url: "data:image/png;base64,...",
        detail: None,
      }),
    ]),
  )
  assert_eq(message_tokens(msg), 8)
}

// ── token-009 空 content + tool_calls（BUG-0010） ────────────────────────────

///|
test "token_009_null_content_tool_calls_known_failure" {
  // BUG-0010：证据 test_cases.json token-009；ruby_results.json 实测 6
  // （4 + content 0 + name 1 + arguments 1）。MB 实测 56（多 50）。
  // 注：MB 的 Message.content 不可为 null，以 Text("") 对应 Ruby 的 content=null。
  if known_failure("BUG-0010") {
    return
  }
  let msg = assistant_with_tool_calls("", [
    @message.ToolCall::new("call_1", "test", "{}"),
  ])
  assert_eq(message_tokens(msg), 6)
}

// ── token-010 压缩判断 - token 阈值 ──────────────────────────────────────────

///|
test "token_010_needs_compression_token_threshold" {
  // 冻结期望（ruby_results.json token-010）：needs_compression=true,
  // token_threshold=150000。此处冻结阈值常量与判定式；
  // Agent::needs_compression 在 token 阈值触发时另有 10% 最小收益检查
  // （BUG-0043，回归测试在 lib/agent/compressor_wbtest.mbt），不在本例范围。
  assert_eq(@agent.compression_threshold, 150000)
  assert_eq(@agent.message_count_threshold, 200)
  let needs = 160000 >= @agent.compression_threshold ||
    50 >= @agent.message_count_threshold
  assert_true(needs)
}

// ── token-011 压缩判断 - 消息数阈值 ──────────────────────────────────────────

///|
test "token_011_needs_compression_msg_threshold" {
  // 冻结期望（ruby_results.json token-011）：needs_compression=true,
  // msg_threshold=200
  let needs = 50000 >= @agent.compression_threshold ||
    210 >= @agent.message_count_threshold
  assert_true(needs)
}

// ── token-012 不需要压缩 ─────────────────────────────────────────────────────

///|
test "token_012_no_compression" {
  // 冻结期望（ruby_results.json token-012）：needs_compression=false
  let needs = 50000 >= @agent.compression_threshold ||
    50 >= @agent.message_count_threshold
  assert_false(needs)
}

// ── token-013 获取最近消息 - 保留 tool pairs ─────────────────────────────────

///|
test "token_013_recent_with_tool_pairs" {
  let msgs = [
    @message.Message::user("msg1"),
    assistant_with_tool_calls("msg2", [@message.ToolCall::new("c1", "f1", "{}")]),
    @message.Message::tool_result("c1", "f1", "result1"),
    @message.Message::user("msg3"),
    @message.Message::assistant("msg4"),
    @message.Message::user("msg5"),
  ]
  let recent = @agent.get_recent_with_tool_pairs(msgs, 3)
  // 冻结期望（ruby_results.json token-013）：
  // count=3, roles=[user, assistant, user], has_tool_pair=false
  assert_eq(recent.length(), 3)
  assert_eq(roles_of(recent), ["user", "assistant", "user"])
  assert_true(recent.iter().all(fn(m) { m.role != @message.Role::Tool }))
}

// ── token-014 获取最近消息 - 排除 system 消息 ────────────────────────────────

///|
test "token_014_recent_excludes_system" {
  let msgs = [
    @message.Message::system("system prompt"),
    @message.Message::user("msg1"),
    @message.Message::assistant("msg2"),
    @message.Message::user("msg3"),
  ]
  let recent = @agent.get_recent_with_tool_pairs(msgs, 2)
  // 冻结期望（ruby_results.json token-014）：
  // count=2, roles=[assistant, user], has_system=false
  assert_eq(recent.length(), 2)
  assert_eq(roles_of(recent), ["assistant", "user"])
  assert_true(recent.iter().all(fn(m) { m.role != @message.Role::System }))
}

// ── token-015 层次化摘要 Level 1 ─────────────────────────────────────────────

///|
test "token_015_hierarchical_summary_level1" {
  // 冻结期望（ruby_results.json token-015）
  assert_eq(
    @agent.generate_hierarchical_summary(
      ["Summary 1", "Summary 2", "Summary 3"],
      1,
    ),
    "Summary 1\n\nSummary 2\n\nSummary 3",
  )
}

// ── token-016 层次化摘要 Level 2 ─────────────────────────────────────────────

///|
test "token_016_hierarchical_summary_level2" {
  // 冻结期望（ruby_results.json token-016）
  assert_eq(
    @agent.generate_hierarchical_summary(
      ["First sentence. Second sentence.", "Another summary. More details."],
      2,
    ),
    "Conversation summary:\nFirst sentence.\nAnother summary.",
  )
}

// ── token-017 层次化摘要 Level 3 ─────────────────────────────────────────────

///|
test "token_017_hierarchical_summary_level3" {
  // 冻结期望（ruby_results.json token-017）
  assert_eq(
    @agent.generate_hierarchical_summary(
      ["Key decision was made. Task completed.", "Another milestone reached."],
      3,
    ),
    "Key progress: Key decision was made. Task completed; Another milestone reached",
  )
}

// ── token-018 层次化摘要 Level 4+ ────────────────────────────────────────────

///|
test "token_018_hierarchical_summary_level4" {
  // 冻结期望（ruby_results.json token-018）
  assert_eq(
    @agent.generate_hierarchical_summary(
      ["Summary 1", "Summary 2", "Summary 3"],
      4,
    ),
    "Progress across 3 compression(s): Summary 1",
  )
}

// ── token-019 工具结果截断 ───────────────────────────────────────────────────

///|
test "token_019_truncate_tool_result" {
  let long_content = String::make(3000, 'A')
  let result = @agent.truncate_tool_result(long_content, max_chars=2000)
  // 冻结期望（ruby_results.json token-019）：前 1500 字符 + 截断标记
  assert_eq(result, String::make(1500, 'A') + "... [truncated 1500 chars] ...")
}

// ── token-020 工具结果不截断 ─────────────────────────────────────────────────

///|
test "token_020_no_truncation" {
  // 冻结期望（ruby_results.json token-020）
  assert_eq(
    @agent.truncate_tool_result("Short content", max_chars=2000),
    "Short content",
  )
}

// ── token-021 XML 提取 - topics ──────────────────────────────────────────────

///|
test "token_021_xml_extract_topics" {
  // 冻结期望（ruby_results.json token-021）
  assert_eq(
    @agent.extract_xml_content(
      "<topics>Rails setup, database config</topics>\n<summary>\nDetailed summary here.\n</summary>",
      "topics",
    ),
    Some("Rails setup, database config"),
  )
}

// ── token-022 XML 提取 - summary ─────────────────────────────────────────────

///|
test "token_022_xml_extract_summary" {
  // 冻结期望（ruby_results.json token-022）
  assert_eq(
    @agent.extract_xml_content(
      "<summary>\nDetailed summary here.\n</summary>", "summary",
    ),
    Some("Detailed summary here."),
  )
}

// ── token-023 XML 提取 - 缺少标签 ────────────────────────────────────────────

///|
test "token_023_xml_extract_missing_tag" {
  // 冻结期望（ruby_results.json token-023）：null
  assert_eq(@agent.extract_xml_content("No tags here", "topics"), None)
}

// ── token-024 压缩统计计算 ───────────────────────────────────────────────────

///|
test "token_024_compression_stats" {
  let stats = @agent.calculate_compression_savings(100000, 10000, 200, 20)
  // 冻结期望（ruby_results.json token-024）
  assert_eq(stats.before_tokens, 100000)
  assert_eq(stats.after_tokens, 10000)
  assert_eq(stats.messages_removed, 180)
  assert_eq(stats.compression_ratio, 0.9)
}

// ── token-025 应跳过压缩 - 压缩率不足 ────────────────────────────────────────

///|
test "token_025_skip_compression_low_reduction" {
  // 冻结期望（ruby_results.json token-025）：should_skip=true（10% 阈值）
  assert_true(@agent.should_skip_compression(0.05))
}

// ── token-026 不应跳过压缩 - 压缩率足够 ──────────────────────────────────────

///|
test "token_026_no_skip_compression" {
  // 冻结期望（ruby_results.json token-026）：should_skip=false
  assert_false(@agent.should_skip_compression(0.3))
}

// ── token-027 目标最近消息数（BUG-0049） ─────────────────────────────────────

///|
test "token_027_target_recent_count_known_failure" {
  // BUG-0049：分层摘要 token 钳制公式差异。
  // 证据：diff-harness/cases/context_compression/test_cases.json token-027 +
  // ruby_results.json 实测 20（token 预算 10000*0.2=2000 / 500 = 4，钳制到
  // [20, 20]）。MB 实测 19——公式为 total*(1-ratio) 钳制 [10,50]，且
  // 100*(1.0-0.8) 在 IEEE754 下为 19.999...，to_int 截断得 19。
  if known_failure("BUG-0049") {
    return
  }
  assert_eq(@agent.calculate_target_recent_count(100, 0.8), 20)
}

// ── token-028 提取关键信息（BUG-0050） ───────────────────────────────────────

///|
test "token_028_extract_key_information_known_failure" {
  // BUG-0050：关键信息提取规则差异。
  // 证据：diff-harness/cases/context_compression/test_cases.json token-028 +
  // ruby_results.json 实测 files_mentioned=["File created successfully at main.py"]、
  // decisions_made=[]、errors_encountered=["Error: test failed"]。
  // MB 实测：files_mentioned=[]（"File created..." 无路径分隔符，
  //   不满足 is_likely_file_path）；decisions_made=[]（中文"使用"不匹配
  //   英文关键词 "using"）；errors_encountered=[]（仅扫描 User/Assistant
  //   消息，"Error: test failed" 在 Tool 消息中）。
  //   另：MB 将 "File created successfully at main.py" 归入 tasks_completed
  //   （含 "created"/"success"），Ruby 简化提取无此维度。
  if known_failure("BUG-0050") {
    return
  }
  let msgs = [
    @message.Message::user("请帮我创建 main.py 文件"),
    @message.Message::assistant(
      "我决定使用 Python 3.12 来创建这个项目",
    ),
    @message.Message::tool_result(
      "c1", "f1", "File created successfully at main.py",
    ),
    @message.Message::user("运行测试"),
    @message.Message::tool_result("c2", "f2", "Error: test failed"),
    @message.Message::assistant("测试失败了，让我修复"),
  ]
  let info = @agent.extract_key_information(msgs)
  assert_eq(info.files_mentioned, ["File created successfully at main.py"])
  assert_eq(info.decisions_made, [])
  assert_eq(info.errors_encountered, ["Error: test failed"])
}

// ── token-029 溢出恢复 - 保留 tool pairs（BUG-0011） ─────────────────────────

///|
test "token_029_overflow_keeps_tool_pairs_known_failure" {
  // BUG-0011：溢出恢复拆散 tool pair。
  // 证据：diff-harness/cases/context_compression/test_cases.json token-029；
  // ruby_results.json 实测 kept_count=4, kept_roles=[user, assistant, tool, user]
  // （总估算 23 <= max_tokens=50，无需弹出）。
  // MB 实测：kept_count=1——每个 tool_call 计 50 tokens（BUG-0010）使
  // assistant 消息估算 51 > 50，连乘弹出至只剩 user msg1。
  if known_failure("BUG-0011") {
    return
  }
  let msgs = [
    @message.Message::user("msg1"),
    assistant_with_tool_calls("msg2", [@message.ToolCall::new("c1", "f1", "{}")]),
    @message.Message::tool_result("c1", "f1", "result1"),
    @message.Message::user("msg3"),
  ]
  let (kept, _pulled) = @agent.pulled_back_messages(msgs, 50)
  assert_eq(kept.length(), 4)
  assert_eq(roles_of(kept), ["user", "assistant", "tool", "user"])
}

// ── token-030 构建压缩摘要消息 ───────────────────────────────────────────────

///|
test "token_030_build_summary_message" {
  let msg = @agent.build_compressed_summary_message(
    "This is a test summary.", "test, summary",
  )
  // 冻结期望（ruby_results.json token-030）：role=user, system_injected=true
  assert_true(msg.role == @message.Role::User)
  assert_eq(msg.system_injected, Some(true))
  guard msg.content is @message.MessageContent::Text(content) else {
    fail("expected text content")
  }
  assert_eq(
    content, "[Compressed conversation summary — previous turns archived]\nTopics: test, summary\n\nThis is a test summary.",
  )
}
