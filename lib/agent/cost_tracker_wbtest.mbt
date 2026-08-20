///|
/// White-box tests for cost tracking (Spec 21 task package 1):
/// cost source priority (api > price > estimated), delta-token guards,
/// single-write billing persistence and subagent skip.

///|
/// Hermetic billing store under _build (never touches the user profile).
fn ct_make_billing_store(tag : String) -> @billing.BillingStore {
  let dir = "_build/ct_billing_\{tag}_\{@env.now().reinterpret_as_int64()}"
  @billing.BillingStore::new(dir)
}

///|
/// Agent wired to a hermetic billing store instead of the default one.
fn ct_make_agent(model : String) -> Agent {
  let client = @client.Client::new(
    "test-key",
    "https://api.test.com",
    model,
    @config.OpenAICompletions,
  )
  let config = @config.AgentConfig::default()
  let agent = Agent::new("ct-session", "ct-agent", "/tmp/test", client, config)
  agent.billing_store = ct_make_billing_store(model)
  agent
}

///|
/// Cumulative (OpenAI-style) usage literal.
fn ct_usage(
  input : Int,
  output : Int,
  api_cost? : Double? = None,
) -> @client.Usage {
  {
    input_tokens: input,
    output_tokens: output,
    cache_creation_input_tokens: 0,
    cache_read_input_tokens: 0,
    total_tokens: input + output,
    api_cost,
    total_is_per_turn: false,
  }
}

// ── Cost source priority: api > price > estimated ───────────────────────────

///|
test "track_cost api_cost wins over pricing table" {
  let agent = ct_make_agent("claude-sonnet-4.5")
  let data = agent.track_cost(ct_usage(1000, 500, api_cost=Some(0.123)))
  @debug.assert_eq(data.cost_source, Api)
  @debug.assert_eq(data.cost, 0.123)
  @debug.assert_eq(agent.cost_source, Api)
  @debug.assert_eq(agent.total_cost, 0.123)
}

///|
test "track_cost falls back to pricing table" {
  let agent = ct_make_agent("claude-sonnet-4.5")
  let data = agent.track_cost(ct_usage(1000, 500))
  @debug.assert_eq(data.cost_source, Price)
  assert_true(data.cost > 0.0)
  @debug.assert_eq(agent.total_cost, data.cost)
}

///|
test "track_cost unknown model estimates zero" {
  let agent = ct_make_agent("totally-unknown-model-xyz")
  let data = agent.track_cost(ct_usage(1000, 500))
  @debug.assert_eq(data.cost_source, Estimated)
  @debug.assert_eq(data.cost, 0.0)
}

// ── Delta-token guards ──────────────────────────────────────────────────────

///|
test "track_cost cumulative delta and negative guard" {
  let agent = ct_make_agent("totally-unknown-model-xyz")
  // First call establishes the baseline: delta == total.
  let d1 = agent.track_cost(ct_usage(100, 100))
  @debug.assert_eq(d1.delta_tokens, 200)
  // Cumulative grows: delta = 300 - 200.
  let d2 = agent.track_cost(ct_usage(180, 120))
  @debug.assert_eq(d2.delta_tokens, 100)
  // Cumulative shrinks (usage fallback): negative delta clamped to 0.
  let d3 = agent.track_cost(ct_usage(30, 20))
  @debug.assert_eq(d3.delta_tokens, 0)
  // Baseline still holds the previous maximum (50): 150 - 50.
  let d4 = agent.track_cost(ct_usage(90, 60))
  @debug.assert_eq(d4.delta_tokens, 100)
}

///|
test "track_cost zero usage does not reset baseline" {
  let agent = ct_make_agent("totally-unknown-model-xyz")
  let _ = agent.track_cost(ct_usage(100, 50))
  // Upstream returns zero usage — baseline must NOT be poisoned to 0.
  let d_zero = agent.track_cost(ct_usage(0, 0))
  @debug.assert_eq(d_zero.delta_tokens, 0)
  let d_next = agent.track_cost(ct_usage(120, 80))
  @debug.assert_eq(d_next.delta_tokens, 200 - 150)
}

///|
test "track_cost per-turn total is the delta" {
  let agent = ct_make_agent("totally-unknown-model-xyz")
  let _ = agent.track_cost(ct_usage(500, 500))
  // Anthropic per-turn convention: total IS the new compute; it must not
  // be subtracted from the previous cumulative baseline.
  let per_turn : @client.Usage = {
    input_tokens: 60,
    output_tokens: 40,
    cache_creation_input_tokens: 0,
    cache_read_input_tokens: 0,
    total_tokens: 100,
    api_cost: None,
    total_is_per_turn: true,
  }
  let data = agent.track_cost(per_turn)
  @debug.assert_eq(data.delta_tokens, 100)
}

// ── Billing persistence: single write point ─────────────────────────────────

///|
test "track_cost writes exactly one billing record per call" {
  let agent = ct_make_agent("claude-sonnet-4.5")
  let _ = agent.track_cost(ct_usage(100, 50, api_cost=Some(0.01)))
  let _ = agent.track_cost(ct_usage(200, 100))
  let records = agent.billing_store.query(session_id="ct-session")
  @debug.assert_eq(records.length(), 2)
  // Order is timestamp-sorted (unstable within the same millisecond),
  // so locate the records by their cost source instead.
  let mut api_rec : @billing.BillingRecord? = None
  let mut price_rec : @billing.BillingRecord? = None
  for r in records {
    if r.cost_source == "api" {
      api_rec = Some(r)
    }
    if r.cost_source == "price" {
      price_rec = Some(r)
    }
  }
  match (api_rec, price_rec) {
    (Some(a), Some(p)) => {
      @debug.assert_eq(a.cost_usd, 0.01)
      @debug.assert_eq(p.model, "claude-sonnet-4.5")
      @debug.assert_eq(p.prompt_tokens, 200)
    }
    _ => assert_true(false)
  }
}

///|
test "track_cost subagent skips billing persistence" {
  let agent = ct_make_agent("claude-sonnet-4.5")
  agent.is_subagent = true
  let data = agent.track_cost(ct_usage(100, 50, api_cost=Some(0.02)))
  // Cost still accumulates for the session view…
  @debug.assert_eq(agent.total_cost, 0.02)
  @debug.assert_eq(data.cost, 0.02)
  // …but no record is persisted (parent absorbs the spend).
  let records = agent.billing_store.query()
  @debug.assert_eq(records.length(), 0)
}
