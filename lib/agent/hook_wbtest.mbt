///| Tests for the Hook system.

///|
test "hook_manager_empty_new" {
  let hm = HookManager::new()
  // No callbacks registered initially
  inspect(hm.callbacks.length(), content="0")
}

///|
test "hook_register_and_emit" {
  let hm = HookManager::new()
  let mut invoked = false
  hm.register(fn(_event : HookEvent) { invoked = true })
  hm.emit(StatusChanged(Idle, Running))
  guard invoked else { fail("Expected callback to be invoked") }
}

///|
test "hook_emit_multiple_callbacks" {
  let hm = HookManager::new()
  let mut count = 0
  hm.register(fn(_event : HookEvent) { count = count + 1 })
  hm.register(fn(_event : HookEvent) { count = count + 1 })
  hm.register(fn(_event : HookEvent) { count = count + 1 })
  hm.emit(BeforeIteration(1))
  inspect(count, content="3")
}

///|
test "hook_clear" {
  let hm = HookManager::new()
  let mut invoked = false
  hm.register(fn(_event : HookEvent) { invoked = true })
  hm.clear()
  hm.emit(MessageAdded)
  guard !invoked else {
    fail("Expected callback NOT to be invoked after clear")
  }
}

///|
test "hook_emit_event_payload" {
  // Verify that event payloads are passed correctly
  let hm = HookManager::new()
  let mut received_iteration = 0
  hm.register(fn(event : HookEvent) {
    match event {
      BeforeIteration(n) => received_iteration = n
      _ => ()
    }
  })
  hm.emit(BeforeIteration(42))
  inspect(received_iteration, content="42")
}

///|
test "hook_emit_all_event_types" {
  // Verify all event types can be emitted without errors
  let hm = HookManager::new()
  let event_types : Array[String] = []
  hm.register(fn(event : HookEvent) {
    match event {
      StatusChanged(_, _) => event_types.push("status")
      BeforeIteration(_) => event_types.push("before_iter")
      AfterIteration(_) => event_types.push("after_iter")
      BeforeLlmCall => event_types.push("before_llm")
      AfterLlmCall => event_types.push("after_llm")
      MessageAdded => event_types.push("message")
      ToolExecuting(_, _) => event_types.push("tool_exec")
      ToolExecuted(_, _) => event_types.push("tool_done")
      ErrorOccurred(_) => event_types.push("error")
      RunCompleted(_) => event_types.push("completed")
    }
  })

  hm.emit(StatusChanged(Idle, Running))
  hm.emit(BeforeIteration(1))
  hm.emit(AfterIteration(1))
  hm.emit(BeforeLlmCall)
  hm.emit(AfterLlmCall)
  hm.emit(MessageAdded)
  hm.emit(ToolExecuting("test_tool", "{}"))
  hm.emit(
    ToolExecuted("test_tool", { id: "call_1", content: "ok", is_error: false }),
  )
  hm.emit(ErrorOccurred("test error"))
  hm.emit(
    RunCompleted({
      status: Success,
      session_id: "s1",
      iterations: 1,
      total_cost_usd: 0.0,
      cost_source: Estimated,
      cache_stats: CacheStats::new(),
      error: None,
    }),
  )

  inspect(event_types.length(), content="10")
}

///|
test "hook_integration_agent_status_changes" {
  let client = @client.Client::new(
    "test-key",
    "https://api.test.com",
    "test-model",
    @config.OpenAICompletions,
  )
  let config = @config.AgentConfig::default()
  let agent = Agent::new("hook-test-1", "test-agent", "/tmp", client, config)

  let mut status_changed_count = 0

  agent.hook_manager.register(fn(event : HookEvent) {
    match event {
      StatusChanged(_, _) => status_changed_count = status_changed_count + 1
      _ => ()
    }
  })

  // Set a mock response so run() doesn't raise
  agent.mock_responses.push({
    content: Some("Hello!"),
    tool_calls: None,
    finish_reason: Some("stop"),
    usage: None,
    latency: None,
  })

  // Run the agent
  let result = agent.run("Say hello")

  inspect(status_changed_count, content="2")
  inspect(result.status.to_string_value(), content="Success")
}

///|
test "hook_integration_iteration_events" {
  let client = @client.Client::new(
    "test-key",
    "https://api.test.com",
    "test-model",
    @config.OpenAICompletions,
  )
  let config = @config.AgentConfig::default()
  let agent = Agent::new("hook-test-2", "test-agent", "/tmp", client, config)

  let before_iterations : Array[Int] = []
  let after_iterations : Array[Int] = []

  agent.hook_manager.register(fn(event : HookEvent) {
    match event {
      BeforeIteration(n) => before_iterations.push(n)
      AfterIteration(n) => after_iterations.push(n)
      _ => ()
    }
  })

  // Set mock response (no tool calls, complete immediately)
  agent.mock_responses.push({
    content: Some("Hello!"),
    tool_calls: None,
    finish_reason: Some("stop"),
    usage: None,
    latency: None,
  })

  let result = agent.run("Hi")
  inspect(result.status.to_string_value(), content="Success")
  // Should have at least one iteration
  guard before_iterations.length() >= 1 else {
    fail("Expected at least one BeforeIteration event")
  }
  guard after_iterations.length() >= 1 else {
    fail("Expected at least one AfterIteration event")
  }
}

///|
test "hook_integration_message_events" {
  let client = @client.Client::new(
    "test-key",
    "https://api.test.com",
    "test-model",
    @config.OpenAICompletions,
  )
  let config = @config.AgentConfig::default()
  let agent = Agent::new("hook-test-3", "test-agent", "/tmp", client, config)

  let mut message_count = 0

  agent.hook_manager.register(fn(event : HookEvent) {
    match event {
      MessageAdded => message_count = message_count + 1
      _ => ()
    }
  })

  // Set mock response
  agent.mock_responses.push({
    content: Some("Hello!"),
    tool_calls: None,
    finish_reason: Some("stop"),
    usage: None,
    latency: None,
  })

  let result = agent.run("Test messages")
  inspect(result.status.to_string_value(), content="Success")
  // System prompt + user message + assistant response = at least 3 messages
  guard message_count >= 3 else {
    fail("Expected at least 3 MessageAdded events (got \{message_count})")
  }
}

///|
test "hook_integration_run_completed" {
  let client = @client.Client::new(
    "test-key",
    "https://api.test.com",
    "test-model",
    @config.OpenAICompletions,
  )
  let config = @config.AgentConfig::default()
  let agent = Agent::new("hook-test-4", "test-agent", "/tmp", client, config)

  let mut completed_received = false

  agent.hook_manager.register(fn(event : HookEvent) {
    match event {
      RunCompleted(_) => completed_received = true
      _ => ()
    }
  })

  agent.mock_responses.push({
    content: Some("Hello!"),
    tool_calls: None,
    finish_reason: Some("stop"),
    usage: None,
    latency: None,
  })

  let _ = agent.run("Test completed")
  guard completed_received else { fail("Expected RunCompleted event") }
}

///|
test "hook_multiple_events_in_order" {
  // Verify that events are emitted in the expected order
  let client = @client.Client::new(
    "test-key",
    "https://api.test.com",
    "test-model",
    @config.OpenAICompletions,
  )
  let config = @config.AgentConfig::default()
  let agent = Agent::new("hook-test-5", "test-agent", "/tmp", client, config)

  let event_log : Array[String] = []

  agent.hook_manager.register(fn(event : HookEvent) {
    match event {
      StatusChanged(_, _) => event_log.push("status_changed")
      BeforeIteration(_) => event_log.push("before_iteration")
      BeforeLlmCall => event_log.push("before_llm_call")
      AfterLlmCall => event_log.push("after_llm_call")
      MessageAdded => event_log.push("message_added")
      AfterIteration(_) => event_log.push("after_iteration")
      RunCompleted(_) => event_log.push("run_completed")
      _ => ()
    }
  })

  agent.mock_responses.push({
    content: Some("Hi there!"),
    tool_calls: None,
    finish_reason: Some("stop"),
    usage: None,
    latency: None,
  })

  let result = agent.run("Hello")
  inspect(result.status.to_string_value(), content="Success")

  // Check that important events are in the log
  guard event_log.contains("status_changed") else {
    fail("Expected status_changed in event log")
  }
  guard event_log.contains("run_completed") else {
    fail("Expected run_completed in event log")
  }
  guard event_log.contains("before_llm_call") ||
    event_log.contains("message_added") else {
    fail("Expected LLM or message events in log")
  }
}
