///| Unit tests for the billing module.

///|
test "BillingRecord new generates id and timestamp" {
  let record = BillingRecord::new(
    session_id="sess-001",
    model="claude-sonnet-4.5",
    prompt_tokens=1000,
    completion_tokens=500,
    cache_read_tokens=200,
    cache_write_tokens=100,
    cost_usd=0.015,
    cost_source="price",
  )
  // ID should not be empty
  assert_true(record.id.length() > 0)
  // Timestamp is Int64 (may be 0 in wasm-gc tests)
  assert_true(record.timestamp >= 0L)
  // Fields should match
  @debug.assert_eq(record.session_id, "sess-001")
  @debug.assert_eq(record.model, "claude-sonnet-4.5")
  @debug.assert_eq(record.prompt_tokens, 1000)
  @debug.assert_eq(record.completion_tokens, 500)
  @debug.assert_eq(record.cache_read_tokens, 200)
  @debug.assert_eq(record.cache_write_tokens, 100)
  @debug.assert_eq(record.cost_usd, 0.015)
  @debug.assert_eq(record.cost_source, "price")
}

///|
test "BillingRecord total_tokens" {
  let record : BillingRecord = {
    id: "test-1",
    session_id: "s1",
    timestamp: 1000L,
    model: "gpt-4",
    prompt_tokens: 800,
    completion_tokens: 200,
    cache_read_tokens: 0,
    cache_write_tokens: 0,
    cost_usd: 0.01,
    cost_source: "price",
  }
  @debug.assert_eq(record.total_tokens(), 1000)
}

///|
test "BillingRecord serialization roundtrip" {
  let record : BillingRecord = {
    id: "roundtrip-001",
    session_id: "sess-abc",
    timestamp: 1719100000000L,
    model: "claude-sonnet-4.5",
    prompt_tokens: 5000,
    completion_tokens: 1500,
    cache_read_tokens: 300,
    cache_write_tokens: 150,
    cost_usd: 0.0425,
    cost_source: "estimated",
  }
  let json = record.to_json()
  let json_str = json.stringify()
  let parsed = @json.parse(json_str)
  let restored : BillingRecord = @json.from_json(parsed)
  @debug.assert_eq(restored.id, record.id)
  @debug.assert_eq(restored.session_id, record.session_id)
  @debug.assert_eq(restored.timestamp, record.timestamp)
  @debug.assert_eq(restored.model, record.model)
  @debug.assert_eq(restored.prompt_tokens, record.prompt_tokens)
  @debug.assert_eq(restored.completion_tokens, record.completion_tokens)
  @debug.assert_eq(restored.cache_read_tokens, record.cache_read_tokens)
  @debug.assert_eq(restored.cache_write_tokens, record.cache_write_tokens)
  @debug.assert_eq(restored.cost_source, record.cost_source)
}

///|
test "filter_records filters by model" {
  let records = make_test_records()
  let filtered = filter_records(records, model="claude-sonnet-4.5")
  @debug.assert_eq(filtered.length(), 2)
  for r in filtered {
    @debug.assert_eq(r.model, "claude-sonnet-4.5")
  }
}

///|
test "filter_records filters by session" {
  let records = make_test_records()
  let filtered = filter_records(records, session_id="sess-002")
  @debug.assert_eq(filtered.length(), 2)
  for r in filtered {
    @debug.assert_eq(r.session_id, "sess-002")
  }
}

///|
test "filter_records filters by time range" {
  let records = make_test_records()
  // Only records with timestamp >= 2000 and <= 3000
  let filtered = filter_records(records, from_ms=2000L, to_ms=3000L)
  @debug.assert_eq(filtered.length(), 2)
}

///|
test "aggregate_summary computes totals" {
  let records = make_test_records()
  let summary = aggregate_summary(records, Month)
  @debug.assert_eq(summary.record_count, 4)
  @debug.assert_eq(summary.total_prompt_tokens, 4000) // 1000+1000+1000+1000
  @debug.assert_eq(summary.total_completion_tokens, 2000) // 500+500+500+500
  assert_true(summary.period == Month)
  // by_model should have 2 entries
  assert_true(summary.by_model.get("claude-sonnet-4.5") is Some(_))
  assert_true(summary.by_model.get("gpt-4o") is Some(_))
}

///|
test "aggregate_summary by_model breakdown" {
  let records = make_test_records()
  let summary = aggregate_summary(records, All)
  let claude = summary.by_model.get("claude-sonnet-4.5").unwrap()
  @debug.assert_eq(claude.requests, 2)
  @debug.assert_eq(claude.prompt_tokens, 2000)
  @debug.assert_eq(claude.completion_tokens, 1000)
  let gpt = summary.by_model.get("gpt-4o").unwrap()
  @debug.assert_eq(gpt.requests, 2)
  @debug.assert_eq(gpt.prompt_tokens, 2000)
  @debug.assert_eq(gpt.completion_tokens, 1000)
}

///|
test "TimePeriod enum values" {
  let periods : Array[TimePeriod] = [Day, Week, Month, Year, All]
  @debug.assert_eq(periods.length(), 5)
  assert_true(Day != Week)
  assert_true(Month != Year)
  assert_true(All != Day)
}

///|
test "filter_records with no filters returns all" {
  let records = make_test_records()
  let filtered = filter_records(records)
  @debug.assert_eq(filtered.length(), records.length())
}

///|
test "aggregate_summary empty records" {
  let records : Array[BillingRecord] = []
  let summary = aggregate_summary(records, Day)
  @debug.assert_eq(summary.record_count, 0)
  @debug.assert_eq(summary.total_cost, 0.0)
  @debug.assert_eq(summary.total_prompt_tokens, 0)
  @debug.assert_eq(summary.total_completion_tokens, 0)
}

// ── Test Helpers ────────────────────────────────────────────────

///|
/// Create a set of test records for filtering/aggregation tests.
fn make_test_records() -> Array[BillingRecord] {
  [
    {
      id: "rec-1",
      session_id: "sess-001",
      timestamp: 1000L,
      model: "claude-sonnet-4.5",
      prompt_tokens: 1000,
      completion_tokens: 500,
      cache_read_tokens: 100,
      cache_write_tokens: 50,
      cost_usd: 0.01,
      cost_source: "price",
    },
    {
      id: "rec-2",
      session_id: "sess-001",
      timestamp: 2000L,
      model: "gpt-4o",
      prompt_tokens: 1000,
      completion_tokens: 500,
      cache_read_tokens: 0,
      cache_write_tokens: 0,
      cost_usd: 0.02,
      cost_source: "price",
    },
    {
      id: "rec-3",
      session_id: "sess-002",
      timestamp: 3000L,
      model: "claude-sonnet-4.5",
      prompt_tokens: 1000,
      completion_tokens: 500,
      cache_read_tokens: 200,
      cache_write_tokens: 100,
      cost_usd: 0.015,
      cost_source: "estimated",
    },
    {
      id: "rec-4",
      session_id: "sess-002",
      timestamp: 4000L,
      model: "gpt-4o",
      prompt_tokens: 1000,
      completion_tokens: 500,
      cache_read_tokens: 0,
      cache_write_tokens: 0,
      cost_usd: 0.025,
      cost_source: "api",
    },
  ]
}
