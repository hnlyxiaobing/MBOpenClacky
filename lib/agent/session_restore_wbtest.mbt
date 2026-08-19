///| Tests for enhanced session serialization and restoration.

// ── Timestamp & Option-field serialization fixes (web-ui fix-03) ─────────────

///|
/// Minimal valid SessionData JSON with configurable created_at and
/// optional extra fields.
fn fix03_session_json(created_at : String, extra : String) -> Json raise {
  let src =
    #| {
    #|   "session_id": "s_fix03",
    #|   "name": "fix03-session",
    #|   "messages": [],
    #|   "stats": {
    #|     "total_iterations": 0,
    #|     "total_cost_usd": 0.0,
    #|     "total_tasks": 0,
    #|     "cost_source": "estimated"
    #|   },
    #|   "working_dir": ".",
    #|   "created_at": CREATED_AT
    #|   EXTRA
    #| }
  @json.parse(
    src
    .replace(old="CREATED_AT", new=created_at)
    .replace(old="EXTRA", new=extra),
  )
}

///|
test "current_time_ms is unix epoch magnitude" {
  let now = current_time_ms()
  // Unix epoch ms: 2023-11 .. 2033-11. A 1601-based value would be ~1.3e13.
  assert_true(now > 1700000000000L)
  assert_true(now < 2000000000000L)
}

///|
test "created_at normalization keeps ISO strings" {
  let parsed : SessionData = @json.from_json(
    fix03_session_json("\"2026-07-24T12:22:34+08:00\"", ""),
  )
  @debug.assert_eq(parsed.created_at, "2026-07-24T12:22:34+08:00")
}

///|
test "created_at normalization converts unix epoch ms" {
  let parsed : SessionData = @json.from_json(
    fix03_session_json("\"1784880000000\"", ""),
  )
  let ts = parsed.created_at
  assert_true(ts.length() == 25)
  assert_true(ts[10] == 'T')
  @debug.assert_eq(ts, ms_to_iso8601(1784880000000L))
}

///|
test "created_at normalization converts windows-epoch ms" {
  // 1601-based dirty value = unix ms + 11644473600000 (> 1e13 threshold).
  let parsed : SessionData = @json.from_json(
    fix03_session_json("\"13429353600000\"", ""),
  )
  @debug.assert_eq(parsed.created_at, ms_to_iso8601(1784880000000L))
}

///|
test "model_name parses both plain string and legacy array form" {
  let plain : SessionData = @json.from_json(
    fix03_session_json(
      "\"2026-07-24T12:22:34+08:00\"", ", \"model_name\": \"kimi-k2\"",
    ),
  )
  @debug.assert_eq(plain.model_name, Some("kimi-k2"))
  let legacy : SessionData = @json.from_json(
    fix03_session_json(
      "\"2026-07-24T12:22:34+08:00\"", ", \"model_name\": [\"kimi-k2\"]",
    ),
  )
  @debug.assert_eq(legacy.model_name, Some("kimi-k2"))
}

///|
test "model_config_id absent in legacy files parses to None" {
  // Legacy session files predate the field; loading must not fail.
  let legacy : SessionData = @json.from_json(
    fix03_session_json("\"2026-07-24T12:22:34+08:00\"", ""),
  )
  @debug.assert_eq(legacy.model_config_id, None)
  let with_id : SessionData = @json.from_json(
    fix03_session_json(
      "\"2026-07-24T12:22:34+08:00\"", ", \"model_config_id\": \"s_1784773902\"",
    ),
  )
  @debug.assert_eq(with_id.model_config_id, Some("s_1784773902"))
  // Roundtrip: the id survives to_json -> from_json.
  let reparsed : SessionData = @json.from_json(ToJson::to_json(with_id))
  @debug.assert_eq(reparsed.model_config_id, Some("s_1784773902"))
}

///|
test "reasoning_effort and sub_model parse legacy array form" {
  let parsed : SessionData = @json.from_json(
    fix03_session_json(
      "\"2026-07-24T12:22:34+08:00\"", ", \"reasoning_effort\": [\"high\"], \"sub_model\": [\"sub-m\"]",
    ),
  )
  @debug.assert_eq(parsed.reasoning_effort, Some("high"))
  @debug.assert_eq(parsed.sub_model, Some("sub-m"))
}

///|
test "option string fields serialize as plain string or null" {
  let data : SessionData = @json.from_json(
    fix03_session_json(
      "\"2026-07-24T12:22:34+08:00\"", ", \"model_name\": [\"kimi-k2\"]",
    ),
  )
  match ToJson::to_json(data) {
    Object(map) => {
      @debug.assert_eq(map.get("model_name"), Some("kimi-k2".to_json()))
      @debug.assert_eq(map.get("sub_model"), Some(Json::null()))
      @debug.assert_eq(map.get("reasoning_effort"), Some(Json::null()))
    }
    _ => panic()
  }
}

///|
test "ChannelInfo serialization roundtrip" {
  let ci : ChannelInfo = {
    platform: "feishu",
    channel_id: "ch-001",
    user_id: "u-abc",
    webhook_url: "https://hook.example.com/cb",
  }
  let json = ToJson::to_json(ci)
  let parsed : ChannelInfo = @json.from_json(json)
  @debug.assert_eq(parsed, ci)
}

///|
test "SessionTaskMeta serialization roundtrip" {
  let meta : SessionTaskMeta = {
    title: "Fix login bug",
    started_at: "1719100000000",
    ended_at: "1719103600000",
  }
  let json = ToJson::to_json(meta)
  let parsed : SessionTaskMeta = @json.from_json(json)
  @debug.assert_eq(parsed, meta)
}

///|
test "SessionTimeMachine serialization roundtrip" {
  let parents : Map[String, String] = Map([])
  parents["2"] = "1"
  parents["3"] = "2"
  let meta_map : Map[String, SessionTaskMeta] = Map([])
  meta_map["1"] = {
    title: "Initial task",
    started_at: "1719100000000",
    ended_at: "1719101000000",
  }
  meta_map["2"] = {
    title: "Sub task",
    started_at: "1719101000000",
    ended_at: "",
  }
  let tm : SessionTimeMachine = {
    task_parents: parents,
    task_meta: meta_map,
    current_task_id: 3,
    active_task_id: 2,
  }
  let json = ToJson::to_json(tm)
  let parsed : SessionTimeMachine = @json.from_json(json)
  @debug.assert_eq(parsed.current_task_id, 3)
  @debug.assert_eq(parsed.active_task_id, 2)
  @debug.assert_eq(parsed.task_parents.get("2"), Some("1"))
  @debug.assert_eq(parsed.task_parents.get("3"), Some("2"))
  @debug.assert_eq(parsed.task_meta.get("1").unwrap().title, "Initial task")
}

///|
test "SessionData with new fields serialization" {
  let data : SessionData = {
    session_id: "s_123",
    name: "test-session",
    messages: [],
    stats: {
      total_iterations: 5,
      total_cost_usd: 0.05,
      total_tasks: 2,
      cost_source: "estimated",
      cache_creation_input_tokens: 0,
      cache_read_input_tokens: 0,
      total_requests: 5,
      cache_hit_requests: 0,
    },
    working_dir: "/tmp/work",
    created_at: "1719100000000",
    source: "manual",
    reasoning_effort: None,
    model_name: Some("gpt-4"),
    model_config_id: None,
    channel_info: Some({
      platform: "telegram",
      channel_id: "tg-123",
      user_id: "user-7",
      webhook_url: "",
    }),
    latest_latency_ms: Some(350),
    latest_ttft_ms: Some(80),
    time_machine: None,
    pending_error_rollback: false,
    model_base_url: "https://api.openai.com",
    last_status: "idle",
    last_error: "",
    error_code: None,
    top_up_url: None,
    raw_message: None,
    forked_from: None,
    chunk_count: 0,
    agent_profile: "general",
    sub_model: None,
    pinned: false,
    todos: None,
    updated_at: "1719000000000",
    previous_total_tokens: 0,
    deleted_at: None,
  }
  let json = ToJson::to_json(data)
  let parsed : SessionData = @json.from_json(json)
  @debug.assert_eq(parsed.session_id, "s_123")
  @debug.assert_eq(parsed.channel_info.unwrap().platform, "telegram")
  @debug.assert_eq(parsed.latest_latency_ms, Some(350))
  @debug.assert_eq(parsed.latest_ttft_ms, Some(80))
  @debug.assert_eq(parsed.pending_error_rollback, false)
  @debug.assert_eq(parsed.model_base_url, "https://api.openai.com")
  @debug.assert_eq(parsed.last_status, "idle")
  @debug.assert_eq(parsed.last_error, "")
}

///|
test "SessionData backward compatibility (missing new fields)" {
  // Simulate old JSON without the new fields
  let old_json =
    #| {
    #|   "session_id": "s_old",
    #|   "name": "old-session",
    #|   "messages": [],
    #|   "stats": {
    #|     "total_iterations": 1,
    #|     "total_cost_usd": 0.01,
    #|     "total_tasks": 1,
    #|     "cost_source": "api"
    #|   },
    #|   "working_dir": "/home/user",
    #|   "created_at": "1700000000000",
    #|   "source": "manual"
    #| }
  let json = @json.parse(old_json)
  let parsed : SessionData = @json.from_json(json)
  @debug.assert_eq(parsed.session_id, "s_old")
  @debug.assert_eq(parsed.channel_info, None)
  @debug.assert_eq(parsed.latest_latency_ms, None)
  @debug.assert_eq(parsed.latest_ttft_ms, None)
  @debug.assert_eq(parsed.time_machine, None)
  @debug.assert_eq(parsed.pending_error_rollback, false)
  @debug.assert_eq(parsed.model_base_url, "")
  @debug.assert_eq(parsed.last_status, "")
  @debug.assert_eq(parsed.last_error, "")
}

///|
test "restore_session_enhanced basic" {
  let config = @config.AgentConfig::default()
  let data : SessionData = {
    session_id: "s_basic",
    name: "basic-test",
    messages: [@message.Message::user("hello")],
    stats: {
      total_iterations: 3,
      total_cost_usd: 0.02,
      total_tasks: 1,
      cost_source: "estimated",
      cache_creation_input_tokens: 0,
      cache_read_input_tokens: 0,
      total_requests: 3,
      cache_hit_requests: 0,
    },
    working_dir: "/tmp",
    created_at: "1719000000000",
    source: "manual",
    reasoning_effort: None,
    model_name: None,
    model_config_id: None,
    channel_info: None,
    latest_latency_ms: None,
    latest_ttft_ms: None,
    time_machine: None,
    pending_error_rollback: false,
    model_base_url: "",
    last_status: "idle",
    last_error: "",
    error_code: None,
    top_up_url: None,
    raw_message: None,
    forked_from: None,
    chunk_count: 0,
    agent_profile: "general",
    sub_model: None,
    pinned: false,
    todos: None,
    updated_at: "1719000000000",
    previous_total_tokens: 0,
    deleted_at: None,
  }
  let result = restore_session_enhanced(config, data)
  @debug.assert_eq(result.session_id, "s_basic")
  @debug.assert_eq(result.name, "basic-test")
  @debug.assert_eq(result.messages.length(), 1)
  @debug.assert_eq(result.total_cost, 0.02)
  @debug.assert_eq(result.needs_error_rollback, false)
  @debug.assert_eq(result.model_recovered, false)
}

///|
test "restore_session_enhanced with channel_info" {
  let config = @config.AgentConfig::default()
  let ci : ChannelInfo = {
    platform: "discord",
    channel_id: "dc-999",
    user_id: "user-42",
    webhook_url: "https://discord.com/webhook/abc",
  }
  let data : SessionData = {
    session_id: "s_chan",
    name: "channel-test",
    messages: [],
    stats: {
      total_iterations: 0,
      total_cost_usd: 0.0,
      total_tasks: 0,
      cost_source: "estimated",
      cache_creation_input_tokens: 0,
      cache_read_input_tokens: 0,
      total_requests: 0,
      cache_hit_requests: 0,
    },
    working_dir: "/tmp",
    created_at: "1719000000000",
    source: "channel",
    reasoning_effort: None,
    model_name: None,
    model_config_id: None,
    channel_info: Some(ci),
    latest_latency_ms: Some(200),
    latest_ttft_ms: Some(40),
    time_machine: None,
    pending_error_rollback: false,
    model_base_url: "",
    last_status: "idle",
    last_error: "",
    error_code: None,
    top_up_url: None,
    raw_message: None,
    forked_from: None,
    chunk_count: 0,
    agent_profile: "general",
    sub_model: None,
    pinned: false,
    todos: None,
    updated_at: "1719000000000",
    previous_total_tokens: 0,
    deleted_at: None,
  }
  let result = restore_session_enhanced(config, data)
  @debug.assert_eq(result.channel_info.unwrap().platform, "discord")
  @debug.assert_eq(result.channel_info.unwrap().channel_id, "dc-999")
  @debug.assert_eq(result.latest_latency_ms, Some(200))
  @debug.assert_eq(result.latest_ttft_ms, Some(40))
}

///|
test "restore_session_enhanced error rollback detection" {
  let config = @config.AgentConfig::default()
  let data : SessionData = {
    session_id: "s_err",
    name: "error-test",
    messages: [],
    stats: {
      total_iterations: 1,
      total_cost_usd: 0.0,
      total_tasks: 0,
      cost_source: "estimated",
      cache_creation_input_tokens: 0,
      cache_read_input_tokens: 0,
      total_requests: 0,
      cache_hit_requests: 0,
    },
    working_dir: "/tmp",
    created_at: "1719000000000",
    source: "manual",
    reasoning_effort: None,
    model_name: None,
    model_config_id: None,
    channel_info: None,
    latest_latency_ms: None,
    latest_ttft_ms: None,
    time_machine: None,
    pending_error_rollback: false,
    model_base_url: "",
    last_status: "error",
    last_error: "Connection timeout",
    error_code: None,
    top_up_url: None,
    raw_message: None,
    forked_from: None,
    chunk_count: 0,
    agent_profile: "general",
    sub_model: None,
    pinned: false,
    todos: None,
    updated_at: "1719000000000",
    previous_total_tokens: 0,
    deleted_at: None,
  }
  let result = restore_session_enhanced(config, data)
  @debug.assert_eq(result.needs_error_rollback, true)
}

///|
test "apply_error_rollback" {
  let msgs : Array[@message.Message] = [
    @message.Message::user("first question"),
    @message.Message::assistant("first answer"),
    @message.Message::user("second question"),
    @message.Message::assistant("second answer (error happened after)"),
  ]
  let result = apply_error_rollback(msgs)
  // Should keep up to and including the last real user message
  @debug.assert_eq(result.length(), 3)
  // Verify the last message is "second question"
  let last = result[result.length() - 1]
  assert_true(last.role == @message.User)
}

///|
test "apply_error_rollback no user messages" {
  let msgs : Array[@message.Message] = [
    @message.Message::assistant("orphan assistant msg"),
  ]
  let result = apply_error_rollback(msgs)
  // Should return as-is since no user message found
  @debug.assert_eq(result.length(), 1)
}

///|
test "backfill_task_meta_from_history" {
  let msg1 : @message.Message = {
    role: @message.User,
    content: @message.Text("Start task one"),
    tool_calls: None,
    tool_call_id: None,
    name: None,
    reasoning_content: None,
    task_id: Some("1"),
    created_at: Some("1719100000000"),
    system_injected: None,
    memory_update: None,
    subagent_instructions: None,
    subagent_result: None,
    token_usage: None,
    compressed_summary: None,
    transient: None,
  }
  let msg2 : @message.Message = {
    role: @message.Assistant,
    content: @message.Text("Working on it"),
    tool_calls: None,
    tool_call_id: None,
    name: None,
    reasoning_content: None,
    task_id: Some("1"),
    created_at: Some("1719100001000"),
    system_injected: None,
    memory_update: None,
    subagent_instructions: None,
    subagent_result: None,
    token_usage: None,
    compressed_summary: None,
    transient: None,
  }
  let msg3 : @message.Message = {
    role: @message.User,
    content: @message.Text("Now do task two"),
    tool_calls: None,
    tool_call_id: None,
    name: None,
    reasoning_content: None,
    task_id: Some("2"),
    created_at: Some("1719100002000"),
    system_injected: None,
    memory_update: None,
    subagent_instructions: None,
    subagent_result: None,
    token_usage: None,
    compressed_summary: None,
    transient: None,
  }
  let messages = [msg1, msg2, msg3]
  let result = backfill_task_meta_from_history(messages, None)
  // Task "1" should have meta with title from first user message
  let meta1 = result.task_meta.get("1").unwrap()
  @debug.assert_eq(meta1.title, "Start task one")
  @debug.assert_eq(meta1.started_at, "1719100000000")
  @debug.assert_eq(meta1.ended_at, "1719100001000")
  // Task "2" should be a child of task "1"
  @debug.assert_eq(result.task_parents.get("2"), Some("1"))
  // Task "2" metadata
  let meta2 = result.task_meta.get("2").unwrap()
  @debug.assert_eq(meta2.title, "Now do task two")
}

// ── Agent::restore_from_session integration (decision 6 wiring) ─────────────

///|
fn make_restore_agent() -> Agent {
  let client = @client.Client::new(
    "test-key",
    "https://api.test.com",
    "current-model",
    @config.OpenAICompletions,
  )
  let config = @config.AgentConfig::default()
  Agent::new("test-session", "test-agent", "/tmp/test", client, config)
}

///|
fn restore_test_session(messages : Array[@message.Message]) -> SessionData {
  {
    session_id: "s_restore",
    name: "restore-test",
    messages,
    stats: {
      total_iterations: 4,
      total_cost_usd: 0.03,
      total_tasks: 2,
      cost_source: "estimated",
      cache_creation_input_tokens: 0,
      cache_read_input_tokens: 0,
      total_requests: 4,
      cache_hit_requests: 0,
    },
    working_dir: "/tmp",
    created_at: "1719000000000",
    source: "manual",
    reasoning_effort: None,
    model_name: Some("archived-model"),
    model_config_id: None,
    channel_info: None,
    latest_latency_ms: None,
    latest_ttft_ms: None,
    time_machine: None,
    pending_error_rollback: false,
    model_base_url: "https://api.test.com",
    last_status: "idle",
    last_error: "",
    error_code: None,
    top_up_url: None,
    raw_message: None,
    forked_from: None,
    chunk_count: 0,
    agent_profile: "general",
    sub_model: None,
    pinned: false,
    todos: None,
    updated_at: "1719000000000",
    previous_total_tokens: 0,
    deleted_at: None,
  }
}

///|
/// The token baseline must survive restore; a zeroed baseline would make
/// compression misfire immediately after resuming (decision 6).
test "restore_from_session keeps previous_total_tokens baseline" {
  let agent = make_restore_agent()
  let data = { ..restore_test_session([]), previous_total_tokens: 5000 }
  agent.restore_from_session(data)
  @debug.assert_eq(agent.previous_total_tokens, 5000)
}

///|
/// A session saved in an error state is rolled back past the failed run:
/// history truncates to the last real user message (apply_error_rollback
/// wired into the production restore path).
test "restore_from_session rolls back history after error state" {
  let agent = make_restore_agent()
  let msgs = [
    @message.Message::user("question"),
    @message.Message::assistant("partial answer before crash"),
  ]
  let data = { ..restore_test_session(msgs), last_status: "error" }
  agent.restore_from_session(data)
  // Rollback keeps only the last real user message; the refreshed system
  // prompt is re-inserted at the head.
  let all = agent.history.all()
  @debug.assert_eq(all.length(), 2)
  @debug.assert_eq(all[0].role, @message.System)
  @debug.assert_eq(all[1].role, @message.User)
  match all[1].content {
    @message.Text(s) => @debug.assert_eq(s, "question")
    @message.Blocks(_) => panic()
  }
}

///|
/// The archived system prompt may reference stale models, skills, or rules;
/// restore must rebuild it from the current agent state (decision 6).
test "restore_from_session refreshes system prompt to current version" {
  let agent = make_restore_agent()
  let msgs = [
    @message.Message::system("stale archived prompt"),
    @message.Message::user("hi"),
  ]
  let data = restore_test_session(msgs)
  agent.restore_from_session(data)
  let all = agent.history.all()
  @debug.assert_eq(all[0].role, @message.System)
  let sys_content = match all[0].content {
    @message.Text(s) => s
    @message.Blocks(_) => ""
  }
  assert_true(sys_content.contains("current-model"))
  assert_true(!sys_content.contains("stale archived"))
}

///|
/// When the archived model still exists in the current config, the client
/// is rebuilt on it instead of keeping the agent's default (Ruby
/// open_ai.rb:187-191 model recovery).
test "restore_from_session recovers archived model from config" {
  let client = @client.Client::new(
    "test-key",
    "https://api.test.com",
    "current-model",
    @config.OpenAICompletions,
  )
  let config = {
    ..@config.AgentConfig::default(),
    models: [
      @config.ModelConfig::new(
        "m1", "test-key", "https://api.test.com", "archived-model",
      ),
    ],
  }
  let agent = Agent::new(
    "test-session", "test-agent", "/tmp/test", client, config,
  )
  let data = {
    ..restore_test_session([]),
    model_name: Some("archived-model"),
    model_base_url: "https://api.test.com",
  }
  agent.restore_from_session(data)
  @debug.assert_eq(agent.client.model, "archived-model")
}
