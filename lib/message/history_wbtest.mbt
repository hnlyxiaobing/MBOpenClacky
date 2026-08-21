///|
/// White-box tests for MessageHistory.
test "MessageHistory new and empty" {
  let h = MessageHistory::new()
  @debug.debug_inspect(h.is_empty(), content="true")
  @debug.debug_inspect(h.size(), content="0")
}

///|
test "MessageHistory append and size" {
  let h = MessageHistory::new()
  h.append(Message::user("hello"))
  @debug.debug_inspect(h.size(), content="1")
  @debug.debug_inspect(h.is_empty(), content="false")
  h.append(Message::assistant("hi"))
  @debug.debug_inspect(h.size(), content="2")
}

///|
test "MessageHistory to_api strips internal fields" {
  let msg : Message = {
    role: User,
    content: Text("test"),
    tool_calls: None,
    tool_call_id: None,
    name: None,
    reasoning_content: None,
    latency: None,
    display_text: None,
    display_files: None,
    task_id: Some("task-123"),
    created_at: Some("2026-01-01"),
    system_injected: Some(true),
    memory_update: None,
    subagent_instructions: Some("do stuff"),
    subagent_result: Some("done"),
    token_usage: None,
    compressed_summary: Some("summary"),
    transient: Some(true),
    session_date: None,
    session_context: None,
  }
  let h = MessageHistory::from_messages([msg])
  let api_msgs = h.to_api()
  let api_msg = api_msgs[0]
  // Core fields preserved
  @debug.debug_inspect(api_msg.role == User, content="true")
  // Internal fields stripped
  @debug.debug_inspect(api_msg.task_id, content="None")
  @debug.debug_inspect(api_msg.created_at, content="None")
  @debug.debug_inspect(api_msg.system_injected, content="None")
  @debug.debug_inspect(api_msg.subagent_instructions, content="None")
  @debug.debug_inspect(api_msg.subagent_result, content="None")
  @debug.debug_inspect(api_msg.compressed_summary, content="None")
  @debug.debug_inspect(api_msg.transient, content="None")
}

///|
test "MessageHistory real_user_messages" {
  let h = MessageHistory::new()
  // Normal user message
  h.append(Message::user("real msg"))
  // System-injected user message
  let injected : Message = {
    role: User,
    content: Text("injected"),
    tool_calls: None,
    tool_call_id: None,
    name: None,
    reasoning_content: None,
    latency: None,
    display_text: None,
    display_files: None,
    task_id: None,
    created_at: None,
    system_injected: Some(true),
    memory_update: None,
    subagent_instructions: None,
    subagent_result: None,
    token_usage: None,
    compressed_summary: None,
    transient: None,
    session_date: None,
    session_context: None,
  }
  h.append(injected)
  // Another real user message
  h.append(Message::user("another real"))
  let real = h.real_user_messages()
  @debug.debug_inspect(real.length(), content="2")
}

///|
test "MessageHistory pending_tool_calls" {
  let h = MessageHistory::new()
  // No messages - no pending
  @debug.debug_inspect(h.pending_tool_calls(), content="false")
  // Add assistant without tool_calls
  h.append(Message::assistant("no tools"))
  @debug.debug_inspect(h.pending_tool_calls(), content="false")
  // Add assistant with tool_calls
  let tc = ToolCall::new("call-1", "search", "{}")
  let assistant_with_tools : Message = {
    role: Assistant,
    content: Text("let me search"),
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
  }
  let h2 = MessageHistory::from_messages([assistant_with_tools])
  @debug.debug_inspect(h2.pending_tool_calls(), content="true")
  // After adding tool result, no longer pending
  h2.append(Message::tool_result("call-1", "search", "result"))
  @debug.debug_inspect(h2.pending_tool_calls(), content="false")
}

///|
test "MessageHistory estimate_tokens" {
  let h = MessageHistory::new()
  // A short message: "hello" = 5 chars => 5/4 rounded up = 2 + 4 overhead = 6
  h.append(Message::user("hello"))
  let tokens = h.estimate_tokens()
  // 4 overhead + ceil(5/4)=2 = 6
  @debug.debug_inspect(tokens, content="6")
}

///|
test "MessageHistory last_real_user_index" {
  let h = MessageHistory::new()
  // Empty history
  @debug.debug_inspect(h.last_real_user_index(), content="None")
  h.append(Message::system("sys"))
  h.append(Message::user("first"))
  h.append(Message::assistant("reply"))
  h.append(Message::user("second"))
  @debug.debug_inspect(h.last_real_user_index(), content="Some(3)")
}

///|
test "MessageHistory drop_dangling_tool_calls" {
  let tc = ToolCall::new("call-x", "run", "{}")
  let assistant_msg : Message = {
    role: Assistant,
    content: Text("calling tool"),
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
  }
  let h = MessageHistory::from_messages([Message::user("hi"), assistant_msg])
  @debug.debug_inspect(h.size(), content="2")
  // Appending a user message should drop the dangling assistant
  h.append(Message::user("new question"))
  // Dangling assistant removed, user added => size = 2
  @debug.debug_inspect(h.size(), content="2")
}

///|
test "MessageHistory pop_last" {
  let h = MessageHistory::new()
  @debug.debug_inspect(h.pop_last() is None, content="true")
  h.append(Message::user("one"))
  h.append(Message::user("two"))
  let popped = h.pop_last()
  @debug.debug_inspect(popped is Some(_), content="true")
  @debug.debug_inspect(h.size(), content="1")
}

///|
test "MessageHistory truncate_from" {
  let h = MessageHistory::new()
  h.append(Message::user("a"))
  h.append(Message::assistant("b"))
  h.append(Message::user("c"))
  h.append(Message::assistant("d"))
  h.truncate_from(2)
  @debug.debug_inspect(h.size(), content="2")
}

///|
test "MessageHistory replace_system_prompt" {
  let h = MessageHistory::new()
  h.append(Message::system("old prompt"))
  h.append(Message::user("hi"))
  h.replace_system_prompt("new prompt")
  @debug.debug_inspect(h.size(), content="2")
  let msgs = h.all()
  let is_new_prompt = msgs[0].content == MessageContent::Text("new prompt")
  @debug.debug_inspect(is_new_prompt, content="true")
}

///|
test "MessageHistory from_messages" {
  let msgs = [Message::user("a"), Message::assistant("b")]
  let h = MessageHistory::from_messages(msgs)
  @debug.debug_inspect(h.size(), content="2")
  @debug.debug_inspect(h.is_empty(), content="false")
}

///|
test "MessageHistory repair_dangling_tool_calls inserts interrupted placeholder" {
  let tc1 = ToolCall::new("call-1", "search", "{}")
  let tc2 = ToolCall::new("call-2", "read", "{}")
  let assistant_msg : Message = {
    role: Assistant,
    content: Text("calling tools"),
    tool_calls: Some([tc1, tc2]),
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
  }
  // call-1 answered, call-2 dangling
  let h = MessageHistory::from_messages([
    Message::user("hi"),
    assistant_msg,
    Message::tool_result("call-1", "search", "result"),
  ])
  h.repair_dangling_tool_calls()
  let msgs = h.all()
  // user + assistant + placeholder(call-2) + tool_result(call-1)
  @debug.debug_inspect(msgs.length(), content="4")
  let placeholder = msgs[2]
  @debug.debug_inspect(placeholder.role == Tool, content="true")
  @debug.debug_inspect(placeholder.tool_call_id, content="Some(\"call-2\")")
  match placeholder.content {
    Text(s) => @debug.debug_inspect(s, content="\"(interrupted)\"")
    _ => @debug.debug_inspect("wrong", content="\"(interrupted)\"")
  }
  // The answered call-1 result stays in place
  @debug.debug_inspect(msgs[3].tool_call_id, content="Some(\"call-1\")")
  // No dangling calls remain
  @debug.debug_inspect(h.pending_tool_calls(), content="false")
}

///|
test "MessageHistory pad_missing_reasoning only in thinking mode" {
  let h = MessageHistory::new()
  h.append(Message::assistant("plain answer"))
  // Non-thinking mode: no padding
  h.pad_missing_reasoning(false)
  @debug.debug_inspect(h.all()[0].reasoning_content, content="None")
  // Thinking mode: assistant without reasoning gets empty placeholder
  h.pad_missing_reasoning(true)
  @debug.debug_inspect(h.all()[0].reasoning_content, content="Some(\"\")")
}

///|
test "MessageHistory to_api_cleaned filters transient and repairs pairing" {
  let tc = ToolCall::new("call-x", "run", "{}")
  let assistant_msg : Message = {
    role: Assistant,
    content: Text("calling"),
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
  }
  let transient_msg : Message = {
    role: User,
    content: Text("transient"),
    tool_calls: None,
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
    transient: Some(true),
    session_date: None,
    session_context: None,
  }
  let h = MessageHistory::from_messages([
    Message::user("hi"),
    assistant_msg,
    transient_msg,
  ])
  let api = h.to_api_cleaned(true)
  // user + assistant + interrupted placeholder; transient filtered
  @debug.debug_inspect(api.length(), content="3")
  // Stored history untouched
  @debug.debug_inspect(h.size(), content="3")
  // Placeholder present in cleaned output
  let last = api[2]
  @debug.debug_inspect(last.role == Tool, content="true")
  @debug.debug_inspect(last.tool_call_id, content="Some(\"call-x\")")
  // Tool message name stripped on the wire
  @debug.debug_inspect(last.name, content="None")
}

///|
test "MessageHistory to_api strips tool message name" {
  let h = MessageHistory::new()
  h.append(Message::tool_result("c1", "search", "ok"))
  let api = h.to_api()
  @debug.debug_inspect(api[0].name, content="None")
}

///|
/// last_session_context_date: newest session-context message wins.
test "MessageHistory last_session_context_date newest" {
  let older : Message = {
    role: User,
    content: Text("old ctx"),
    tool_calls: None,
    tool_call_id: None,
    name: None,
    reasoning_content: None,
    latency: None,
    display_text: None,
    display_files: None,
    session_date: Some("2026-08-20"),
    session_context: Some(true),
    task_id: None,
    created_at: None,
    system_injected: Some(true),
    memory_update: None,
    subagent_instructions: None,
    subagent_result: None,
    token_usage: None,
    compressed_summary: None,
    transient: None,
  }
  let newer : Message = {
    role: User,
    content: Text("new ctx"),
    tool_calls: None,
    tool_call_id: None,
    name: None,
    reasoning_content: None,
    latency: None,
    display_text: None,
    display_files: None,
    session_date: Some("2026-08-21"),
    session_context: Some(true),
    task_id: None,
    created_at: None,
    system_injected: Some(true),
    memory_update: None,
    subagent_instructions: None,
    subagent_result: None,
    token_usage: None,
    compressed_summary: None,
    transient: None,
  }
  let plain = Message::user("hi")
  let h = MessageHistory::from_messages([plain, older, plain, newer])
  @debug.assert_eq(h.last_session_context_date(), Some("2026-08-21"))
}

///|
/// last_session_context_date: no session-context message → None.
test "MessageHistory last_session_context_date none" {
  let h = MessageHistory::from_messages([Message::user("a"), Message::user("b")])
  @debug.assert_eq(h.last_session_context_date(), None)
}

///|
/// last_session_context_date: session_context=false does not count.
test "MessageHistory last_session_context_date false ignored" {
  let m : Message = {
    role: User,
    content: Text("ctx"),
    tool_calls: None,
    tool_call_id: None,
    name: None,
    reasoning_content: None,
    latency: None,
    display_text: None,
    display_files: None,
    session_date: Some("2026-08-21"),
    session_context: Some(false),
    task_id: None,
    created_at: None,
    system_injected: Some(true),
    memory_update: None,
    subagent_instructions: None,
    subagent_result: None,
    token_usage: None,
    compressed_summary: None,
    transient: None,
  }
  let h = MessageHistory::from_messages([Message::user("a"), m])
  @debug.assert_eq(h.last_session_context_date(), None)
}
