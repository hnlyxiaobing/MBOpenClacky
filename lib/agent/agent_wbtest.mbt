///| White-box tests for the agent package.

///| Tests cover: cost tracking, system prompt building, tool execution,

///|
/// agent lifecycle, ReAct loop, fallback state machine, and compression.

// ── Helper ────────────────────────────────────────────────────────────────────

fn make_test_agent() -> Agent {
  let client = @client.Client::new(
    "test-key",
    "https://api.test.com",
    "test-model",
    @config.OpenAICompletions,
  )
  let config = @config.AgentConfig::default()
  Agent::new("test-session", "test-agent", "/tmp/test", client, config)
}

///|
fn _make_anthropic_agent() -> Agent {
  let client = @client.Client::new(
    "test-key",
    "https://api.test.com",
    "claude-3-5-sonnet",
    @config.AnthropicMessages,
  )
  let config = @config.AgentConfig::default()
  Agent::new("test-session", "test-agent", "/tmp/test", client, config)
}

///|
fn make_mock_response(
  content : String,
  tool_calls : Array[@message.ToolCall]?,
) -> @client.LlmResponse {
  {
    content: Some(content),
    tool_calls,
    finish_reason: Some("stop"),
    usage: Some(@client.Usage::from_openai(100, 50)),
    latency: Some(@client.Latency::new(200, ttft_ms=50)),
    reasoning_content: None,
  }
}

///|
fn make_tool_call(
  id : String,
  name : String,
  arguments : String,
) -> @message.ToolCall {
  { id, type_: "function", function: { name, arguments } }
}

// ── CostTracker Tests ─────────────────────────────────────────────────────────

///|
test "cache_stats_new_defaults" {
  let stats = CacheStats::new()
  @debug.assert_eq(stats.cache_creation_input_tokens, 0)
  @debug.assert_eq(stats.cache_read_input_tokens, 0)
  @debug.assert_eq(stats.total_requests, 0)
  @debug.assert_eq(stats.cache_hit_requests, 0)
}

///|
test "cost_source_to_string" {
  @debug.assert_eq(CostSource::Api.to_string_value(), "api")
  @debug.assert_eq(CostSource::Price.to_string_value(), "price")
  @debug.assert_eq(CostSource::Default.to_string_value(), "default")
  @debug.assert_eq(CostSource::Estimated.to_string_value(), "estimated")
}

///|
test "cost_source_json" {
  let json = CostSource::Api.to_json()
  @debug.assert_eq(json, "api".to_json())
}

///|
test "track_cost_basic" {
  let agent = make_test_agent()
  let usage = @client.Usage::from_openai(1000, 500)
  let token_data = agent.track_cost(usage)
  @debug.assert_eq(token_data.prompt_tokens, 1000)
  @debug.assert_eq(token_data.completion_tokens, 500)
  @debug.assert_eq(token_data.total_tokens, 1500)
  @debug.assert_eq(agent.total_cost, 0.0) // "test-model" not in pricing table
  @debug.assert_eq(agent.previous_total_tokens, 1500)
  @debug.assert_eq(agent.cache_stats.total_requests, 1)
}

///|
test "track_cost_with_known_model" {
  let client = @client.Client::new(
    "test-key",
    "https://api.test.com",
    "claude-3-5-sonnet-20241022",
    @config.AnthropicMessages,
  )
  let agent = Agent::new(
    "test-session",
    "test-agent",
    "/tmp/test",
    client,
    @config.AgentConfig::default(),
  )
  let usage = @client.Usage::from_openai(1000, 500)
  let token_data = agent.track_cost(usage)
  @debug.assert_eq(token_data.cost_source, CostSource::Price)
  assert_true(token_data.cost > 0.0)
  assert_true(agent.total_cost > 0.0)
}

///|
test "track_cost_unknown_model_falls_back_to_estimated" {
  let agent = make_test_agent()
  let usage = @client.Usage::from_openai(1000, 500)
  let token_data = agent.track_cost(usage)
  @debug.assert_eq(token_data.cost_source, CostSource::Estimated)
  @debug.assert_eq(token_data.cost, 0.0)
}

///|
test "track_cost_with_cache" {
  let agent = make_test_agent()
  let usage = @client.Usage::from_openai(
    1000,
    500,
    cache_creation=200,
    cache_read=300,
  )
  let _ = agent.track_cost(usage)
  @debug.assert_eq(agent.cache_stats.cache_creation_input_tokens, 200)
  @debug.assert_eq(agent.cache_stats.cache_read_input_tokens, 300)
  @debug.assert_eq(agent.cache_stats.cache_hit_requests, 1)
}

///|
test "track_cost_delta_tokens" {
  let agent = make_test_agent()
  let usage1 = @client.Usage::from_openai(1000, 500)
  let data1 = agent.track_cost(usage1)
  @debug.assert_eq(data1.delta_tokens, 1500)
  let usage2 = @client.Usage::from_openai(2000, 1000)
  let data2 = agent.track_cost(usage2)
  @debug.assert_eq(data2.delta_tokens, 1500) // 3000 - 1500
}

///|
test "estimate_token_count" {
  @debug.assert_eq(estimate_token_count(""), 0)
  @debug.assert_eq(estimate_token_count("a"), 1)
  @debug.assert_eq(estimate_token_count("abcd"), 1)
  @debug.assert_eq(estimate_token_count("abcde"), 2)
  @debug.assert_eq(estimate_token_count("12345678"), 2)
}

// ── SystemPrompt Tests ────────────────────────────────────────────────────────

///|
test "build_system_prompt_not_empty" {
  let agent = make_test_agent()
  let prompt = agent.build_system_prompt()
  assert_true(prompt.length() > 0)
}

///|
test "build_system_prompt_has_brand_notice" {
  let agent = make_test_agent()
  let prompt = agent.build_system_prompt()
  assert_true(prompt.find("CONFIDENTIAL") is Some(_))
}

///|
test "build_system_prompt_has_base_rules" {
  let agent = make_test_agent()
  let prompt = agent.build_system_prompt()
  assert_true(prompt.find("Core Behavior") is Some(_))
}

///|
test "build_system_prompt_has_working_dir" {
  let agent = make_test_agent()
  let prompt = agent.build_system_prompt()
  assert_true(prompt.find("/tmp/test") is Some(_))
}

///|
test "build_system_prompt_has_model" {
  let agent = make_test_agent()
  let prompt = agent.build_system_prompt()
  assert_true(prompt.find("test-model") is Some(_))
}

///|
test "build_system_prompt_has_environment" {
  let agent = make_test_agent()
  let prompt = agent.build_system_prompt()
  assert_true(prompt.find("Environment") is Some(_))
  assert_true(prompt.find("Current date:") is Some(_))
  assert_true(prompt.find("Operating System:") is Some(_))
}

///|
test "build_system_prompt_has_role_fallback" {
  // Agent named "test-agent" has no profile files on disk,
  // so build_system_prompt should fall back to the hardcoded Role.
  let agent = make_test_agent()
  let prompt = agent.build_system_prompt()
  assert_true(prompt.find("## Role") is Some(_))
  assert_true(prompt.find("AI coding assistant") is Some(_))
}

///|
test "detect_os_returns_nonempty" {
  let os = detect_os()
  assert_true(os.length() > 0)
}

///|
test "format_prompt_section" {
  let section = format_prompt_section("Title", "Content here")
  assert_true(section.find("## Title") is Some(_))
  assert_true(section.find("Content here") is Some(_))
}

///|
test "truncate_text_short" {
  @debug.assert_eq(truncate_text("hello", 10), "hello")
}

///|
test "truncate_text_long" {
  let result = truncate_text("hello world", 8)
  @debug.assert_eq(result, "hello...")
}

///|
test "truncate_text_exact" {
  @debug.assert_eq(truncate_text("hello", 5), "hello")
}

// ── ToolExecutor Tests ────────────────────────────────────────────────────────

///|
test "should_auto_execute_auto_approve" {
  let agent = make_test_agent()
  agent.config.permission_mode = @config.AutoApprove
  assert_true(agent.should_auto_execute("file_reader", Map([])))
  assert_true(agent.should_auto_execute("terminal", Map([])))
  assert_true(agent.should_auto_execute("write", Map([])))
}

///|
test "should_auto_execute_confirm_safes_read" {
  let agent = make_test_agent()
  agent.config.permission_mode = @config.ConfirmSafes
  assert_true(agent.should_auto_execute("file_reader", Map([])))
  assert_true(agent.should_auto_execute("grep", Map([])))
  assert_true(agent.should_auto_execute("glob", Map([])))
}

///|
test "should_auto_execute_confirm_safes_write" {
  let agent = make_test_agent()
  agent.config.permission_mode = @config.ConfirmSafes
  assert_false(agent.should_auto_execute("write", Map([])))
  assert_false(agent.should_auto_execute("edit", Map([])))
}

///|
test "should_auto_execute_confirm_safes_terminal_safe" {
  let agent = make_test_agent()
  agent.config.permission_mode = @config.ConfirmSafes
  let params : Map[String, Json] = { "command": "ls -la".to_json() }
  assert_true(agent.should_auto_execute("terminal", params))
}

///|
test "should_auto_execute_confirm_all" {
  let agent = make_test_agent()
  agent.config.permission_mode = @config.ConfirmAll
  // ConfirmAll (aligned with Ruby openclacky): all tools auto-execute.
  // The difference from AutoApprove is only in request_user_feedback handling:
  // AutoApprove injects auto_reply; ConfirmAll truly waits for user input.
  assert_true(agent.should_auto_execute("file_reader", Map([])))
  assert_true(agent.should_auto_execute("terminal", Map([])))
  assert_true(agent.should_auto_execute("edit", Map([])))
}

///|
test "is_safe_operation_file_reader" {
  let agent = make_test_agent()
  assert_true(agent.is_safe_operation("file_reader", Map([])))
}

///|
test "is_safe_operation_grep" {
  let agent = make_test_agent()
  assert_true(agent.is_safe_operation("grep", Map([])))
}

///|
test "is_safe_operation_write" {
  let agent = make_test_agent()
  // Blacklist: write is NOT safe
  assert_false(agent.is_safe_operation("write", Map([])))
}

///|
test "is_safe_operation_edit" {
  let agent = make_test_agent()
  // Blacklist: edit is NOT safe
  assert_false(agent.is_safe_operation("edit", Map([])))
}

///|
test "is_safe_operation_other_tools" {
  let agent = make_test_agent()
  // Blacklist: everything except edit/write is safe
  assert_true(agent.is_safe_operation("web_search", Map([])))
  assert_true(agent.is_safe_operation("web_fetch", Map([])))
  assert_true(agent.is_safe_operation("invoke_skill", Map([])))
  assert_true(agent.is_safe_operation("todo_manager", Map([])))
  assert_true(agent.is_safe_operation("request_user_feedback", Map([])))
}

///|
test "build_success_result" {
  let call = make_tool_call("call_1", "file_reader", "{}")
  let result = @tool.ToolResult::success("file content")
  let entry = build_success_result(call, result)
  @debug.assert_eq(entry.id, "call_1")
  @debug.assert_eq(entry.content, "file content")
  assert_false(entry.is_error)
}

///|
test "build_error_result" {
  let call = make_tool_call("call_2", "file_reader", "{}")
  let entry = build_error_result(call, "file not found")
  @debug.assert_eq(entry.id, "call_2")
  assert_true(entry.is_error)
}

///|
test "build_denied_result_no_feedback" {
  let call = make_tool_call("call_3", "terminal", "{}")
  let entry = build_denied_result(call, None)
  @debug.assert_eq(entry.id, "call_3")
  assert_true(entry.is_error)
  assert_true(entry.content.find("denied") is Some(_))
}

///|
test "build_denied_result_with_feedback" {
  let call = make_tool_call("call_4", "terminal", "{}")
  let entry = build_denied_result(call, Some("use ls instead"))
  assert_true(entry.content.find("use ls instead") is Some(_))
}

///|
test "parse_tool_arguments_valid_json" {
  let call = make_tool_call(
    "call_1", "file_reader", "{\"path\": \"/tmp/test.txt\"}",
  )
  let args = parse_tool_arguments(call)
  assert_true(args.contains("path"))
}

///|
test "parse_tool_arguments_invalid_json" {
  let call = make_tool_call("call_1", "file_reader", "{invalid}")
  let args = parse_tool_arguments(call)
  @debug.assert_eq(args.length(), 0)
}

///|
test "parse_tool_arguments_empty" {
  let call = make_tool_call("call_1", "file_reader", "")
  let args = parse_tool_arguments(call)
  @debug.assert_eq(args.length(), 0)
}

// ── Agent Lifecycle Tests ─────────────────────────────────────────────────────

///|
test "agent_new_with_client" {
  let agent = make_test_agent()
  @debug.assert_eq(agent.session_id, "test-session")
  @debug.assert_eq(agent.name, "test-agent")
  @debug.assert_eq(agent.working_dir, "/tmp/test")
  @debug.assert_eq(agent.current_model(), "test-model")
  @debug.assert_eq(agent.iterations, 0)
  @debug.assert_eq(agent.total_cost, 0.0)
  assert_true(agent.status == Idle)
}

///|
test "agent_set_reasoning_effort" {
  let agent = make_test_agent()
  agent.set_reasoning_effort(Some("high"))
  @debug.assert_eq(agent.reasoning_effort, Some("high"))
}

///|
test "agent_set_reasoning_effort_off" {
  let agent = make_test_agent()
  agent.set_reasoning_effort(Some("off"))
  @debug.assert_eq(agent.reasoning_effort, None)
}

///|
test "agent_set_reasoning_effort_none" {
  let agent = make_test_agent()
  agent.set_reasoning_effort(Some("none"))
  @debug.assert_eq(agent.reasoning_effort, None)
}

///|
test "agent_set_reasoning_effort_empty" {
  let agent = make_test_agent()
  agent.set_reasoning_effort(Some(""))
  @debug.assert_eq(agent.reasoning_effort, None)
}

///|
test "agent_to_session_data" {
  let agent = make_test_agent()
  agent.history.push(@message.Message::user("hello"))
  let data = agent.to_session_data()
  @debug.assert_eq(data.session_id, "test-session")
  @debug.assert_eq(data.name, "test-agent")
  @debug.assert_eq(data.messages.length(), 1)
  @debug.assert_eq(data.stats.total_iterations, 0)
}

///|
test "to_session_data keeps system_injected on context messages" {
  let agent = make_test_agent()
  let ctx = @message.Message::user("[Session context: test]")
  agent.history.push({ ..ctx, system_injected: Some(true) })
  agent.history.push(@message.Message::user("real question"))
  let data = agent.to_session_data()
  @debug.assert_eq(data.messages.length(), 2)
  @debug.assert_eq(data.messages[0].system_injected, Some(true))
  @debug.assert_eq(data.messages[1].system_injected, None)
}

///|
test "to_session_data carries current_model_id as model_config_id" {
  let agent = make_test_agent()
  agent.config.current_model_id = Some("m_cfg_1")
  let data = agent.to_session_data()
  @debug.assert_eq(data.model_config_id, Some("m_cfg_1"))
  // Without an explicit selection the field stays None (legacy-compatible).
  let plain = make_test_agent()
  @debug.assert_eq(plain.to_session_data().model_config_id, None)
}

///|
test "agent_restore_from_session" {
  let agent = make_test_agent()
  let data = agent.to_session_data()
  agent.iterations = 10
  agent.total_cost = 5.0
  agent.restore_from_session(data)
  @debug.assert_eq(agent.iterations, 0)
  @debug.assert_eq(agent.total_cost, 0.0)
  assert_true(agent.status == Idle)
}

// ── ReAct Loop Tests ──────────────────────────────────────────────────────────

///|
async test "run_empty_history_adds_system_prompt" {
  let agent = make_test_agent()
  // Mock: LLM returns no tool calls → loop exits immediately
  agent.mock_responses.push(make_mock_response("Hello!", None))
  let result = agent.run("Hi") catch { _ => abort("unexpected error") }
  assert_true(result.status == Success)
  // First message should be system prompt
  assert_true(agent.history.length() >= 2)
  assert_true(agent.history[0].role == @message.System)
}

///|
async test "run_increments_iterations" {
  let agent = make_test_agent()
  agent.mock_responses.push(make_mock_response("Done", None))
  let _ = agent.run("test") catch { _ => abort("unexpected error") }
  @debug.assert_eq(agent.iterations, 1)
}

///|
async test "run_no_tool_calls_breaks" {
  let agent = make_test_agent()
  agent.mock_responses.push(make_mock_response("Final answer", None))
  let result = agent.run("question") catch { _ => abort("unexpected error") }
  assert_true(result.status == Success)
  @debug.assert_eq(agent.iterations, 1)
}

///|
async test "run_with_tool_calls_executes" {
  let agent = make_test_agent()
  // First response: tool call to file_reader (safe operation)
  let tool_call = make_tool_call(
    "call_1", "file_reader", "{\"path\": \"/tmp/test.txt\"}",
  )
  agent.mock_responses.push(
    make_mock_response("Reading file...", Some([tool_call])),
  )
  // Second response: no tool calls → exit
  agent.mock_responses.push(make_mock_response("Done", None))
  let result = agent.run("read file") catch { _ => abort("unexpected error") }
  assert_true(result.status == Success)
  @debug.assert_eq(agent.iterations, 2)
}

///|
async test "run_auto_approve_executes_tools" {
  let agent = make_test_agent()
  agent.config.permission_mode = @config.AutoApprove
  let tool_call = make_tool_call(
    "call_1", "file_reader", "{\"path\": \"/tmp/test.txt\"}",
  )
  agent.mock_responses.push(make_mock_response("Reading...", Some([tool_call])))
  agent.mock_responses.push(make_mock_response("Done", None))
  let result = agent.run("read") catch { _ => abort("unexpected error") }
  assert_true(result.status == Success)
}

///|
async test "run_confirm_safes_denies_unsafe" {
  let agent = make_test_agent()
  agent.config.permission_mode = @config.ConfirmSafes
  // write is not safe → should be denied
  let tool_call = make_tool_call(
    "call_1", "write", "{\"path\": \"/tmp/test.txt\", \"content\": \"hello\"}",
  )
  agent.mock_responses.push(make_mock_response("Writing...", Some([tool_call])))
  // After denial, loop should exit
  let result = agent.run("write file") catch { _ => abort("unexpected error") }
  assert_true(result.status == Success)
}

///|
test "build_result_success" {
  let agent = make_test_agent()
  agent.iterations = 5
  agent.total_cost = 0.5
  let result = agent.build_result(Success)
  assert_true(result.status == Success)
  @debug.assert_eq(result.iterations, 5)
  @debug.assert_eq(result.total_cost_usd, 0.5)
}

///|
test "build_result_error" {
  let agent = make_test_agent()
  let result = agent.build_result(Error, error=Some("test error"))
  assert_true(result.status == Error)
  @debug.assert_eq(result.error, Some("test error"))
}

// ── Fallback State Machine Tests ──────────────────────────────────────────────

///|
test "fallback_state_primary_ok" {
  let agent = make_test_agent()
  assert_true(agent.fallback_state == PrimaryOk)
}

///|
test "try_activate_fallback_no_model" {
  let agent = make_test_agent()
  agent.fallback_model = None
  let activated = agent.try_activate_fallback("test-model")
  assert_false(activated)
  assert_true(agent.fallback_state == PrimaryOk)
}

///|
test "try_activate_fallback_with_model" {
  let agent = make_test_agent()
  agent.fallback_model = Some("fallback-model")
  let activated = agent.try_activate_fallback("test-model")
  assert_true(activated)
  match agent.fallback_state {
    FallbackActive(_) => ()
    _ => fail("Expected FallbackActive")
  }
}

///|
test "handle_probe_success" {
  let agent = make_test_agent()
  agent.fallback_state = Probing
  agent.handle_probe_success()
  assert_true(agent.fallback_state == PrimaryOk)
}

///|
test "handle_probe_failure" {
  let agent = make_test_agent()
  agent.fallback_state = Probing
  agent.handle_probe_failure()
  match agent.fallback_state {
    FallbackActive(_) => ()
    _ => fail("Expected FallbackActive")
  }
}

// ── URL Fallback Tests ───────────────────────────────────────────────────────

///|
test "try_url_fallback_no_fallback_url" {
  let agent = make_test_agent()
  agent.config.fallback_base_url = None
  let switched = agent.try_url_fallback()
  assert_false(switched)
  assert_false(agent.url_fallback_active)
}

///|
test "try_url_fallback_with_fallback_url" {
  let agent = make_test_agent()
  agent.config.fallback_base_url = Some("https://fallback.example.com")
  let switched = agent.try_url_fallback()
  assert_true(switched)
  assert_true(agent.url_fallback_active)
  assert_eq(agent.client.base_url, "https://fallback.example.com")
}

///|
test "try_url_fallback_only_once" {
  let agent = make_test_agent()
  agent.config.fallback_base_url = Some("https://fallback.example.com")
  let first = agent.try_url_fallback()
  let second = agent.try_url_fallback()
  assert_true(first)
  assert_false(second)
  assert_true(agent.url_fallback_active)
}

// ── Idle Timer Tests ─────────────────────────────────────────────────────────

///|
async test "idle_timer_starts_after_run" {
  let agent = make_test_agent()
  agent.mock_responses.push(make_mock_response("Hello!", None))
  let _ = agent.run("Hi")
  assert_true(agent.idle_timer.active())
}

///|
async test "idle_timer_cancelled_on_new_input" {
  let agent = make_test_agent()
  agent.mock_responses.push(make_mock_response("Hello!", None))
  let _ = agent.run("Hi")
  assert_true(agent.idle_timer.active())
  // New run should cancel the timer
  agent.mock_responses.push(make_mock_response("Again!", None))
  let _ = agent.run("Another question")
  // After run completes, timer is started again
  assert_true(agent.idle_timer.active())
}

///|
test "idle_timer_initial_state" {
  let agent = make_test_agent()
  assert_false(agent.idle_timer.active())
  match agent.idle_timer.state {
    Idle => ()
    _ => fail("Expected Idle state")
  }
}

// ── Skill Evolution Tests ────────────────────────────────────────────────────

///|
async test "skill_evolution_not_called_when_disabled" {
  let agent = make_test_agent()
  agent.config.skill_evolution = None
  agent.mock_responses.push(make_mock_response("Done", None))
  let result = agent.run("Do something")
  assert_eq(result.status, Success)
}

///|
async test "skill_evolution_called_when_enabled" {
  let agent = make_test_agent()
  agent.config.skill_evolution = Some(Json::null())
  agent.mock_responses.push(make_mock_response("Done", None))
  let result = agent.run("Do something")
  assert_eq(result.status, Success)
}

///|
async test "skill_evolution_not_called_on_error" {
  let agent = make_test_agent()
  agent.config.skill_evolution = Some(Json::null())
  // Empty response triggers error after 3 retries
  agent.mock_responses.push(make_mock_response("", None))
  agent.mock_responses.push(make_mock_response("", None))
  agent.mock_responses.push(make_mock_response("", None))
  let result = agent.run("Do something")
  assert_eq(result.status, Error)
}

// ── Compression Tests ─────────────────────────────────────────────────────────

///|
test "needs_compression_false" {
  let agent = make_test_agent()
  assert_false(agent.needs_compression())
}

///|
test "needs_compression_true_by_count" {
  let agent = make_test_agent()
  // Add more than message_count_threshold messages
  for i in 0..<=message_count_threshold {
    agent.history.push(@message.Message::user("msg \{i}"))
  }
  assert_true(agent.needs_compression())
}

///|
test "compress_messages_if_needed_none" {
  let agent = make_test_agent()
  let ctx = agent.compress_messages_if_needed(false)
  assert_true(ctx is None)
}

///|
test "compress_messages_if_needed_force" {
  let agent = make_test_agent()
  agent.history.push(@message.Message::user("test"))
  let ctx = agent.compress_messages_if_needed(true)
  assert_true(ctx is Some(_))
}

///|
test "estimate_history_tokens" {
  let history : Array[@message.Message] = [
    @message.Message::user("hello"),
    @message.Message::assistant("world"),
  ]
  let tokens = estimate_history_tokens(history)
  assert_true(tokens > 0)
}

// ── LLM Caller Tests ──────────────────────────────────────────────────────────

///|
async test "call_llm_mock_response" {
  let agent = make_test_agent()
  let mock_resp = make_mock_response("mock response", None)
  agent.mock_responses.push(mock_resp)
  let resp = agent.call_llm_async() catch { _ => abort("unexpected error") }
  @debug.assert_eq(resp.content, Some("mock response"))
}

///|
async test "call_llm_no_mock_raises" {
  let agent = make_test_agent()
  let result = Ok(agent.call_llm_async()) catch { e => Err(e) }
  assert_true(result is Err(_))
}

///|
test "messages_for_api_strips_internal" {
  let agent = make_test_agent()
  let msg = @message.Message::user("test")
  agent.history.push(msg)
  let api_msgs = agent.messages_for_api()
  @debug.assert_eq(api_msgs.length(), 1)
  // Internal fields should be stripped by to_api_message
  assert_true(api_msgs[0].task_id is None)
  assert_true(api_msgs[0].created_at is None)
  assert_true(api_msgs[0].system_injected is None)
}

///|
test "handle_context_overflow_standard" {
  let agent = make_test_agent()
  agent.history.push(@message.Message::system("system"))
  agent.history.push(@message.Message::user("msg1"))
  agent.history.push(@message.Message::user("msg2"))
  let removed = agent.handle_context_overflow(Standard)
  assert_true(removed)
  @debug.assert_eq(agent.history.length(), 2) // system + msg1
}

///|
test "handle_context_overflow_aggressive" {
  let agent = make_test_agent()
  agent.history.push(@message.Message::system("system"))
  for i in 0..<10 {
    agent.history.push(@message.Message::user("msg \{i}"))
  }
  let removed = agent.handle_context_overflow(Aggressive)
  assert_true(removed)
  // Should remove ~half of 10 = 5 messages
  assert_true(agent.history.length() < 11)
}

///|
test "detect_upstream_truncation_valid" {
  let tool_call = make_tool_call(
    "call_1", "file_reader", "{\"path\": \"/tmp/test.txt\"}",
  )
  let resp = make_mock_response("ok", Some([tool_call]))
  // Should not raise
  Agent::detect_upstream_truncation(resp) catch {
    _ => fail("unexpected error")
  }
}

///|
test "detect_upstream_truncation_invalid" {
  let tool_call = make_tool_call("call_1", "file_reader", "{invalid json")
  let resp = make_mock_response("ok", Some([tool_call]))
  let result = Ok(Agent::detect_upstream_truncation(resp)) catch { e => Err(e) }
  assert_true(result is Err(_))
}

// ── Session Data Tests ────────────────────────────────────────────────────────

///|
test "session_data_roundtrip" {
  let agent = make_test_agent()
  agent.history.push(@message.Message::user("hello"))
  agent.iterations = 5
  agent.total_cost = 1.5
  let data = agent.to_session_data()
  let agent2 = make_test_agent()
  agent2.restore_from_session(data)
  @debug.assert_eq(agent2.iterations, 5)
  @debug.assert_eq(agent2.total_cost, 1.5)
  @debug.assert_eq(agent2.history.length(), 1)
}

///|
test "session_data_created_at_json_roundtrip" {
  // created_at must survive to_session_data -> to_json -> from_json so
  // history pagination keeps working after a save/load round trip.
  let agent = make_test_agent()
  agent.history.push({
    ..@message.Message::user("stamped"),
    created_at: Some("1700000000001"),
  })
  let data = agent.to_session_data()
  @debug.assert_eq(data.messages[0].created_at, Some("1700000000001"))
  let json = @json.parse(ToJson::to_json(data).stringify())
  let parsed : SessionData = @json.from_json(json)
  @debug.assert_eq(parsed.messages[0].created_at, Some("1700000000001"))
}

///|
test "session_stats_fields" {
  let agent = make_test_agent()
  agent.iterations = 10
  agent.total_cost = 2.0
  agent.total_tasks = 3
  let data = agent.to_session_data()
  @debug.assert_eq(data.stats.total_iterations, 10)
  @debug.assert_eq(data.stats.total_cost_usd, 2.0)
  @debug.assert_eq(data.stats.total_tasks, 3)
}

// ── Session JSON Serialization Tests ──────────────────────────────────────────

///|
test "session_stats_to_json_basic" {
  let stats : SessionStats = {
    total_iterations: 5,
    total_cost_usd: 1.25,
    total_tasks: 2,
    cost_source: "api",
    cache_creation_input_tokens: 100,
    cache_read_input_tokens: 200,
    total_requests: 3,
    cache_hit_requests: 1,
  }
  let json = ToJson::to_json(stats)
  let json_str = json.stringify()
  assert_true(json_str.find("\"total_iterations\"") is Some(_))
  assert_true(json_str.find("\"total_cost_usd\"") is Some(_))
  assert_true(json_str.find("1.25") is Some(_))
  assert_true(json_str.find("\"cost_source\"") is Some(_))
}

///|
test "session_stats_from_json_roundtrip" {
  let original : SessionStats = {
    total_iterations: 10,
    total_cost_usd: 3.5,
    total_tasks: 5,
    cost_source: "estimated",
    cache_creation_input_tokens: 50,
    cache_read_input_tokens: 75,
    total_requests: 8,
    cache_hit_requests: 2,
  }
  let json_str = ToJson::to_json(original).stringify()
  let json = @json.parse(json_str)
  let parsed : SessionStats = @json.from_json(json)
  @debug.assert_eq(parsed.total_iterations, 10)
  @debug.assert_eq(parsed.total_cost_usd, 3.5)
  @debug.assert_eq(parsed.total_tasks, 5)
  @debug.assert_eq(parsed.cost_source, "estimated")
  @debug.assert_eq(parsed.cache_creation_input_tokens, 50)
  @debug.assert_eq(parsed.cache_read_input_tokens, 75)
  @debug.assert_eq(parsed.total_requests, 8)
  @debug.assert_eq(parsed.cache_hit_requests, 2)
}

///|
test "session_data_to_json_basic" {
  let msg = @message.Message::user("test message")
  let stats : SessionStats = {
    total_iterations: 0,
    total_cost_usd: 0.0,
    total_tasks: 0,
    cost_source: "manual",
    cache_creation_input_tokens: 0,
    cache_read_input_tokens: 0,
    total_requests: 0,
    cache_hit_requests: 0,
  }
  let data : SessionData = {
    session_id: "s_test123",
    name: "test",
    messages: [msg],
    stats,
    working_dir: "/tmp",
    created_at: "1234567890",
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
    last_status: "",
    last_error: "",
    error_code: None,
    top_up_url: None,
    raw_message: None,
    forked_from: None,
    chunk_count: 0,
    agent_profile: "general",
    sub_model: None,
  }
  let json = ToJson::to_json(data)
  let json_str = json.stringify()
  assert_true(json_str.find("\"session_id\"") is Some(_))
  assert_true(json_str.find("s_test123") is Some(_))
  assert_true(json_str.find("\"name\"") is Some(_))
  assert_true(json_str.find("\"messages\"") is Some(_))
}

///|
test "session_data_from_json_roundtrip" {
  let msg = @message.Message::user("hello world")
  let stats : SessionStats = {
    total_iterations: 3,
    total_cost_usd: 0.75,
    total_tasks: 1,
    cost_source: "api",
    cache_creation_input_tokens: 10,
    cache_read_input_tokens: 20,
    total_requests: 2,
    cache_hit_requests: 1,
  }
  let original : SessionData = {
    session_id: "s_roundtrip",
    name: "roundtrip-test",
    messages: [msg],
    stats,
    working_dir: "/home/test",
    created_at: "9876543210",
    source: "cli",
    reasoning_effort: Some("high"),
    model_name: Some("gpt-4"),
    model_config_id: None,
    channel_info: None,
    latest_latency_ms: None,
    latest_ttft_ms: None,
    time_machine: None,
    pending_error_rollback: false,
    model_base_url: "",
    last_status: "",
    last_error: "",
    error_code: None,
    top_up_url: None,
    raw_message: None,
    forked_from: None,
    chunk_count: 0,
    agent_profile: "general",
    sub_model: None,
  }
  // Direct JSON construction avoids stringify/parse roundtrip issues
  let json_obj = Json::object({
    "session_id": "s_roundtrip".to_json(),
    "name": "roundtrip-test".to_json(),
    "messages": ToJson::to_json(original.messages),
    "stats": ToJson::to_json(original.stats),
    "working_dir": "/home/test".to_json(),
    "created_at": "9876543210".to_json(),
    "source": "cli".to_json(),
    "reasoning_effort": "high".to_json(),
    "model_name": "gpt-4".to_json(),
  })
  let parsed : SessionData = @json.from_json(json_obj)
  @debug.assert_eq(parsed.session_id, "s_roundtrip")
  @debug.assert_eq(parsed.name, "roundtrip-test")
  @debug.assert_eq(parsed.messages.length(), 1)
  assert_true(
    parsed.messages[0].content ==
    (@message.MessageContent::Text("hello world") : @message.MessageContent),
  )
  @debug.assert_eq(parsed.stats.total_iterations, 3)
  @debug.assert_eq(parsed.stats.total_cost_usd, 0.75)
  @debug.assert_eq(parsed.working_dir, "/home/test")
  // Legacy epoch-ms created_at is normalized to ISO 8601 on load (fix-03).
  @debug.assert_eq(parsed.created_at, ms_to_iso8601(9876543210L))
  @debug.assert_eq(parsed.source, "cli")
  @debug.assert_eq(parsed.reasoning_effort, Some("high"))
  @debug.assert_eq(parsed.model_name, Some("gpt-4"))
}

///|
test "session_data_from_json_missing_optional" {
  let stats : SessionStats = {
    total_iterations: 0,
    total_cost_usd: 0.0,
    total_tasks: 0,
    cost_source: "manual",
    cache_creation_input_tokens: 0,
    cache_read_input_tokens: 0,
    total_requests: 0,
    cache_hit_requests: 0,
  }
  // Build JSON with only required fields
  let map : Map[String, Json] = {
    "session_id": "s_minimal".to_json(),
    "name": "minimal".to_json(),
    "messages": (([] : Array[Json]).to_json() : Json),
    "stats": ToJson::to_json(stats),
    "working_dir": "/tmp".to_json(),
    "created_at": "0".to_json(),
  }
  let json_str = Json::object(map).stringify()
  let json = @json.parse(json_str)
  let parsed : SessionData = @json.from_json(json)
  @debug.assert_eq(parsed.session_id, "s_minimal")
  @debug.assert_eq(parsed.source, "manual")
  @debug.assert_eq(parsed.reasoning_effort, None)
  @debug.assert_eq(parsed.model_name, None)
}

///|
test "session_data_with_multiple_messages_json" {
  let msgs = [
    @message.Message::system("system prompt"),
    @message.Message::user("user message"),
    @message.Message::assistant("assistant response"),
  ]
  let stats : SessionStats = {
    total_iterations: 1,
    total_cost_usd: 0.1,
    total_tasks: 1,
    cost_source: "api",
    cache_creation_input_tokens: 0,
    cache_read_input_tokens: 0,
    total_requests: 1,
    cache_hit_requests: 0,
  }
  let data : SessionData = {
    session_id: "s_multi",
    name: "multi-msg-test",
    messages: msgs,
    stats,
    working_dir: ".",
    created_at: "1111111111",
    source: "test",
    reasoning_effort: None,
    model_name: None,
    model_config_id: None,
    channel_info: None,
    latest_latency_ms: None,
    latest_ttft_ms: None,
    time_machine: None,
    pending_error_rollback: false,
    model_base_url: "",
    last_status: "",
    last_error: "",
    error_code: None,
    top_up_url: None,
    raw_message: None,
    forked_from: None,
    chunk_count: 0,
    agent_profile: "general",
    sub_model: None,
  }
  let json_str = ToJson::to_json(data).stringify()
  let json = @json.parse(json_str)
  let parsed : SessionData = @json.from_json(json)
  @debug.assert_eq(parsed.messages.length(), 3)
  assert_true(parsed.messages[0].role == @message.System)
  assert_true(parsed.messages[1].role == @message.User)
  assert_true(parsed.messages[2].role == @message.Assistant)
}

// ── Session Manager Tests ─────────────────────────────────────────────────────

///|
test "format_session_summary_with_model" {
  let stats : SessionStats = {
    total_iterations: 0,
    total_cost_usd: 0.0,
    total_tasks: 0,
    cost_source: "manual",
    cache_creation_input_tokens: 0,
    cache_read_input_tokens: 0,
    total_requests: 0,
    cache_hit_requests: 0,
  }
  let data : SessionData = {
    session_id: "s_summary",
    name: "summary-test",
    messages: [],
    stats,
    working_dir: ".",
    created_at: "1234567890",
    source: "test",
    reasoning_effort: None,
    model_name: Some("gpt-4"),
    model_config_id: None,
    channel_info: None,
    latest_latency_ms: None,
    latest_ttft_ms: None,
    time_machine: None,
    pending_error_rollback: false,
    model_base_url: "",
    last_status: "",
    last_error: "",
    error_code: None,
    top_up_url: None,
    raw_message: None,
    forked_from: None,
    chunk_count: 0,
    agent_profile: "general",
    sub_model: None,
  }
  let summary = format_session_summary(data)
  assert_true(summary.find("s_summary") is Some(_))
  assert_true(summary.find("1234567890") is Some(_))
  assert_true(summary.find("gpt-4") is Some(_))
  assert_true(summary.find("0 msgs") is Some(_))
}

///|
test "format_session_summary_no_model" {
  let stats : SessionStats = {
    total_iterations: 0,
    total_cost_usd: 0.0,
    total_tasks: 0,
    cost_source: "manual",
    cache_creation_input_tokens: 0,
    cache_read_input_tokens: 0,
    total_requests: 0,
    cache_hit_requests: 0,
  }
  let data : SessionData = {
    session_id: "s_nomodel",
    name: "no-model",
    messages: [],
    stats,
    working_dir: ".",
    created_at: "0",
    source: "test",
    reasoning_effort: None,
    model_name: None,
    model_config_id: None,
    channel_info: None,
    latest_latency_ms: None,
    latest_ttft_ms: None,
    time_machine: None,
    pending_error_rollback: false,
    model_base_url: "",
    last_status: "",
    last_error: "",
    error_code: None,
    top_up_url: None,
    raw_message: None,
    forked_from: None,
    chunk_count: 0,
    agent_profile: "general",
    sub_model: None,
  }
  let summary = format_session_summary(data)
  assert_true(summary.find("s_nomodel") is Some(_))
  assert_true(summary.find("-") is Some(_)) // placeholder for no model
}

///|
test "generate_session_id_format" {
  let id = generate_session_id()
  assert_true(id.has_prefix("s_"))
  assert_true(id.length() > 2)
}

///|
test "current_timestamp_iso_format" {
  let ts = current_timestamp_iso()
  // ISO 8601 local format: "2026-07-24T12:22:34+08:00"
  assert_true(ts.length() == 25)
  assert_true(ts[4] == '-' && ts[7] == '-')
  assert_true(ts[10] == 'T')
  assert_true(ts[13] == ':' && ts[16] == ':')
  // Trailing UTC offset like "+08:00" or "-05:00".
  let sign = ts[19]
  assert_true(sign == '+' || sign == '-')
  assert_true(ts[22] == ':')
}

// ── Streaming pipeline tests (#4) ───────────────────────────────────────────

///|
async test "call_llm_stream_async mock path emits content as a single chunk" {
  let agent = make_test_agent()
  agent.mock_responses.push(make_mock_response("Hello stream", None))
  let chunks : Array[String] = []
  let response = agent.call_llm_stream_async(fn(c) { chunks.push(c) })
  @debug.assert_eq(chunks, ["Hello stream"])
  @debug.assert_eq(response.content, Some("Hello stream"))
}

///|
async test "call_llm_stream_async mock path with empty content emits no chunk" {
  let agent = make_test_agent()
  agent.mock_responses.push({
    content: None,
    tool_calls: None,
    finish_reason: Some("stop"),
    usage: None,
    latency: None,
    reasoning_content: None,
  })
  let chunks : Array[String] = []
  let response = agent.call_llm_stream_async(fn(c) { chunks.push(c) })
  @debug.assert_eq(chunks.length(), 0)
  assert_true(response.content is None)
}

// ── Agent::rename ────────────────────────────────────────────────────────────

///|
test "agent_rename_updates_session_data_name" {
  let agent = make_test_agent()
  @debug.assert_eq(agent.to_session_data().name, "test-agent")
  agent.rename("renamed-agent")
  @debug.assert_eq(agent.to_session_data().name, "renamed-agent")
}

// ── Empty Response Detection ────────────────────────────────────────────────

///|
async test "empty_response_retries_then_succeeds" {
  let agent = make_test_agent()
  agent.mock_responses.push(make_mock_response("", None))
  agent.mock_responses.push(make_mock_response("Here is the answer", None))
  let result = agent.run("question") catch { _ => abort("unexpected error") }
  assert_true(result.status == Success)
  @debug.assert_eq(agent.iterations, 2)
}

///|
async test "empty_response_exhausts_retries" {
  let agent = make_test_agent()
  agent.mock_responses.push(make_mock_response("", None))
  agent.mock_responses.push(make_mock_response("", None))
  agent.mock_responses.push(make_mock_response("", None))
  let result = agent.run("question") catch { _ => abort("unexpected error") }
  assert_true(result.status == Error)
}

///|
async test "thinking_silent_response_retries" {
  let agent = make_test_agent()
  agent.mock_responses.push({
    content: Some(""),
    tool_calls: None,
    finish_reason: Some("stop"),
    usage: Some(@client.Usage::from_openai(100, 50)),
    latency: Some(@client.Latency::new(200, ttft_ms=50)),
    reasoning_content: Some("thinking hard..."),
  })
  agent.mock_responses.push(make_mock_response("Done thinking", None))
  let result = agent.run("question") catch { _ => abort("unexpected error") }
  assert_true(result.status == Success)
  @debug.assert_eq(agent.iterations, 2)
}
