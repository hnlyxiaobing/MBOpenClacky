///| White-box tests for LLM error detail recording (fix-09 hardening).

///|
fn lc_make_agent(base_url : String, provider_id? : String? = None) -> Agent {
  let client = @client.Client::new(
    "test-key",
    base_url,
    "test-model",
    @config.OpenAICompletions,
    provider_id~,
  )
  let config = @config.AgentConfig::default()
  Agent::new("test-session", "test-agent", "/tmp/test", client, config)
}

///|
test "record_llm_error maps HTTP 402 to insufficient_credit" {
  let agent = lc_make_agent("https://api.unknown.example.com")
  agent.record_llm_error(402, "{\"error\":{\"message\":\"quota exceeded\"}}")
  @debug.assert_eq(agent.error_code, Some("insufficient_credit"))
  // Unknown provider: no fabricated top-up link.
  @debug.assert_eq(agent.top_up_url, None)
  @debug.assert_eq(agent.raw_message, Some("quota exceeded"))
}

///|
test "record_llm_error uses provider preset website as top_up_url" {
  let agent = lc_make_agent("https://api.deepseek.com")
  agent.record_llm_error(
    403, "{\"error\":{\"code\":\"insufficient_credit\",\"message\":\"out of credit\"}}",
  )
  @debug.assert_eq(agent.error_code, Some("insufficient_credit"))
  @debug.assert_eq(
    agent.top_up_url,
    Some("https://platform.deepseek.com/api_keys"),
  )
}

///|
test "record_llm_error falls back to error.type for code" {
  let agent = lc_make_agent("https://api.anthropic.com")
  agent.record_llm_error(
    429, "{\"error\":{\"type\":\"rate_limit_error\",\"message\":\"slow down\"}}",
  )
  @debug.assert_eq(agent.error_code, Some("rate_limit_error"))
  // top_up_url is only meaningful for insufficient_credit.
  @debug.assert_eq(agent.top_up_url, None)
}

///|
test "record_llm_error prefers provider_id over base_url for top_up_url" {
  let agent = lc_make_agent(
    "https://proxy.example.com/v1",
    provider_id=Some("openrouter"),
  )
  agent.record_llm_error(402, "{\"error\":{\"message\":\"pay up\"}}")
  @debug.assert_eq(agent.error_code, Some("insufficient_credit"))
  @debug.assert_eq(agent.top_up_url, Some("https://openrouter.ai/keys"))
}

///|
test "clear_llm_error resets recorded error fields" {
  let agent = lc_make_agent("https://api.deepseek.com")
  agent.record_llm_error(402, "{\"error\":{\"message\":\"pay up\"}}")
  @debug.assert_eq(agent.error_code, Some("insufficient_credit"))
  agent.clear_llm_error()
  @debug.assert_eq(agent.error_code, None)
  @debug.assert_eq(agent.top_up_url, None)
  @debug.assert_eq(agent.raw_message, None)
}
