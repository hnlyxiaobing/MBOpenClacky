///|
/// Unit tests for slash command semantics aligned in SPEC-02 task package 1:
/// with-arg /model (match by id or name, switch + default badge, overlay
/// cleared) and the persistence round trip of the default model.

///|
/// Build an agent whose config has two model cards (m1 current, m2 standby).
fn make_cmd_agent() -> @agent.Agent {
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
  @agent.Agent::new("s1", "test-agent", "/tmp/test", client, config)
}

///|
test "/model <id> switches current model, sets default badge, clears overlay" {
  let agent = make_cmd_agent()
  agent.set_session_sub_model(Some("sub-x"))
  let result = execute(SlashCommand::Model(name="m2"), agent)
  assert_eq(result, Ok("Model switched to: model-two"))
  assert_eq(agent.config.current_model_id, Some("m2"))
  // The default badge follows the switch (persisted as the launch default).
  match agent.config.current_model() {
    Some(m) => assert_eq(m.id, "m2")
    None => abort("expected a current model")
  }
  // Client hot-swapped; sub-model overlay cleared.
  assert_eq(agent.client.model, "model-two")
  assert_eq(agent.session_sub_model, None)
}

///|
test "/model <model-name> also matches a configured card" {
  let agent = make_cmd_agent()
  let result = execute(SlashCommand::Model(name="model-two"), agent)
  assert_eq(result, Ok("Model switched to: model-two"))
  assert_eq(agent.config.current_model_id, Some("m2"))
}

///|
test "/model <unknown> reports an error and keeps the current model" {
  let agent = make_cmd_agent()
  let result = execute(SlashCommand::Model(name="no-such-model"), agent)
  assert_true(result is Err(_))
  assert_eq(agent.config.current_model_id, Some("m1"))
  assert_eq(agent.client.model, "model-one")
}

///|
/// Build a temp-file path that works on both Windows (%TEMP%) and Unix.
fn test_temp_path(name : String) -> String {
  let dir = match @utils.env_var("TEMP") {
    Some(d) => d
    None =>
      match @utils.env_var("TMPDIR") {
        Some(d) => d
        None => "/tmp"
      }
  }
  let sep = if dir.has_suffix("/") || dir.has_suffix("\\") { "" } else { "/" }
  dir + sep + name
}

///|
test "default model change survives a config save/load round trip" {
  let agent = make_cmd_agent()
  ignore(execute(SlashCommand::Model(name="m2"), agent))
  let path = test_temp_path("specc2_model_persist.toml")
  agent.config.save(path) |> ignore
  let reloaded = @config.AgentConfig::load(path) catch {
    _ => abort("reload failed")
  }
  // p6: card ids are runtime-only (stripped on save, re-injected as
  // positional ids on load), so current_model_id after reload is a fresh
  // id and must not be compared literally. What must survive is the
  // selection: the default badge lands on the model-two card and
  // current_model() resolves to it.
  assert_true(reloaded.current_model_id is Some(_))
  match reloaded.current_model() {
    Some(m) => {
      assert_eq(m.model, "model-two")
      assert_eq(m.type_, Some("default"))
    }
    None => abort("expected a current model after reload")
  }
}

///|
test "/clear resets the agent session in place" {
  let agent = make_cmd_agent()
  agent.iterations = 5
  agent.total_cost = 0.5
  let result = execute(SlashCommand::Clear, agent)
  assert_eq(result, Ok("Session cleared. Starting fresh."))
  assert_true(agent.session_id != "s1")
  assert_eq(agent.iterations, 0)
  assert_eq(agent.total_cost, 0.0)
  assert_eq(agent.idle_timer.state, @agent.TimerState::Idle)
}
