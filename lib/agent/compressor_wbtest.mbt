///|
/// Tests for the Insert-then-Compress message compression system.
test "CompressionConfig default values" {
  let config = CompressionConfig::default()
  @debug.debug_inspect(config.max_recent_messages, content="20")
  @debug.debug_inspect(config.target_compressed_tokens, content="10000")
  @debug.debug_inspect(config.idle_compression_threshold, content="20000")
}

///|
test "build_compression_message creates valid message" {
  let msg = build_compression_message()
  // Should be a user message
  assert_true(msg.role == @message.User)
  // Should be system_injected
  assert_true(msg.system_injected == Some(true))
  // Should have text content containing the compression prompt keywords
  match msg.content {
    @message.Text(s) => {
      assert_true(s.contains("MEMORY COMPRESSION MODE"))
      assert_true(s.contains("<topics>"))
      assert_true(s.contains("<summary>"))
    }
    _ => fail("Expected Text content")
  }
  // Should have no tool_calls
  assert_true(msg.tool_calls == None)
}

///|
test "parse_compression_response valid format" {
  let response = "<topics>MoonBit setup, agent config, tool system</topics>\n<summary>\nThe user worked on setting up a MoonBit project with agent configuration.\nThey implemented the tool system and fixed compilation errors.\n</summary>"
  let result = parse_compression_response(response)
  match result {
    Ok(parsed) => {
      @debug.assert_eq(
        parsed.topics,
        "MoonBit setup, agent config, tool system",
      )
      assert_true(parsed.summary.contains("MoonBit project"))
      assert_true(parsed.summary.contains("tool system"))
    }
    Err(e) => fail("Expected Ok but got Err: \{e}")
  }
}

///|
test "parse_compression_response missing tags" {
  let response = "This is just plain text without any XML tags."
  let result = parse_compression_response(response)
  match result {
    Ok(_) => fail("Expected Err for missing tags")
    Err(e) => assert_true(e.contains("missing <summary> tag"))
  }
}

///|
test "parse_compression_response missing topics only" {
  let response = "<summary>\nSome summary content here.\n</summary>"
  let result = parse_compression_response(response)
  match result {
    Ok(parsed) => {
      // Topics should be empty string when missing
      @debug.assert_eq(parsed.topics, "")
      assert_true(parsed.summary.contains("Some summary content"))
    }
    Err(e) => fail("Expected Ok but got Err: \{e}")
  }
}

///|
test "rebuild_history_with_compression" {
  let messages : Array[@message.Message] = [
    @message.Message::system("You are an assistant."),
    @message.Message::user("Hello"),
    @message.Message::assistant("Hi there!"),
    @message.Message::user("What is MoonBit?"),
    @message.Message::assistant("MoonBit is a programming language."),
    @message.Message::user("Thanks"),
    @message.Message::assistant("You're welcome!"),
  ]
  let result = rebuild_history_with_compression(
    messages, "The user asked about MoonBit and got an explanation.", "MoonBit, language",
    2,
  )
  // First should be the system message
  assert_true(result[0].role == @message.System)
  // Second should be the compressed summary
  match result[1].content {
    @message.Text(s) => {
      assert_true(s.contains("Compressed conversation summary"))
      assert_true(s.contains("MoonBit, language"))
    }
    _ => fail("Expected Text content for summary")
  }
  // Should contain recent messages at the end
  let last = result[result.length() - 1]
  assert_true(last.role == @message.Assistant)
}

///|
test "get_recent_with_tool_pairs keeps pairs together" {
  let tc : @message.ToolCall = {
    id: "call_1",
    type_: "function",
    function: { name: "read_file", arguments: "{\"path\": \"test.txt\"}" },
    extra_content: None,
  }
  let messages : Array[@message.Message] = [
    @message.Message::user("Read my file"),
    {
      role: @message.Assistant,
      content: @message.Text(""),
      tool_calls: Some([tc]),
      tool_call_id: None,
      name: None,
      reasoning_content: None,
      latency: None,
      display_text: None,
      display_files: None,
      task_id: None,
      created_at: None,
      system_injected: None,
      memory_update: None,
      subagent_instructions: None,
      subagent_result: None,
      token_usage: None,
      compressed_summary: None,
      transient: None,
      session_date: None,
      session_context: None,
    },
    @message.Message::tool_result("call_1", "read_file", "file content here"),
    @message.Message::user("Now summarize it"),
    @message.Message::assistant("Here is the summary."),
  ]
  // Request 3 messages - should include tool pair together
  let recent = get_recent_with_tool_pairs(messages, 3)
  // Should get at least the tool_result, user, and assistant
  // And since tool_result links back, should also get the assistant with tool_calls
  assert_true(recent.length() >= 3)
  // Verify the tool_call and tool_result are both present
  let mut has_tool_call = false
  let mut has_tool_result = false
  for msg in recent {
    match msg.tool_calls {
      Some(calls) => if calls.length() > 0 { has_tool_call = true }
      _ => ()
    }
    if msg.role == @message.Tool {
      has_tool_result = true
    }
  }
  // If we have tool_result, we should also have the tool_call
  if has_tool_result {
    assert_true(has_tool_call)
  }
}

///|
test "get_recent_with_tool_pairs respects count" {
  let messages : Array[@message.Message] = [
    @message.Message::user("Message 1"),
    @message.Message::assistant("Reply 1"),
    @message.Message::user("Message 2"),
    @message.Message::assistant("Reply 2"),
    @message.Message::user("Message 3"),
    @message.Message::assistant("Reply 3"),
  ]
  let recent = get_recent_with_tool_pairs(messages, 4)
  // Should return exactly 4 messages
  @debug.assert_eq(recent.length(), 4)
  // Last should be the final assistant message
  assert_true(recent[recent.length() - 1].role == @message.Assistant)
}

///|
test "extract_xml_content" {
  // Basic extraction
  let result = extract_xml_content("<topics>hello, world</topics>", "topics")
  @debug.assert_eq(result, Some("hello, world"))
  // Multiline content
  let multi = extract_xml_content(
    "<summary>\nLine 1\nLine 2\n</summary>", "summary",
  )
  match multi {
    Some(s) => assert_true(s.contains("Line 1"))
    None => fail("Expected Some for multiline content")
  }
  // Missing tag
  let missing = extract_xml_content("no tags here", "topics")
  @debug.assert_eq(missing, None)
  // Empty tag
  let empty = extract_xml_content("<topics></topics>", "topics")
  assert_true(empty == None)
}

///|
test "should_trigger_idle_compression" {
  // Small message list - should not trigger
  let small : Array[@message.Message] = [
    @message.Message::user("Hi"),
    @message.Message::assistant("Hello!"),
  ]
  assert_true(should_trigger_idle_compression(small, 20000) == false)
  // Create a large message that exceeds threshold
  let buf = StringBuilder()
  for i = 0; i < 100000; i = i + 1 {
    buf.write_char('a')
    let _ = i
  }
  let large_text = buf.to_string()
  let large : Array[@message.Message] = [@message.Message::user(large_text)]
  assert_true(should_trigger_idle_compression(large, 20000))
}

///|
test "calculate_compression_savings" {
  let stats = calculate_compression_savings(100000, 10000, 50, 5)
  @debug.assert_eq(stats.before_tokens, 100000)
  @debug.assert_eq(stats.after_tokens, 10000)
  @debug.assert_eq(stats.messages_removed, 45)
  // Compression ratio should be 0.9 (90% reduction)
  assert_true(stats.compression_ratio > 0.89)
  assert_true(stats.compression_ratio < 0.91)
}

///|
test "calculate_compression_savings zero before" {
  let stats = calculate_compression_savings(0, 0, 0, 0)
  assert_true(stats.compression_ratio == 0.0)
  @debug.assert_eq(stats.messages_removed, 0)
}

///|
test "count_messages_to_compress" {
  let messages : Array[@message.Message] = [
    @message.Message::system("System prompt"),
    @message.Message::user("Hello"),
    @message.Message::assistant("Hi"),
    @message.Message::user("Question"),
    @message.Message::assistant("Answer"),
    @message.Message::user("Thanks"),
    @message.Message::assistant("Welcome"),
  ]
  // 6 non-system messages, keeping 2 recent => 4 to compress
  let count = count_messages_to_compress(messages, 2)
  @debug.assert_eq(count, 4)
  // Keep more than available => 0 to compress
  let count2 = count_messages_to_compress(messages, 10)
  @debug.assert_eq(count2, 0)
}

///|
test "needs_compression_uses_config_threshold" {
  let client = @client.Client::new(
    "key",
    "https://api.test.com",
    "model",
    @config.OpenAICompletions,
  )
  let config = @config.AgentConfig::default()
  let agent = Agent::new("s", "a", "/tmp", client, config)
  // Build a large enough history so that reduction_needed >= 10%
  // target_compressed_tokens = 10000, so we need > ~11111 tokens
  let buf = StringBuilder()
  for i = 0; i < 50000; i = i + 1 {
    buf.write_char('a')
    let _ = i
  }
  let large_text = buf.to_string()
  agent.history.append(@message.Message::user(large_text))
  agent.config.compression_threshold = 5
  assert_true(agent.needs_compression())
  agent.config.compression_threshold = 999_999
  assert_false(agent.needs_compression())
}

///|
test "needs_compression_skips_when_reduction_below_10pct (BUG-0043)" {
  // 回归用例：ruby 侧 message_compressor_helper.rb 在 token_threshold_exceeded 时
  // 额外要求 reduction_needed >= 10% * total_tokens；否则不触发压缩。
  // 场景：threshold=1（极低），但 history token_count << target_compressed_tokens(10000)，
  // 此时压缩收益为负，应跳过。
  let client = @client.Client::new(
    "key",
    "https://api.test.com",
    "model",
    @config.OpenAICompletions,
  )
  let config = @config.AgentConfig::default()
  let agent = Agent::new("s", "a", "/tmp", client, config)
  agent.config.compression_threshold = 1
  // 小 history：约几十 tokens，远低于 target_compressed_tokens=10000
  agent.history.append(
    @message.Message::user("Hello world, this is a test message"),
  )
  // Ruby: total=~13, reduction_needed = 13-10000 = -9987 < 13*0.1 → 不压缩
  assert_false(agent.needs_compression())
}

///|
test "needs_compression_uses_max_previous_total_tokens (BUG-0042)" {
  // 差异一回归：ruby 取 total_tokens = max(previous_total_tokens, estimate)
  // （message_compressor_helper.rb:143）。场景：threshold=1、history 很小
  // （estimate 远低于 target_compressed_tokens），但上一轮 API 报告
  // previous_total_tokens=15000 → max 后触发压缩（10% 检查同样通过）。
  let client = @client.Client::new(
    "key",
    "https://api.test.com",
    "model",
    @config.OpenAICompletions,
  )
  let config = @config.AgentConfig::default()
  let agent = Agent::new("s", "a", "/tmp", client, config)
  agent.config.compression_threshold = 1
  agent.history.append(
    @message.Message::user("Hello world, this is a test message"),
  )
  // previous_total_tokens 默认 0：estimate ≈ 13 → 10% 检查拦截
  assert_false(agent.needs_compression())
  // 上一轮 API 报告 15000：max(15000, ~13) = 15000 >= 1；
  // reduction_needed = 15000-10000 = 5000 >= 15000*0.1 → 触发
  agent.previous_total_tokens = 15000
  assert_true(agent.needs_compression())
}

///|
test "compress_messages_if_needed_guard_exception_oversized_tool_result (BUG-0042)" {
  // 差异二回归：recent >= non_system_count 时，若 history 含 content > 2000 字符的
  // tool_result，应继续压缩流程（模拟 ruby truncate_tool_result 截断后返回新 Hash、
  // 破坏对象相等性、使原始大 tool_result 落入待压缩集的副作用，helper.rb:472-478）；
  // 否则才返回 None。
  let client = @client.Client::new(
    "key",
    "https://api.test.com",
    "model",
    @config.OpenAICompletions,
  )
  let config = @config.AgentConfig::default()
  let agent = Agent::new("s", "a", "/tmp", client, config)
  agent.config.compression_threshold = 1
  agent.previous_total_tokens = 15000
  agent.history.append(@message.Message::system("system prompt"))
  agent.history.append(@message.Message::user("context"))
  agent.history.append(@message.Message::user("读一下 big.txt"))
  let asst = @message.Message::assistant("")
  asst.tool_calls = Some([
    @message.ToolCall::new("call_1", "file_reader", "{\"path\":\"big.txt\"}"),
  ])
  agent.history.append(asst)
  let big_result = Array::make(3000, "a").join("")
  agent.history.append(
    @message.Message::tool_result("call_1", "file_reader", big_result),
  )
  // 5 条消息（含 system）：recent = min(5, 20) = 5 >= non_system(4) → 守卫命中，
  // 但存在超大 tool_result → 例外放行，返回 Some
  assert_true(agent.compress_messages_if_needed(false) is Some(_))
}

///|
test "compress_messages_if_needed_guard_returns_none_without_oversized (BUG-0042)" {
  // 反向确认：同样 5 条消息但 tool_result <= 2000 字符 → 无截断副作用，
  // 守卫按原语义返回 None（全部非 system 消息都在 recent 中，无可压缩内容）。
  let client = @client.Client::new(
    "key",
    "https://api.test.com",
    "model",
    @config.OpenAICompletions,
  )
  let config = @config.AgentConfig::default()
  let agent = Agent::new("s", "a", "/tmp", client, config)
  agent.config.compression_threshold = 1
  agent.previous_total_tokens = 15000
  agent.history.append(@message.Message::system("system prompt"))
  agent.history.append(@message.Message::user("context"))
  agent.history.append(@message.Message::user("读一下 big.txt"))
  let asst = @message.Message::assistant("")
  asst.tool_calls = Some([
    @message.ToolCall::new("call_1", "file_reader", "{\"path\":\"big.txt\"}"),
  ])
  agent.history.append(asst)
  let small_result = Array::make(500, "a").join("")
  agent.history.append(
    @message.Message::tool_result("call_1", "file_reader", small_result),
  )
  assert_true(agent.compress_messages_if_needed(false) is None)
}

///|
/// BUG-0011 决策 3 验收：pulled_back_messages 的 pair 处理方向对齐 Ruby
/// `get_recent_messages_with_tool_pairs` —— kept 中的 tool_result 缺父时
/// 把父 assistant 回填（而非删除 tool_result）。
///
/// 场景：max_tokens 极小，弹窗把 parent assistant 弹出，但 tool_result
/// 留在 kept。期望：父 assistant 被回填到 kept；tool_result 保留。
test "pulled_back_messages_repairs_pair_by_re_pulling_parent" {
  // 构造 4 条消息：user + assistant(tool_calls) + tool_result + user(long)
  // max_tokens 故意设极小以触发弹窗，使 assistant 被弹出、tool_result 留下。
  let msgs : Array[@message.Message] = []
  msgs.push(@message.Message::user("msg1"))
  let asst = @message.Message::assistant("thinking...")
  asst.tool_calls = Some([@message.ToolCall::new("c1", "f1", "{}")])
  msgs.push(asst)
  msgs.push(@message.Message::tool_result("c1", "f1", "result1"))
  // 长 user 消息让总估算远超 budget
  let long_user = String::make(500, 'x')
  msgs.push(@message.Message::user(long_user))
  let (kept, pulled) = pulled_back_messages(msgs, 1) // 极小 budget → 弹到只剩 1 条
  // 因为 budget=1，弹到只剩 1 条；然后 pair repair 触发回填父 assistant。
  // 我们验证 kept 不含孤立 tool_result（每个 tool_result 都有父 in kept）。
  let kept_call_ids : Map[String, Bool] = Map([])
  for m in kept {
    if m.role == @message.Assistant {
      match m.tool_calls {
        Some(calls) =>
          for c in calls {
            kept_call_ids[c.id] = true
          }
        None => ()
      }
    }
  }
  // 验证 kept 中每个 tool_result 都有匹配的 parent call_id
  for m in kept {
    if m.role == @message.Tool {
      match m.tool_call_id {
        Some(id) =>
          match kept_call_ids.get(id) {
            Some(_) => ()
            None => fail("orphan tool_result in kept: call_id not answered")
          }
        None => ()
      }
    }
  }
  // pulled 应非空
  assert_true(pulled.length() > 0)
}

///|
/// BUG-0011 决策 3 验收：parent assistant 已在 kept 时不重复添加。
/// 即 budget 刚够保留所有消息时不触发回填逻辑。
test "pulled_back_messages_no_repair_when_budget_sufficient" {
  let msgs : Array[@message.Message] = [
    @message.Message::user("msg1"),
    {
      role: @message.Assistant,
      content: @message.Text("thinking"),
      tool_calls: Some([@message.ToolCall::new("c1", "f1", "{}")]),
      tool_call_id: None,
      name: None,
      reasoning_content: None,
      latency: None,
      display_text: None,
      display_files: None,
      task_id: None,
      created_at: None,
      system_injected: None,
      memory_update: None,
      subagent_instructions: None,
      subagent_result: None,
      token_usage: None,
      compressed_summary: None,
      transient: None,
      session_date: None,
      session_context: None,
    },
    @message.Message::tool_result("c1", "f1", "result1"),
    @message.Message::user("msg3"),
  ]
  let (kept, _pulled) = pulled_back_messages(msgs, 10_000)
  // budget 足够 → kept 应包含全部 4 条
  assert_eq(kept.length(), 4)
}
