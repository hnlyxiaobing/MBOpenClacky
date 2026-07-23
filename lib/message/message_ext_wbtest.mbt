///| Extended tests for message package: roles, tool calls, content blocks, message constructors, history operations.

// ── Role Tests ──────────────────────────────────────────────────────────────

///|
test "ext_role_to_string_all_variants" {
  assert_eq(Role::User.to_string_value(), "user")
  assert_eq(Role::Assistant.to_string_value(), "assistant")
  assert_eq(Role::System.to_string_value(), "system")
  assert_eq(Role::Tool.to_string_value(), "tool")
}

///|
test "ext_role_from_string_valid" {
  assert_true(Role::from_string("user") == Some(User))
  assert_true(Role::from_string("assistant") == Some(Assistant))
  assert_true(Role::from_string("system") == Some(System))
  assert_true(Role::from_string("tool") == Some(Tool))
}

///|
test "ext_role_from_string_invalid" {
  assert_true(Role::from_string("admin") is None)
  assert_true(Role::from_string("") is None)
  assert_true(Role::from_string("USER") is None)
}

///|
test "ext_role_equality_and_compare" {
  assert_true(User == User)
  assert_true(User != Assistant)
  assert_true(System != Tool)
}

// ── ToolCall & FunctionCall Tests ───────────────────────────────────────────

///|
test "ext_toolcall_new_defaults" {
  let tc = ToolCall::new("call-1", "search", "{\"q\":\"test\"}")
  assert_eq(tc.id, "call-1")
  assert_eq(tc.type_, "function")
  assert_eq(tc.function.name, "search")
  assert_eq(tc.function.arguments, "{\"q\":\"test\"}")
}

///|
test "ext_toolcall_equality" {
  let tc1 = ToolCall::new("c1", "fn", "{}")
  let tc2 = ToolCall::new("c1", "fn", "{}")
  let tc3 = ToolCall::new("c2", "fn", "{}")
  assert_true(tc1 == tc2)
  assert_true(tc1 != tc3)
}

// ── Message Constructor Tests ───────────────────────────────────────────────

///|
test "ext_message_user_fields" {
  let msg = Message::user("hello")
  assert_true(msg.role == User)
  assert_true(msg.content == MessageContent::Text("hello"))
  assert_true(msg.tool_calls is None)
  assert_true(msg.task_id is None)
}

///|
test "ext_message_assistant_fields" {
  let msg = Message::assistant("reply")
  assert_true(msg.role == Assistant)
  assert_true(msg.content == MessageContent::Text("reply"))
}

///|
test "ext_message_system_fields" {
  let msg = Message::system("be helpful")
  assert_true(msg.role == System)
  assert_true(msg.content == MessageContent::Text("be helpful"))
}

///|
test "ext_message_tool_result_fields" {
  let msg = Message::tool_result("tc-1", "search", "data")
  assert_true(msg.role == Tool)
  assert_eq(msg.tool_call_id, Some("tc-1"))
  assert_eq(msg.name, Some("search"))
}

///|
test "ext_message_to_api_strips_internal" {
  let msg : Message = {
    role: User,
    content: Text("test"),
    tool_calls: None,
    tool_call_id: None,
    name: None,
    task_id: Some("task-1"),
    created_at: Some("2026-01-01"),
    system_injected: Some(true),
    memory_update: None,
    subagent_instructions: Some("instr"),
    subagent_result: Some("res"),
    token_usage: None,
    compressed_summary: Some("sum"),
    transient: Some(true),
  }
  let api = msg.to_api_message()
  assert_true(api.task_id is None)
  assert_true(api.created_at is None)
  assert_true(api.system_injected is None)
  assert_true(api.subagent_instructions is None)
  assert_true(api.subagent_result is None)
  assert_true(api.compressed_summary is None)
  assert_true(api.transient is None)
  assert_true(api.role == User)
}

///|
test "ext_message_to_api_preserves_core_fields" {
  let tc = ToolCall::new("c1", "fn", "{}")
  let msg : Message = {
    role: Assistant,
    content: Text("calling"),
    tool_calls: Some([tc]),
    tool_call_id: None,
    name: Some("tool_name"),
    task_id: Some("t1"),
    created_at: None,
    system_injected: None,
    memory_update: None,
    subagent_instructions: None,
    subagent_result: None,
    token_usage: None,
    compressed_summary: None,
    transient: None,
  }
  let api = msg.to_api_message()
  assert_true(api.tool_calls is Some(_))
  assert_eq(api.name, Some("tool_name"))
  assert_true(api.role == Assistant)
}

// ── MessageHistory Extended Tests ────────────────────────────────────────────

///|
test "ext_history_delete_where" {
  let h = MessageHistory::new()
  h.append(Message::user("keep"))
  h.append(Message::assistant("remove"))
  h.append(Message::user("keep2"))
  h.delete_where(fn(msg) { msg.role == Assistant })
  assert_eq(h.size(), 2)
  assert_true(h.all()[0].role == User)
  assert_true(h.all()[1].role == User)
}

///|
test "ext_history_delete_where_no_match" {
  let h = MessageHistory::new()
  h.append(Message::user("a"))
  h.append(Message::user("b"))
  h.delete_where(fn(msg) { msg.role == System })
  assert_eq(h.size(), 2)
}

///|
test "ext_history_mutate_last_found" {
  let h = MessageHistory::new()
  h.append(Message::user("original"))
  let found = h.mutate_last_matching(fn(msg) { msg.role == User }, fn(_) {
    Message::user("mutated")
  })
  assert_true(found)
  assert_true(h.all()[0].content == MessageContent::Text("mutated"))
}

///|
test "ext_history_mutate_last_not_found" {
  let h = MessageHistory::new()
  h.append(Message::user("a"))
  let found = h.mutate_last_matching(fn(msg) { msg.role == System }, fn(msg) {
    msg
  })
  assert_false(found)
}

///|
test "ext_history_clear" {
  let h = MessageHistory::new()
  h.append(Message::user("a"))
  h.append(Message::assistant("b"))
  h.clear()
  assert_eq(h.size(), 0)
  assert_true(h.is_empty())
}

///|
test "ext_history_replace_all" {
  let h = MessageHistory::new()
  h.append(Message::user("old"))
  h.replace_all([Message::system("new1"), Message::user("new2")])
  assert_eq(h.size(), 2)
  assert_true(h.all()[0].role == System)
  assert_true(h.all()[1].role == User)
}

// ── ContentBlock & MessageContent Tests ─────────────────────────────────────

///|
test "ext_textblock_construction" {
  let tb : TextBlock = { text: "hello" }
  assert_eq(tb.text, "hello")
}

///|
test "ext_imageblock_with_detail" {
  let ib : ImageBlock = { url: "http://img.png", detail: Some("high") }
  assert_eq(ib.url, "http://img.png")
  assert_eq(ib.detail, Some("high"))
}

///|
test "ext_contentblock_text_to_json" {
  let cb = ContentBlock::Text({ text: "hi" })
  match ToJson::to_json(cb) {
    Object(obj) => {
      assert_eq(obj.get("type"), Some("text".to_json()))
      match obj.get("text") {
        Some(String(s)) => assert_eq(s, "hi")
        _ => assert_true(false)
      }
    }
    _ => assert_true(false)
  }
}

///|
test "ext_contentblock_image_to_json" {
  let cb = ContentBlock::Image({ url: "http://x.png", detail: None })
  match ToJson::to_json(cb) {
    Object(obj) => assert_eq(obj.get("type"), Some("image_url".to_json()))
    _ => assert_true(false)
  }
}

///|
test "ext_messagecontent_text_to_json" {
  let mc = MessageContent::Text("hello")
  match ToJson::to_json(mc) {
    String(s) => assert_eq(s, "hello")
    _ => assert_true(false)
  }
}

///|
test "ext_messagecontent_blocks_to_json" {
  let mc = MessageContent::Blocks([
    ContentBlock::Text({ text: "a" }),
    ContentBlock::Image({ url: "u", detail: None }),
  ])
  match ToJson::to_json(mc) {
    Array(arr) => assert_eq(arr.length(), 2)
    _ => assert_true(false)
  }
}

///|
test "ext_contentblock_equality" {
  let t1 = ContentBlock::Text({ text: "x" })
  let t2 = ContentBlock::Text({ text: "x" })
  let t3 = ContentBlock::Text({ text: "y" })
  assert_true(t1 == t2)
  assert_true(t1 != t3)
}

// ── More MessageHistory Tests ───────────────────────────────────────────────

///|
test "ext_history_truncate_from_created_at" {
  let h = MessageHistory::new()
  let m1 : Message = {
    role: User,
    content: Text("first"),
    tool_calls: None,
    tool_call_id: None,
    name: None,
    task_id: None,
    created_at: Some("ts1"),
    system_injected: None,
    memory_update: None,
    subagent_instructions: None,
    subagent_result: None,
    token_usage: None,
    compressed_summary: None,
    transient: None,
  }
  h.replace_all([m1, Message::assistant("reply")])
  h.truncate_from_created_at("ts1")
  assert_eq(h.size(), 0)
}

///|
test "ext_history_truncate_from_created_at_no_match" {
  let h = MessageHistory::new()
  let m1 : Message = {
    role: User,
    content: Text("first"),
    tool_calls: None,
    tool_call_id: None,
    name: None,
    task_id: None,
    created_at: Some("ts1"),
    system_injected: None,
    memory_update: None,
    subagent_instructions: None,
    subagent_result: None,
    token_usage: None,
    compressed_summary: None,
    transient: None,
  }
  h.replace_all([m1])
  h.truncate_from_created_at("nonexistent")
  assert_eq(h.size(), 1)
}

///|
test "ext_history_rollback_before" {
  let h = MessageHistory::new()
  let m1 : Message = {
    role: User,
    content: Text("first"),
    tool_calls: None,
    tool_call_id: None,
    name: None,
    task_id: Some("tid1"),
    created_at: None,
    system_injected: None,
    memory_update: None,
    subagent_instructions: None,
    subagent_result: None,
    token_usage: None,
    compressed_summary: None,
    transient: None,
  }
  h.replace_all([m1, Message::assistant("reply")])
  h.rollback_before("tid1")
  assert_eq(h.size(), 0)
}

///|
test "ext_history_rollback_before_no_match" {
  let h = MessageHistory::new()
  h.append(Message::user("a"))
  h.rollback_before("nonexistent")
  assert_eq(h.size(), 1)
}

///|
test "ext_history_replace_system_prompt_insert_head" {
  let h = MessageHistory::new()
  h.append(Message::user("first"))
  h.replace_system_prompt("system prompt")
  assert_eq(h.size(), 2)
  assert_true(h.all()[0].role == System)
}

///|
test "ext_history_pop_last_empty" {
  let h = MessageHistory::new()
  assert_true(h.pop_last() is None)
}

///|
test "ext_history_all_returns_messages" {
  let h = MessageHistory::from_messages([
    Message::user("a"),
    Message::assistant("b"),
  ])
  let msgs = h.all()
  assert_eq(msgs.length(), 2)
}

///|
test "ext_history_estimate_tokens_multiple" {
  let h = MessageHistory::new()
  h.append(Message::user("hello"))
  h.append(Message::assistant("world"))
  let tokens = h.estimate_tokens()
  assert_true(tokens > 0)
}

// ── Additional MessageHistory Tests ─────────────────────────────────────────

///|
test "ext_history_append_then_to_api" {
  let h = MessageHistory::new()
  h.append(Message::system("system prompt"))
  h.append(Message::user("question"))
  h.append(Message::assistant("answer"))
  let api_msgs = h.to_api()
  assert_eq(api_msgs.length(), 3)
  for msg in api_msgs {
    assert_true(msg.task_id is None)
  }
}

///|
test "ext_history_append_user_drops_dangling" {
  let tc = ToolCall::new("c1", "search", "{}")
  let assistant_msg : Message = {
    role: Assistant,
    content: Text("searching"),
    tool_calls: Some([tc]),
    tool_call_id: None,
    name: None,
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
  let h = MessageHistory::from_messages([assistant_msg])
  assert_true(h.pending_tool_calls())
  h.append(Message::user("new question"))
  assert_eq(h.size(), 1)
  assert_false(h.pending_tool_calls())
}

///|
test "ext_history_delete_where_all" {
  let h = MessageHistory::from_messages([Message::user("a"), Message::user("b")])
  h.delete_where(fn(_) { true })
  assert_eq(h.size(), 0)
}

///|
test "ext_history_mutate_last_multiple_users" {
  let h = MessageHistory::from_messages([
    Message::user("first"),
    Message::user("second"),
    Message::user("third"),
  ])
  let found = h.mutate_last_matching(fn(msg) { msg.role == User }, fn(_) {
    Message::user("replaced")
  })
  assert_true(found)
  assert_eq(h.all()[2].content, MessageContent::Text("replaced"))
}

///|
test "ext_history_replace_all_empty_array" {
  let h = MessageHistory::from_messages([Message::user("a")])
  h.replace_all([])
  assert_eq(h.size(), 0)
}

///|
test "ext_history_truncate_from_zero" {
  let h = MessageHistory::from_messages([Message::user("a"), Message::user("b")])
  h.truncate_from(0)
  assert_eq(h.size(), 0)
}

///|
test "ext_history_pop_last_correct_message" {
  let h = MessageHistory::from_messages([
    Message::user("first"),
    Message::user("last"),
  ])
  match h.pop_last() {
    Some(msg) => assert_eq(msg.content, MessageContent::Text("last"))
    None => assert_true(false)
  }
  assert_eq(h.size(), 1)
}

///|
test "ext_history_pending_after_tool_result" {
  let tc = ToolCall::new("call-1", "search", "{}")
  let assistant_msg : Message = {
    role: Assistant,
    content: Text("searching"),
    tool_calls: Some([tc]),
    tool_call_id: None,
    name: None,
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
  let tool_result = Message::tool_result("call-1", "search", "found it")
  let h = MessageHistory::from_messages([assistant_msg, tool_result])
  assert_false(h.pending_tool_calls())
}

// ── JSON Serialization Tests ─────────────────────────────────────────────────

///|
test "ext_message_to_json_minimal" {
  let msg = Message::user("hello world")
  match ToJson::to_json(msg) {
    Object(obj) => {
      assert_eq(obj.get("role"), Some("user".to_json()))
      assert_eq(obj.get("content"), Some("hello world".to_json()))
    }
    _ => assert_true(false)
  }
}

///|
test "ext_message_to_json_with_tool_calls" {
  let tc = ToolCall::new("tc-1", "search", "{\"q\":\"test\"}")
  let msg : Message = {
    role: Assistant,
    content: Text("searching"),
    tool_calls: Some([tc]),
    tool_call_id: None,
    name: None,
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
  match ToJson::to_json(msg) {
    Object(obj) => assert_true(obj.get("tool_calls") is Some(_))
    _ => assert_true(false)
  }
}

///|
test "ext_toolcall_to_json_structure" {
  let tc = ToolCall::new("id-1", "func_name", "{\"arg\":1}")
  match ToJson::to_json(tc) {
    Object(obj) => {
      assert_eq(obj.get("id"), Some("id-1".to_json()))
      assert_eq(obj.get("type_"), Some("function".to_json()))
      match obj.get("function") {
        Some(Object(fn_obj)) => {
          assert_eq(fn_obj.get("name"), Some("func_name".to_json()))
          assert_eq(fn_obj.get("arguments"), Some("{\"arg\":1}".to_json()))
        }
        _ => assert_true(false)
      }
    }
    _ => assert_true(false)
  }
}

///|
test "ext_role_to_json_all_variants" {
  assert_true(ToJson::to_json(User) == "user".to_json())
  assert_true(ToJson::to_json(Assistant) == "assistant".to_json())
  assert_true(ToJson::to_json(System) == "system".to_json())
  assert_true(ToJson::to_json(Tool) == "tool".to_json())
}

///|
test "ext_functioncall_equality" {
  let f1 : FunctionCall = { name: "search", arguments: "{}" }
  let f2 : FunctionCall = { name: "search", arguments: "{}" }
  let f3 : FunctionCall = { name: "other", arguments: "{}" }
  assert_true(f1 == f2)
  assert_true(f1 != f3)
}

///|
test "ext_imageblock_equality" {
  let ib1 : ImageBlock = { url: "http://x.png", detail: Some("high") }
  let ib2 : ImageBlock = { url: "http://x.png", detail: Some("high") }
  let ib3 : ImageBlock = { url: "http://y.png", detail: None }
  assert_true(ib1 == ib2)
  assert_true(ib1 != ib3)
}
