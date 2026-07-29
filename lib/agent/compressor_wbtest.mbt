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
      task_id: None,
      created_at: None,
      system_injected: None,
      memory_update: None,
      subagent_instructions: None,
      subagent_result: None,
      token_usage: None,
      compressed_summary: None,
      transient: None,
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
  let buf = StringBuilder::new()
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
    "key", "https://api.test.com", "model", @config.OpenAICompletions,
  )
  let config = @config.AgentConfig::default()
  let agent = Agent::new("s", "a", "/tmp", client, config)
  agent.config.compression_threshold = 5
  agent.history.push(@message.Message::user("Hello world, this is a test message"))
  assert_true(agent.needs_compression())
  agent.config.compression_threshold = 999_999
  assert_false(agent.needs_compression())
}
