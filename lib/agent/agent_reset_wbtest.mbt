///|
/// Unit tests for Agent::reset_session (/clear new-session semantics) and
/// the per-session sub-model overlay (SPEC-02 task package 1).

///|
/// Build an agent whose config has two model cards (m1 current, m2 standby).
fn make_two_model_agent() -> (Agent, @config.AgentConfig) {
  let client = @client.Client::new(
    "key1",
    "https://api.one.com/v1",
    "model-one",
    @config.OpenAICompletions,
  )
  let config = @config.AgentConfig::default()
  config.models = [
    @config.ModelConfig::new(
      "m1", "key1", "https://api.one.com/v1", "model-one",
    ),
    @config.ModelConfig::new(
      "m2", "key2", "https://api.two.com/v1", "model-two",
    ),
  ]
  config.current_model_id = Some("m1")
  let agent = Agent::new("s_old", "test-agent", "/tmp/test", client, config)
  (agent, config)
}

///|
test "reset_session assigns a new session_id and clears conversation state" {
  let (agent, _) = make_two_model_agent()
  agent.history.append(@message.Message::user("hello"))
  agent.iterations = 7
  agent.total_cost = 1.23
  agent.total_tasks = 3
  agent.reset_session()
  assert_true(agent.session_id != "s_old")
  assert_true(agent.session_id.length() > 0)
  assert_eq(agent.history.size(), 0)
  assert_eq(agent.iterations, 0)
  assert_eq(agent.total_cost, 0.0)
  assert_eq(agent.total_tasks, 0)
  assert_eq(agent.todo_manager.size(), 0)
}

///|
test "reset_session rebuilds the client from the CURRENT config" {
  let (agent, config) = make_two_model_agent()
  // Simulate a /config model switch made during the session.
  ignore(config.switch_model_by_id("m2"))
  agent.reset_session()
  // The client must be rebuilt from the current config (m2), never reused.
  assert_eq(agent.client.model, "model-two")
  assert_eq(agent.client.api_key, "key2")
  assert_eq(agent.client.base_url, "https://api.two.com/v1")
}

///|
test "reset_session rebinds a fresh idle timer" {
  let (agent, _) = make_two_model_agent()
  // Old timer is actively counting down.
  agent.idle_timer.start(1000)
  assert_true(agent.idle_timer.active())
  agent.reset_session()
  // The rebound timer is a fresh instance: not counting, not cancelled.
  assert_true(!agent.idle_timer.active())
  assert_eq(agent.idle_timer.state, TimerState::Idle)
}

///|
test "reset_session clears the sub-model overlay" {
  let (agent, _) = make_two_model_agent()
  agent.set_session_sub_model(Some("sub-x"))
  agent.reset_session()
  assert_eq(agent.session_sub_model, None)
  assert_eq(agent.effective_primary_model(), agent.client.model)
}

///|
test "sub_model overlay applies when building requests" {
  let (agent, _) = make_two_model_agent()
  // No overlay: config model is used.
  assert_eq(agent.build_send_request().model, "model-one")
  // Overlay set: replaces the config model in the request.
  agent.set_session_sub_model(Some("sub-model-x"))
  assert_eq(agent.build_send_request().model, "sub-model-x")
  // Overlay cleared: back to the config model.
  agent.set_session_sub_model(None)
  assert_eq(agent.build_send_request().model, "model-one")
}

///|
test "fallback model takes precedence over the sub-model overlay" {
  let (agent, _) = make_two_model_agent()
  agent.set_session_sub_model(Some("sub-model-x"))
  agent.fallback_state = FallbackActive(1)
  agent.fallback_model = Some("fallback-y")
  assert_eq(agent.build_send_request().model, "fallback-y")
}

///|
test "sub_model overlay round-trips through SessionData" {
  let (agent, _) = make_two_model_agent()
  agent.set_session_sub_model(Some("sub-model-x"))
  let data = agent.to_session_data()
  assert_eq(data.sub_model, Some("sub-model-x"))
  let (agent2, _) = make_two_model_agent()
  agent2.restore_from_session(data)
  assert_eq(agent2.session_sub_model, Some("sub-model-x"))
  assert_eq(agent2.build_send_request().model, "sub-model-x")
}

///|
test "rebuild_client_from_config re-derives api_type from the new card" {
  // Card m2 is Anthropic-protocol; the current client is OpenAI-protocol.
  let client = @client.Client::new(
    "key1",
    "https://api.one.com/v1",
    "model-one",
    @config.OpenAICompletions,
  )
  let config = @config.AgentConfig::default()
  let claude = @config.ModelConfig::new(
    "m2", "key2", "https://api.anthropic.com", "claude-x",
  )
  claude.anthropic_format = true
  config.models = [
    @config.ModelConfig::new(
      "m1", "key1", "https://api.one.com/v1", "model-one",
    ),
    claude,
  ]
  config.current_model_id = Some("m1")
  let agent = Agent::new("s1", "test-agent", "/tmp/test", client, config)
  ignore(agent.config.switch_model_by_id("m2"))
  agent.rebuild_client_from_config()
  // Cross-protocol switch must re-derive api_type — carrying over the old
  // OpenAI api_type would send OpenAI-shaped requests to Anthropic.
  assert_true(agent.client.is_anthropic_format())
  assert_eq(agent.client.model, "claude-x")
}
