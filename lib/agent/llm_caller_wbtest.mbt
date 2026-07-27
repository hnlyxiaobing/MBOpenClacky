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

// ── Retry Delay Tests ────────────────────────────────────────────────────────

///|
test "retry_delay_ms exponential backoff" {
  // attempt 1: base delay = 5000
  @debug.assert_eq(retry_delay_ms(1), 5000)
  // attempt 2: 5000 * 2 = 10000
  @debug.assert_eq(retry_delay_ms(2), 10000)
  // attempt 3: 5000 * 4 = 20000
  @debug.assert_eq(retry_delay_ms(3), 20000)
  // attempt 4: 5000 * 8 = 40000
  @debug.assert_eq(retry_delay_ms(4), 40000)
  // attempt 5: 5000 * 16 = 80000 → capped at 60000
  @debug.assert_eq(retry_delay_ms(5), 60000)
  // attempt 10: still capped
  @debug.assert_eq(retry_delay_ms(10), 60000)
}

// ── Fallback State Machine Tests ─────────────────────────────────────────────

///|
test "record_retryable_failure increments counter in PrimaryOk" {
  let agent = lc_make_agent("https://api.example.com")
  @debug.assert_eq(agent.fallback_state, PrimaryOk)
  @debug.assert_eq(agent.consecutive_retryable_failures, 0)
  agent.record_retryable_failure()
  @debug.assert_eq(agent.consecutive_retryable_failures, 1)
  @debug.assert_eq(agent.fallback_state, PrimaryOk)
  agent.record_retryable_failure()
  @debug.assert_eq(agent.consecutive_retryable_failures, 2)
  @debug.assert_eq(agent.fallback_state, PrimaryOk)
}

///|
test "record_retryable_failure activates fallback after threshold" {
  let agent = lc_make_agent("https://api.example.com")
  agent.fallback_model = Some("fallback-model")
  // 3 consecutive failures should trigger fallback
  agent.record_retryable_failure()
  agent.record_retryable_failure()
  @debug.assert_eq(agent.fallback_state, PrimaryOk)
  agent.record_retryable_failure()
  assert_eq(agent.fallback_state, FallbackActive(0))
  assert_true(agent.fallback_activated_at_ms > 0L)
}

///|
test "record_retryable_failure no fallback without configured model" {
  let agent = lc_make_agent("https://api.example.com")
  // fallback_model is None by default
  agent.record_retryable_failure()
  agent.record_retryable_failure()
  agent.record_retryable_failure()
  // Should stay PrimaryOk because no fallback model configured
  @debug.assert_eq(agent.fallback_state, PrimaryOk)
  @debug.assert_eq(agent.consecutive_retryable_failures, 3)
}

///|
test "record_retryable_failure increments FallbackActive counter" {
  let agent = lc_make_agent("https://api.example.com")
  agent.fallback_state = FallbackActive(0)
  agent.record_retryable_failure()
  @debug.assert_eq(agent.fallback_state, FallbackActive(1))
  agent.record_retryable_failure()
  @debug.assert_eq(agent.fallback_state, FallbackActive(2))
}

///|
test "record_retryable_failure in Probing returns to FallbackActive" {
  let agent = lc_make_agent("https://api.example.com")
  agent.fallback_state = Probing
  agent.record_retryable_failure()
  @debug.assert_eq(agent.fallback_state, FallbackActive(0))
  assert_true(agent.fallback_activated_at_ms > 0L)
}

///|
test "record_llm_success resets counter and resolves Probing" {
  let agent = lc_make_agent("https://api.example.com")
  agent.consecutive_retryable_failures = 5
  agent.fallback_state = Probing
  agent.record_llm_success()
  @debug.assert_eq(agent.consecutive_retryable_failures, 0)
  @debug.assert_eq(agent.fallback_state, PrimaryOk)
}

///|
test "record_llm_success in PrimaryOk just resets counter" {
  let agent = lc_make_agent("https://api.example.com")
  agent.consecutive_retryable_failures = 2
  agent.fallback_state = PrimaryOk
  agent.record_llm_success()
  @debug.assert_eq(agent.consecutive_retryable_failures, 0)
  @debug.assert_eq(agent.fallback_state, PrimaryOk)
}

///|
test "check_fallback_cooldown transitions to Probing after expiry" {
  let agent = lc_make_agent("https://api.example.com")
  agent.fallback_state = FallbackActive(2)
  // Set activation time far in the past (beyond 1800s cooldown)
  agent.fallback_activated_at_ms = current_time_ms() - 2000L * 1000L
  agent.check_fallback_cooldown()
  @debug.assert_eq(agent.fallback_state, Probing)
}

///|
test "check_fallback_cooldown stays FallbackActive before expiry" {
  let agent = lc_make_agent("https://api.example.com")
  agent.fallback_state = FallbackActive(1)
  // Set activation time to now (cooldown not expired)
  agent.fallback_activated_at_ms = current_time_ms()
  agent.check_fallback_cooldown()
  @debug.assert_eq(agent.fallback_state, FallbackActive(1))
}

// ── Fallback Model Selection Tests ────────────────────────────────────────────

///|
test "build_send_request uses fallback model when FallbackActive" {
  let agent = lc_make_agent("https://api.example.com")
  agent.fallback_model = Some("fallback-model-id")
  agent.fallback_state = FallbackActive(0)
  let req = agent.build_send_request()
  @debug.assert_eq(req.model, "fallback-model-id")
}

///|
test "build_send_request uses primary model in PrimaryOk" {
  let agent = lc_make_agent("https://api.example.com")
  agent.fallback_model = Some("fallback-model-id")
  agent.fallback_state = PrimaryOk
  let req = agent.build_send_request()
  // Primary model should be used, not fallback
  @debug.assert_eq(req.model, agent.client.model)
}

///|
test "build_send_request uses primary model in Probing" {
  let agent = lc_make_agent("https://api.example.com")
  agent.fallback_model = Some("fallback-model-id")
  agent.fallback_state = Probing
  let req = agent.build_send_request()
  // Probing should test primary model, not fallback
  @debug.assert_eq(req.model, agent.client.model)
}

///|
test "build_send_request uses primary when fallback_model empty" {
  let agent = lc_make_agent("https://api.example.com")
  agent.fallback_model = Some("")
  agent.fallback_state = FallbackActive(0)
  let req = agent.build_send_request()
  @debug.assert_eq(req.model, agent.client.model)
}
