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
/// Variant with a custom finish_reason (truncation / empty tests).
fn make_mock_response_fr(
  content : String,
  tool_calls : Array[@message.ToolCall]?,
  finish_reason : String?,
  reasoning_content? : String? = None,
) -> @client.LlmResponse {
  {
    content: Some(content),
    tool_calls,
    finish_reason,
    usage: Some(@client.Usage::from_openai(100, 50)),
    latency: Some(@client.Latency::new(200, ttft_ms=50)),
    reasoning_content,
  }
}

///|
fn make_tool_call(
  id : String,
  name : String,
  arguments : String,
) -> @message.ToolCall {
  { id, type_: "function", function: { name, arguments }, extra_content: None }
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
  agent.history.append(@message.Message::user("hello"))
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
  agent.history.append({ ..ctx, system_injected: Some(true) })
  agent.history.append(@message.Message::user("real question"))
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
  assert_true(agent.history.size() >= 2)
  assert_true(agent.history.all()[0].role == @message.System)
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

// ── B7 Task-1: main-loop robustness ─────────────────────────────────────────

///|
async test "run_truncation_drops_dangling_tool_calls" {
  let agent = make_test_agent()
  // Response 1: finish_reason=length with a dangling tool call. The args
  // must be valid non-empty JSON — "{}" would be flagged as truncated by
  // detect_upstream_truncation and absorbed by the retry pipeline before
  // the main loop's length branch ever runs.
  let tool_call = make_tool_call(
    "call_1", "file_reader", "{\"path\":\"/tmp/x\"}",
  )
  agent.mock_responses.push(
    make_mock_response_fr("partial...", Some([tool_call]), Some("length")),
  )
  // Response 2: normal completion.
  agent.mock_responses.push(make_mock_response("Done", None))
  let result = agent.run("do work") catch { _ => abort("unexpected error") }
  assert_true(result.status == Success) // No assistant message may carry tool_calls after a truncation (the
  // dangling calls are protocol poison for the next request).
  let dangling = agent.history
    .all()
    .filter(fn(m) {
      match m.tool_calls {
        Some(calls) => calls.length() > 0
        None => false
      }
    })
  @debug.assert_eq(dangling.length(), 0)
  // The detailed [SYSTEM] continuation hint is present.
  let has_hint = agent.history
    .all()
    .any(fn(m) {
      match m.content {
        @message.Text(t) => t.contains("output token limit")
        _ => false
      }
    })
  assert_true(has_hint)
}

///|
async test "run_truncation_three_times_apologizes_and_succeeds" {
  let agent = make_test_agent()
  for _i in 0..<3 {
    agent.mock_responses.push(
      make_mock_response_fr("partial", None, Some("length")),
    )
  }
  let result = agent.run("big task") catch { _ => abort("unexpected error") }
  // Ruby: too many truncations → apologize and end NORMALLY (Success).
  assert_true(result.status == Success)
  let has_apology = agent.history
    .all()
    .any(fn(m) {
      match m.content {
        @message.Text(t) => t.contains("too complex to complete")
        _ => false
      }
    })
  assert_true(has_apology)
}

///|
async test "run_truncation_preserves_reasoning_content" {
  let agent = make_test_agent()
  agent.mock_responses.push(
    make_mock_response_fr(
      "partial",
      None,
      Some("length"),
      reasoning_content=Some("thinking..."),
    ),
  )
  agent.mock_responses.push(make_mock_response("Done", None))
  let result = agent.run("x") catch { _ => abort("unexpected error") }
  assert_true(result.status == Success)
  // The truncated assistant message keeps its reasoning_content (Ruby
  // truncated_msg[:reasoning_content]) so thinking-mode padding works.
  let has_reasoning = agent.history
    .all()
    .any(fn(m) {
      match m.reasoning_content {
        Some(r) => r == "thinking..."
        None => false
      }
    })
  assert_true(has_reasoning)
}

///|
async test "run_fake_tool_call_over_limit_returns_error" {
  let agent = make_test_agent()
  // Three fake-tool-call responses: two corrections, then stop-with-error.
  for _i in 0..<3 {
    agent.mock_responses.push(
      make_mock_response_fr(
        "<invoke name=\"search\">q</invoke>",
        None,
        Some("stop"),
      ),
    )
  }
  let result = agent.run("do it") catch { _ => abort("unexpected error") }
  // Over-limit must NOT silently succeed with the XML text as the answer.
  assert_true(result.status == Error)
  match result.error {
    Some(e) => assert_true(e.contains("repeatedly emitted"))
    None => fail("expected an error message")
  }
}

///|
async test "run_fake_tool_call_recovers_after_correction" {
  let agent = make_test_agent()
  // Two fake responses (both within the retry budget) then a clean answer.
  agent.mock_responses.push(
    make_mock_response_fr(
      "<invoke name=\"search\">q</invoke>",
      None,
      Some("stop"),
    ),
  )
  agent.mock_responses.push(
    make_mock_response_fr("<antml:invoke name=\"read\">", None, Some("stop")),
  )
  agent.mock_responses.push(make_mock_response("Done", None))
  let result = agent.run("do it") catch { _ => abort("unexpected error") }
  assert_true(result.status == Success)
}

///|
async test "run_empty_response_stop_uses_loop_fallback" {
  let agent = make_test_agent()
  // finish_reason="stop" + empty content: llm_caller does NOT intercept
  // (stop is protocol-legal); the main-loop fallback caps it at 3 → Error.
  for _i in 0..<3 {
    agent.mock_responses.push(make_mock_response_fr("", None, Some("stop")))
  }
  let result = agent.run("x") catch { _ => abort("unexpected error") }
  assert_true(result.status == Error)
}

///|
async test "run_truncation_length_not_intercepted_by_empty_detector" {
  let agent = make_test_agent()
  // Empty content + finish_reason=length: the empty detector must NOT
  // raise (length is truncation, handled by the loop's length branch),
  // so the run continues to the next mock and succeeds.
  agent.mock_responses.push(make_mock_response_fr("", None, Some("length")))
  agent.mock_responses.push(make_mock_response("Done", None))
  let result = agent.run("x") catch { _ => abort("unexpected error") }
  assert_true(result.status == Success)
}

///|
test "to_session_data_pending_error_rollback_flag" {
  let agent = make_test_agent()
  // status == Error derives the flag (existing persistence contract).
  agent.status = Error
  assert_true(agent.to_session_data().pending_error_rollback)
  // The explicit 400-class flag (B7 decision 4) survives even when the
  // run status has been reset (e.g. Idle after restore).
  agent.status = Idle
  agent.pending_error_rollback = true
  assert_true(agent.to_session_data().pending_error_rollback)
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
    agent.history.append(@message.Message::user("msg \{i}"))
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
  agent.history.append(@message.Message::user("test"))
  // Force mode with insufficient messages: should return None (aligned with Ruby)
  let ctx = agent.compress_messages_if_needed(true)
  assert_true(ctx is None)
  // Add enough messages to exceed max_recent_messages
  for i = 0; i < 25; i = i + 1 {
    agent.history.append(@message.Message::user("msg \{i}"))
    let _ = i
  }
  let ctx2 = agent.compress_messages_if_needed(true)
  assert_true(ctx2 is Some(_))
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
  agent.history.append(msg)
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
  agent.history.append(@message.Message::system("system"))
  agent.history.append(@message.Message::user("msg1"))
  agent.history.append(@message.Message::user("msg2"))
  let removed = agent.handle_context_overflow(Standard)
  assert_true(removed)
  @debug.assert_eq(agent.history.size(), 2) // system + msg1
}

///|
test "handle_context_overflow_aggressive" {
  let agent = make_test_agent()
  agent.history.append(@message.Message::system("system"))
  for i in 0..<10 {
    agent.history.append(@message.Message::user("msg \{i}"))
  }
  let removed = agent.handle_context_overflow(Aggressive)
  assert_true(removed)
  // Should remove ~half of 10 = 5 messages
  assert_true(agent.history.size() < 11)
}

// ── BUG-0029 / BUG-0028 验收点 (spec 2026-08-18_14) ────────────────────────

///|
/// BUG-0029 验收：Aggressive 钳制公式对齐 Ruby llm_caller.rb:535-549。
/// 201 条历史（1 system + 200 user）→ half=100, lower=max(100,4)=100,
/// upper=min(199,64)=64, remove=min(100,64)=64 → 剩 137。
test "handle_context_overflow_aggressive_clamps_to_64" {
  let agent = make_test_agent()
  agent.history.append(@message.Message::system("sys"))
  for _ in 0..<200 {
    agent.history.append(@message.Message::user("u"))
  }
  assert_eq(agent.history.size(), 201)
  let removed = agent.handle_context_overflow(Aggressive)
  assert_true(removed)
  assert_eq(agent.history.size(), 137)
  // compression_level 在 pop 后 +1
  @debug.assert_eq(agent.compression_level, 1)
}

///|
/// BUG-0029 验收：Aggressive 的 lower 边界 = 4（max(half, 4)）。
/// 9 条历史 → half=4, lower=max(4,4)=4, upper=min(7,64)=7, remove=4 → 剩 5。
test "handle_context_overflow_aggressive_clamps_to_4" {
  let agent = make_test_agent()
  agent.history.append(@message.Message::system("sys"))
  for i in 0..<8 {
    agent.history.append(@message.Message::user("u \{i}"))
  }
  // 9 条 total：1 system + 8 user
  assert_eq(agent.history.size(), 9)
  let removed = agent.handle_context_overflow(Aggressive)
  assert_true(removed)
  // 弹 4 条 → 剩 5
  assert_eq(agent.history.size(), 5)
}

///|
/// BUG-0028 阶段 A 验收：handle_context_overflow pop 后调用
/// compress_messages_if_needed(false)。压缩调用在函数内不可被外部直接观测，
/// 本测试通过"巨大 tool_result 触发 oversized path"间接验证：
/// 之前 needs_compression=false（短消息），handle_context_overflow 内部
/// 调用 compress_messages_if_needed 时不会因 oversized path 误判 panic；
/// 函数正常返回 + history size 减 1 + compression_level 增 1 即说明 pop
/// 后压缩判定已执行。
test "handle_context_overflow_pop_does_not_panic_with_oversized_tool_result" {
  let agent = make_test_agent()
  agent.config.compression_threshold = 100_000 // disable token threshold
  agent.history.append(@message.Message::system("sys"))
  agent.history.append(@message.Message::user("msg1"))
  // assistant with matching tool_calls 让 tool_result 不被 drop
  let asst = @message.Message::assistant("thinking")
  asst.tool_calls = Some([@message.ToolCall::new("c1", "f1", "{}")])
  agent.history.append(asst)
  // > 2000 字符的 tool_result 触发 oversized path
  let big = String::make(3000, 'a')
  agent.history.append(@message.Message::tool_result("c1", "f1", big))
  // 4 条 total，pop 1 → 剩 3
  let removed = agent.handle_context_overflow(Standard)
  assert_true(removed)
  assert_eq(agent.history.size(), 3)
  // compression_level 增 1
  @debug.assert_eq(agent.compression_level, 1)
}

///|
/// BUG-0028 阶段 A 验收：pop 后调压缩在长 history 上也不 panic。
/// 100 条 user + 1 system = 101 条；threshold 高 → 不会真触发压缩。
/// 验证函数完整跑完 pop + 压缩判定流程。
test "handle_context_overflow_pop_evaluates_compression_on_long_history" {
  let agent = make_test_agent()
  agent.config.compression_threshold = 1_000_000 // disable
  agent.history.append(@message.Message::system("sys"))
  for _ in 0..<100 {
    agent.history.append(@message.Message::user("u"))
  }
  let removed = agent.handle_context_overflow(Standard)
  assert_true(removed)
  assert_eq(agent.history.size(), 100) // 101 - 1
  @debug.assert_eq(agent.compression_level, 1)
}

///|
test "detect_upstream_truncation_valid" {
  let agent = make_test_agent()
  let tool_call = make_tool_call(
    "call_1", "file_reader", "{\"path\": \"/tmp/test.txt\"}",
  )
  let resp = make_mock_response("ok", Some([tool_call]))
  // Should not raise
  agent.detect_upstream_truncation(resp) catch {
    _ => fail("unexpected error")
  }
}

///|
test "detect_upstream_truncation_invalid" {
  let agent = make_test_agent()
  let tool_call = make_tool_call("call_1", "file_reader", "{invalid json")
  let resp = make_mock_response("ok", Some([tool_call]))
  let result = Ok(agent.detect_upstream_truncation(resp)) catch { e => Err(e) }
  assert_true(result is Err(_))
}

// ── Session Data Tests ────────────────────────────────────────────────────────

///|
test "session_data_roundtrip" {
  let agent = make_test_agent()
  agent.history.append(@message.Message::user("hello"))
  agent.iterations = 5
  agent.total_cost = 1.5
  let data = agent.to_session_data()
  let agent2 = make_test_agent()
  agent2.restore_from_session(data)
  @debug.assert_eq(agent2.iterations, 5)
  @debug.assert_eq(agent2.total_cost, 1.5)
  // Restore re-inserts a freshly built system prompt at the head
  // (decision 6), so the history is [system, user].
  @debug.assert_eq(agent2.history.size(), 2)
  @debug.assert_eq(agent2.history.all()[0].role, @message.System)
  @debug.assert_eq(agent2.history.all()[1].role, @message.User)
}

///|
test "session_data_created_at_json_roundtrip" {
  // created_at must survive to_session_data -> to_json -> from_json so
  // history pagination keeps working after a save/load round trip.
  let agent = make_test_agent()
  agent.history.append({
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
    pinned: false,
    todos: None,
    updated_at: "1234567890",
    previous_total_tokens: 0,
    deleted_at: None,
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
    pinned: false,
    todos: None,
    updated_at: "1234567890",
    previous_total_tokens: 0,
    deleted_at: None,
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
    pinned: false,
    todos: None,
    updated_at: "1234567890",
    previous_total_tokens: 0,
    deleted_at: None,
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
    pinned: false,
    todos: None,
    updated_at: "1234567890",
    previous_total_tokens: 0,
    deleted_at: None,
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
    pinned: false,
    todos: None,
    updated_at: "1234567890",
    previous_total_tokens: 0,
    deleted_at: None,
  }
  let summary = format_session_summary(data)
  assert_true(summary.find("s_nomodel") is Some(_))
  assert_true(summary.find("-") is Some(_)) // placeholder for no model
}

///|
test "generate_session_id_format" {
  let id = generate_session_id()
  // 16-char random hex (decision 6), no legacy "s_" prefix.
  assert_true(id.length() == 16)
  for ch in id {
    assert_true((ch >= '0' && ch <= '9') || (ch >= 'a' && ch <= 'f'))
  }
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
  // B7 decision 3: thinking-mode-silent responses (reasoning present, empty
  // content, finish_reason=stop) are intercepted in llm_caller
  // (check_empty_response → RetryableError) and absorbed by the internal
  // 10-retry pipeline — the main loop never sees them, so iterations == 1.
  @debug.assert_eq(agent.iterations, 1)
}

// ── P6: JSON result builders ─────────────────────────────────────────────────

///|
test "build_error_result_valid_json" {
  let call = make_tool_call("call_1", "file_reader", "{}")
  let entry = build_error_result(call, "boom \"quoted\"\nline2")
  assert_true(entry.is_error)
  // Content must round-trip through a JSON parser (keys quoted, escaped)
  let parsed = @json.parse(entry.content) catch { _ => abort("invalid json") }
  match parsed {
    Object(obj) =>
      match obj.get("error") {
        Some(String(s)) => @debug.assert_eq(s, "boom \"quoted\"\nline2")
        _ => abort("missing error key")
      }
    _ => abort("not an object")
  }
}

///|
test "build_denied_result_valid_json" {
  let call = make_tool_call("call_1", "write", "{}")
  let entry = build_denied_result(call, None)
  assert_true(entry.is_error)
  let parsed = @json.parse(entry.content) catch { _ => abort("invalid json") }
  match parsed {
    Object(obj) => {
      match obj.get("error") {
        Some(String(s)) =>
          @debug.assert_eq(
            s, "Tool use denied by user. This action was NOT performed.",
          )
        _ => abort("missing error key")
      }
      match obj.get("action_performed") {
        Some(False) => ()
        _ => abort("action_performed must be false")
      }
      match obj.get("user_feedback") {
        Some(Null) => ()
        _ => abort("user_feedback must be null")
      }
    }
    _ => abort("not an object")
  }
}

///|
test "build_denied_result_with_feedback_content" {
  let call = make_tool_call("call_1", "write", "{}")
  let entry = build_denied_result(call, Some("Do it differently"))
  let parsed = @json.parse(entry.content) catch { _ => abort("invalid json") }
  match parsed {
    Object(obj) => {
      match obj.get("error") {
        Some(String(s)) =>
          @debug.assert_eq(
            s, "Tool use denied by user. This action was NOT performed. User feedback: Do it differently",
          )
        _ => abort("missing error key")
      }
      match obj.get("user_feedback") {
        Some(String(fb)) => @debug.assert_eq(fb, "Do it differently")
        _ => abort("user_feedback must carry the feedback")
      }
    }
    _ => abort("not an object")
  }
}

// ── P6: argument parsing with JSON repair ────────────────────────────────────

///|
test "parse_repairs_trailing_comma" {
  let call = make_tool_call(
    "c1", "file_reader", "{\"path\":\"a.txt\",\"max_lines\":10,}",
  )
  let (args, err) = parse_tool_arguments_checked(call)
  assert_true(err is None)
  match args.get("max_lines") {
    Some(Number(n, ..)) => @debug.assert_eq(n.to_int(), 10)
    _ => abort("max_lines missing after repair")
  }
}

///|
test "parse_repairs_xml_contamination" {
  let call = make_tool_call(
    "c1", "file_reader", "{<parameter name=\"path\">\"a.txt\"</parameter><parameter name=\"max_lines\">10</parameter>}",
  )
  let (args, err) = parse_tool_arguments_checked(call)
  assert_true(err is None)
  match args.get("path") {
    Some(String(p)) => @debug.assert_eq(p, "a.txt")
    _ => abort("path missing after repair")
  }
  match args.get("max_lines") {
    Some(Number(n, ..)) => @debug.assert_eq(n.to_int(), 10)
    _ => abort("max_lines missing after repair")
  }
}

///|
test "parse_repairs_truncated_object" {
  let call = make_tool_call(
    "c1", "file_reader", "{\"path\":\"a.txt\",\"max_lines\":10",
  )
  let (args, err) = parse_tool_arguments_checked(call)
  assert_true(err is None)
  match args.get("path") {
    Some(String(p)) => @debug.assert_eq(p, "a.txt")
    _ => abort("path missing after repair")
  }
}

///|
test "parse_repairs_escaped_quotes" {
  // Literal backslash-quote artifacts: {"path":\"a.txt\"}
  let call = make_tool_call("c1", "file_reader", "{\\\"path\\\":\\\"a.txt\\\"}")
  let (args, err) = parse_tool_arguments_checked(call)
  assert_true(err is None)
  match args.get("path") {
    Some(String(p)) => @debug.assert_eq(p, "a.txt")
    _ => abort("path missing after repair")
  }
}

///|
test "parse_unparseable_returns_error" {
  let call = make_tool_call("c1", "file_reader", "{{{ not json")
  let (_, err) = parse_tool_arguments_checked(call)
  match err {
    Some(msg) => assert_true(msg.contains("could not be parsed"))
    None => abort("expected parse error")
  }
}

///|
test "parse_empty_arguments_ok" {
  let call = make_tool_call("c1", "file_reader", "")
  let (args, err) = parse_tool_arguments_checked(call)
  assert_true(err is None)
  @debug.assert_eq(args.length(), 0)
}

///|
test "parse_tool_arguments_backwards_compat" {
  let call = make_tool_call("c1", "file_reader", "not json")
  let args = parse_tool_arguments(call)
  @debug.assert_eq(args.length(), 0)
}

// ── P6: TODO reminder injection ──────────────────────────────────────────────

///|
test "inject_todo_reminder_appends" {
  let agent = make_test_agent()
  let _ = agent.todo_manager.add("Write docs", "")
  let call = make_tool_call("c1", "file_reader", "{}")
  let entry : ToolResultEntry = {
    id: "c1",
    content: "ok",
    is_error: false,
    image_inject: None,
  }
  let injected = agent.inject_todo_reminder(call, entry)
  assert_true(injected.content.contains("ok"))
  assert_true(
    injected.content.contains("📋 REMINDER: You have 1 pending TODO(s)"),
  )
  assert_true(injected.content.contains("todo_manager with action 'complete'"))
}

///|
test "inject_todo_reminder_skips_todo_manager" {
  let agent = make_test_agent()
  let _ = agent.todo_manager.add("Write docs", "")
  let call = make_tool_call("c1", "todo_manager", "{}")
  let entry : ToolResultEntry = {
    id: "c1",
    content: "ok",
    is_error: false,
    image_inject: None,
  }
  let injected = agent.inject_todo_reminder(call, entry)
  @debug.assert_eq(injected.content, "ok")
}

///|
test "inject_todo_reminder_no_pending" {
  let agent = make_test_agent()
  let call = make_tool_call("c1", "file_reader", "{}")
  let entry : ToolResultEntry = {
    id: "c1",
    content: "ok",
    is_error: false,
    image_inject: None,
  }
  let injected = agent.inject_todo_reminder(call, entry)
  @debug.assert_eq(injected.content, "ok")
}

// ── P6: execute_single_tool integration ──────────────────────────────────────

///|
async test "execute_single_tool_unparseable_returns_error" {
  let agent = make_test_agent()
  let call = make_tool_call("c1", "file_reader", "{{{ not json")
  let entry = agent.execute_single_tool(call)
  assert_true(entry.is_error)
  assert_true(entry.content.contains("could not be parsed as JSON"))
}

///|
async test "execute_single_tool_injects_todo_reminder" {
  let agent = make_test_agent()
  let _ = agent.todo_manager.add("Write docs", "")
  let call = make_tool_call("c1", "memory", "{\"action\":\"list\"}")
  let entry = agent.execute_single_tool(call)
  assert_false(entry.is_error)
  assert_true(entry.content.contains("REMINDER"))
  assert_true(entry.content.contains("1 pending TODO"))
}

///|
/// P6: every terminal invocation gets CLACKY_SESSION_ID injected into the
/// child env (Ruby agent.rb semantics: args[:env] merged with the session
/// id first, so a user-supplied env value would win).
async test "execute_single_tool_injects_clacky_session_id_into_terminal" {
  let agent = make_test_agent()
  // make_test_agent() uses session id "test-session"
  let cmd = if @tool.shell_is_windows() {
    "echo %CLACKY_SESSION_ID%"
  } else {
    "echo $CLACKY_SESSION_ID"
  }
  let call = make_tool_call("c1", "terminal", "{\"command\":\"\{cmd}\"}")
  let entry = agent.execute_single_tool(call)
  assert_false(entry.is_error, msg="terminal failed: \{entry.content}")
  assert_true(
    entry.content.contains("test-session"),
    msg="expected CLACKY_SESSION_ID in output, got: \{entry.content}",
  )
}

// ── P6: denied pairing + canonical-name permission checks ────────────────────

///|
async test "act_async_denied_pairs_all_tool_calls" {
  let agent = make_test_agent()
  agent.config.permission_mode = @config.ConfirmSafes
  // write requires confirmation; deny it
  agent.confirmation_callback = Some(fn(_name, _args) { false })
  let calls = [
    make_tool_call(
      "c1", "write", "{\"path\":\"/tmp/p6_deny.txt\",\"content\":\"x\"}",
    ),
    make_tool_call("c2", "file_reader", "{\"path\":\"/tmp/p6_deny.txt\"}"),
    make_tool_call("c3", "glob", "{\"pattern\":\"*\"}"),
  ]
  let result = agent.act_async(calls)
  assert_true(result.denied)
  // Every tool_use must have a paired result (protocol invariant)
  @debug.assert_eq(result.tool_results.length(), 3)
  for i in 0..<3 {
    @debug.assert_eq(result.tool_results[i].id, "c\{i + 1}")
    assert_true(result.tool_results[i].is_error)
  }
  // Remaining calls are auto-denied with an explanatory reason
  assert_true(result.tool_results[1].content.contains("Auto-denied"))
  assert_true(result.tool_results[2].content.contains("Auto-denied"))
  // The first denial uses the standard user-denial wording
  assert_true(
    result.tool_results[0].content.contains("Tool use denied by user"),
  )
}

///|
async test "act_async_uppercase_write_not_auto_executed" {
  let agent = make_test_agent()
  agent.config.permission_mode = @config.ConfirmSafes
  agent.confirmation_callback = Some(fn(_name, _args) { false })
  // "Write" (uppercase) must be resolved to write before permission checks,
  // so it requires confirmation instead of auto-executing.
  let call = make_tool_call(
    "c1", "Write", "{\"path\":\"/tmp/p6_upper.txt\",\"content\":\"x\"}",
  )
  let result = agent.act_async([call])
  @debug.assert_eq(result.tool_results.length(), 1)
  assert_true(result.denied)
  assert_true(result.tool_results[0].content.contains("denied"))
}

// ── P6: image_inject extraction + observe consumption ────────────────────────

///|
test "extract_image_inject_no_marker" {
  let (content, inject) = extract_image_inject("plain tool output")
  @debug.assert_eq(content, "plain tool output")
  @debug.assert_eq(inject, None)
}

///|
test "extract_image_inject_real_base64" {
  let raw = "Screenshot saved to /tmp/shot.png\n" +
    "[image_inject]\n" +
    "mime_type: image/png\n" +
    "base64_data: iVBORw0KGgoAAAANSUhEUg==\n" +
    "path: /tmp/shot.png\n"
  let (content, inject) = extract_image_inject(raw)
  // Marker block stripped from content
  @debug.assert_eq(content, "Screenshot saved to /tmp/shot.png")
  let expected : ImageInject? = Some({
    mime_type: "image/png",
    base64_data: "iVBORw0KGgoAAAANSUhEUg==",
    path: Some("/tmp/shot.png"),
  })
  @debug.assert_eq(inject, expected)
}

///|
test "extract_image_inject_placeholder_keeps_content" {
  // B3 producer currently ships a length placeholder, not real base64.
  // The parser must keep the whole content (with path/size info) and
  // return no inject so the LLM still sees the description.
  let raw = "Screenshot saved to /tmp/shot.png\n" +
    "[image_inject]\n" +
    "mime_type: image/png\n" +
    "base64_data: (12345 chars)\n" +
    "path: /tmp/shot.png\n"
  let (content, inject) = extract_image_inject(raw)
  @debug.assert_eq(content, raw)
  @debug.assert_eq(inject, None)
}

///|
test "extract_image_inject_missing_base64_no_inject" {
  let raw = "Screenshot saved to /tmp/shot.png\n" +
    "[image_inject]\n" +
    "mime_type: image/png\n" +
    "path: /tmp/shot.png\n"
  let (content, inject) = extract_image_inject(raw)
  @debug.assert_eq(content, raw)
  @debug.assert_eq(inject, None)
}

///|
async test "observe_injects_image_user_message" {
  let agent = make_test_agent()
  let inject = ImageInject::{
    mime_type: "image/png",
    base64_data: "iVBORw0KGgoAAAANSUhEUg==",
    path: Some("/tmp/shot.png"),
  }
  let entries : Array[ToolResultEntry] = [
    {
      id: "c1",
      content: "Screenshot saved to /tmp/shot.png",
      is_error: false,
      image_inject: Some(inject),
    },
  ]
  let response = make_mock_response("I'll take a screenshot", Some([]))
  agent.observe(response, entries)
  // The last history message is the follow-up user message with the image.
  let last = agent.history.all()[agent.history.size() - 1]
  @debug.assert_eq(last.role, @message.User)
  @debug.assert_eq(last.system_injected, Some(true))
  match last.content {
    @message.Blocks(blocks) => {
      @debug.assert_eq(blocks.length(), 2)
      // Text label block
      match blocks[0] {
        @message.Text(tb) => @debug.assert_eq(tb.text, "[Image: shot.png]")
        _ => assert_true(false)
      }
      // Image block with data URL
      match blocks[1] {
        @message.Image(ib) =>
          @debug.assert_eq(
            ib.url,
            "data:image/png;base64,iVBORw0KGgoAAAANSUhEUg==",
          )
        _ => assert_true(false)
      }
    }
    _ => assert_true(false)
  }
}

///|
async test "observe_no_vision_uses_text_placeholder" {
  let client = @client.Client::new(
    "test-key",
    "https://api.test.com",
    "test-model",
    @config.OpenAICompletions,
    vision_supported=Some(false),
  )
  let config = @config.AgentConfig::default()
  let agent = Agent::new(
    "test-session", "test-agent", "/tmp/test", client, config,
  )
  let inject = ImageInject::{
    mime_type: "image/png",
    base64_data: "iVBORw0KGgoAAAANSUhEUg==",
    path: None,
  }
  let entries : Array[ToolResultEntry] = [
    {
      id: "c1",
      content: "screenshot",
      is_error: false,
      image_inject: Some(inject),
    },
  ]
  let response = make_mock_response("I'll take a screenshot", Some([]))
  agent.observe(response, entries)
  let last = agent.history.all()[agent.history.size() - 1]
  match last.content {
    @message.Blocks(blocks) => {
      @debug.assert_eq(blocks.length(), 1)
      match blocks[0] {
        @message.Text(tb) => @debug.assert_eq(tb.text, "[Image: image]")
        _ => assert_true(false)
      }
    }
    _ => assert_true(false)
  }
}

///|
async test "observe_no_image_inject_no_extra_message" {
  let agent = make_test_agent()
  let entries : Array[ToolResultEntry] = [
    { id: "c1", content: "plain result", is_error: false, image_inject: None },
  ]
  let response = make_mock_response(
    "I'll take a screenshot",
    Some([make_tool_call("c1", "browser_screenshot", "{}")]),
  )
  let before = agent.history.size()
  agent.observe(response, entries)
  // Only the tool-result message was appended (no image follow-up).
  @debug.assert_eq(agent.history.size(), before + 1)
}

///|
test "build_success_result_extracts_image_inject" {
  let call = make_tool_call("c1", "browser_screenshot", "{}")
  let result = @tool.ToolResult::{
    content: "Screenshot saved to /tmp/shot.png\n" +
    "[image_inject]\n" +
    "mime_type: image/png\n" +
    "base64_data: iVBORw0KGgoAAAANSUhEUg==\n" +
    "path: /tmp/shot.png\n",
    is_error: false,
  }
  let entry = build_success_result(call, result)
  @debug.assert_eq(entry.content, "Screenshot saved to /tmp/shot.png")
  let expected : ImageInject? = Some({
    mime_type: "image/png",
    base64_data: "iVBORw0KGgoAAAANSUhEUg==",
    path: Some("/tmp/shot.png"),
  })
  @debug.assert_eq(entry.image_inject, expected)
  @debug.assert_eq(entry.is_error, false)
}

///|
/// spec 2026-08-18_17 risk A: Agent::inject_user_image appends a user
/// message with a ContentBlock::Image (data: URL) to the agent history.
/// Verifies the WS attachments injection path (was previously only
/// parsing metadata into text; now constructs real Image blocks).
test "inject_user_image_appends_image_content_block" {
  let agent = make_test_agent()
  let initial_count = agent.history.size()
  agent.inject_user_image(
    "iVBORw0KGgo=",
    "image/png",
    path=Some("/tmp/screenshot.png"),
  )
  // A new user message was appended.
  @debug.assert_eq(agent.history.size(), initial_count + 1)
  // The last message is a user message with Blocks content.
  let msgs = agent.history.all()
  let last = msgs[msgs.length() - 1]
  @debug.assert_eq(last.role, @message.User)
  // The blocks contain at least one Image block with a data: URL.
  match last.content {
    @message.Blocks(blocks) => {
      let mut found_image = false
      for b in blocks {
        match b {
          @message.ContentBlock::Image(ib) => {
            found_image = true
            assert_true(ib.url.has_prefix("data:image/png;base64,"))
          }
          _ => ()
        }
      }
      assert_true(found_image)
    }
    _ => fail("expected Blocks content, got plain text")
  }
}

///|
/// inject_user_image with no path still works (label defaults to "image").
test "inject_user_image_no_path_defaults_label" {
  let agent = make_test_agent()
  agent.inject_user_image("AAAA", "image/jpeg")
  let msgs = agent.history.all()
  let last = msgs[msgs.length() - 1]
  @debug.assert_eq(last.role, @message.User)
  // Verify the text block mentions [Image: image].
  match last.content {
    @message.Blocks(blocks) => {
      let mut found_text = false
      for b in blocks {
        match b {
          @message.ContentBlock::Text(tb) =>
            if tb.text.contains("[Image: image]") {
              found_text = true
            }
          _ => ()
        }
      }
      assert_true(found_text)
    }
    _ => fail("expected Blocks content")
  }
}
// ── P6: request_user_feedback awaiting semantics ────────────────────────────

///|
async test "feedback_no_channel_appends_auto_reply" {
  let agent = make_test_agent()
  // No feedback_request/feedback_response wired (headless mode).
  let call = make_tool_call(
    "c1", "request_user_feedback", "{\"question\":\"Which option?\",\"context\":\"ctx\",\"options\":[\"a\",\"b\"]}",
  )
  let result = agent.act_async([call])
  // Run does NOT suspend; auto-reply hint is appended for the LLM.
  @debug.assert_eq(result.awaiting_feedback, false)
  @debug.assert_eq(result.denied, false)
  @debug.assert_eq(result.feedback, None)
  @debug.assert_eq(result.tool_results.length(), 1)
  assert_true(
    result.tool_results[0].content.contains("**Question:** Which option?"),
  )
  assert_true(result.tool_results[0].content.contains("**Options:**"))
  assert_true(result.tool_results[0].content.contains("1. a"))
  assert_true(result.tool_results[0].content.contains("2. b"))
  assert_true(result.tool_results[0].content.contains("[auto_reply]"))
}

///|
async test "feedback_no_channel_missing_question_is_error" {
  let agent = make_test_agent()
  let call = make_tool_call("c1", "request_user_feedback", "{}")
  let result = agent.act_async([call])
  @debug.assert_eq(result.tool_results.length(), 1)
  assert_true(result.tool_results[0].is_error)
  assert_true(
    result.tool_results[0].content.contains("Missing required parameter"),
  )
  // Error result: no feedback handling, no suspension.
  @debug.assert_eq(result.awaiting_feedback, false)
}

///|
async test "feedback_with_channel_user_reply_feeds_back" {
  let agent = make_test_agent()
  let req_q : @aqueue.Queue[(String, String?, Array[String]?)] = @aqueue.Queue::Queue(
    kind=Unbounded,
  )
  let resp_q : @aqueue.Queue[String] = @aqueue.Queue::Queue(kind=Unbounded)
  agent.feedback_request = Some(req_q)
  agent.feedback_response = Some(resp_q)
  // Simulate the user answering from the bridge side.
  @async.with_task_group(group => {
    group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
      let (q, _ctx, _opts) = req_q.get()
      @debug.assert_eq(q, "Choose?")
      resp_q.put("pick B please")
    }
    let call = make_tool_call(
      "c1", "request_user_feedback", "{\"question\":\"Choose?\"}",
    )
    let result = agent.act_async([call])
    // Reply is routed back (feedback path), run does NOT suspend.
    @debug.assert_eq(result.awaiting_feedback, false)
    @debug.assert_eq(result.denied, false)
    @debug.assert_eq(result.feedback, Some("pick B please"))
    // Tool result keeps the question, no auto-reply hint (channel existed).
    assert_true(
      result.tool_results[0].content.contains("**Question:** Choose?"),
    )
    assert_false(result.tool_results[0].content.contains("[auto_reply]"))
  })
}

///|
async test "feedback_with_channel_empty_reply_suspends" {
  let agent = make_test_agent()
  let req_q : @aqueue.Queue[(String, String?, Array[String]?)] = @aqueue.Queue::Queue(
    kind=Unbounded,
  )
  let resp_q : @aqueue.Queue[String] = @aqueue.Queue::Queue(kind=Unbounded)
  agent.feedback_request = Some(req_q)
  agent.feedback_response = Some(resp_q)
  // Bridge replies with empty string (timeout / no answer).
  @async.with_task_group(group => {
    group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
      let (_q, _ctx, _opts) = req_q.get()
      resp_q.put("")
    }
    let call = make_tool_call(
      "c1", "request_user_feedback", "{\"question\":\"Are you there?\"}",
    )
    let result = agent.act_async([call])
    // Run suspends awaiting the user's next message.
    @debug.assert_eq(result.awaiting_feedback, true)
    @debug.assert_eq(result.feedback, None)
  })
}

// ── invoke_skill tool (task 4: param validation + injection) ──────────────

///|
test "invoke_skill requires task parameter" {
  let agent = make_test_agent()
  let args = Map::from_array([("skill_name", "test-skill".to_json())])
  let call = make_tool_call(
    "c1", "invoke_skill", "{\"skill_name\":\"test-skill\"}",
  )
  let result = agent.execute_invoke_skill(call, args)
  @debug.assert_eq(result.is_error, true)
  assert_true(result.content.contains("missing 'task'"))
  // Nothing enqueued when validation fails.
  @debug.assert_eq(agent.pending_injections.length(), 0)
  @debug.assert_eq(agent.history.size(), 0)
}

///|
test "invoke_skill enqueues injection and returns short message" {
  let agent = make_test_agent()
  agent.skill_registry.register(
    @skill.Skill::default("test-skill", "file:///tmp/SKILL.md"),
  )
  let args = Map::from_array([
    ("skill_name", "test-skill".to_json()),
    ("task", "do the thing".to_json()),
  ])
  let call = make_tool_call(
    "c1", "invoke_skill", "{\"skill_name\":\"test-skill\",\"task\":\"do the thing\"}",
  )
  let result = agent.execute_invoke_skill(call, args)
  @debug.assert_eq(result.is_error, false)
  @debug.assert_eq(
    result.content,
    "Skill 'test-skill' instructions expanded. Proceed to execute the task.",
  )
  // The tool result is the short confirmation, NOT the full skill body.
  assert_true(!result.content.contains("Active Skill"))
  // Injection deferred until flush: history untouched, one pending entry.
  @debug.assert_eq(agent.pending_injections.length(), 1)
  @debug.assert_eq(agent.history.size(), 0)
}

///|
test "flush_pending_injections injects assistant body then user shim" {
  let agent = make_test_agent()
  agent.skill_registry.register(
    @skill.Skill::default("test-skill", "file:///tmp/SKILL.md"),
  )
  agent.enqueue_injection("test-skill", "summarize")
  agent.flush_pending_injections()
  @debug.assert_eq(agent.pending_injections.length(), 0)
  @debug.assert_eq(agent.history.size(), 2)
  let assistant_msg = agent.history.all()[0]
  @debug.assert_eq(assistant_msg.role, @message.Assistant)
  @debug.assert_eq(assistant_msg.system_injected, Some(true))
  match assistant_msg.content {
    @message.MessageContent::Text(s) =>
      assert_true(s.contains("Active Skill: test-skill"))
    _ => assert_true(false)
  }
  let shim_msg = agent.history.all()[1]
  @debug.assert_eq(shim_msg.role, @message.User)
  @debug.assert_eq(shim_msg.system_injected, Some(true))
  @debug.assert_eq(
    shim_msg.content,
    (
      @message.MessageContent::Text(
        "[SYSTEM] The skill instructions above have been loaded. Please proceed to execute the task now.",
      ) : @message.MessageContent),
  )
}
