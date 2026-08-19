///| Extended agent tests: cost source, cache stats, token estimation, agent pool.

// ── CostSource Tests ────────────────────────────────────────────────────────

///|
test "ext_cost_source_to_string" {
  assert_eq(CostSource::Api.to_string_value(), "api")
  assert_eq(CostSource::Price.to_string_value(), "price")
  assert_eq(CostSource::Default.to_string_value(), "default")
  assert_eq(CostSource::Estimated.to_string_value(), "estimated")
}

///|
test "ext_cost_source_equality" {
  assert_true(CostSource::Api == CostSource::Api)
  assert_true(CostSource::Price != CostSource::Default)
}

///|
test "ext_cost_source_to_json" {
  match CostSource::Api.to_json() {
    String(s) => assert_eq(s, "api")
    _ => assert_true(false)
  }
  match CostSource::Price.to_json() {
    String(s) => assert_eq(s, "price")
    _ => assert_true(false)
  }
}

// ── CacheStats Tests ────────────────────────────────────────────────────────

///|
test "ext_cache_stats_new_zero" {
  let cs = CacheStats::new()
  assert_eq(cs.cache_creation_input_tokens, 0)
  assert_eq(cs.cache_read_input_tokens, 0)
  assert_eq(cs.total_requests, 0)
  assert_eq(cs.cache_hit_requests, 0)
}

///|
test "ext_cache_stats_mutable" {
  let cs = CacheStats::new()
  cs.cache_creation_input_tokens = 100
  cs.cache_read_input_tokens = 200
  cs.total_requests = 5
  cs.cache_hit_requests = 3
  assert_eq(cs.cache_creation_input_tokens, 100)
  assert_eq(cs.cache_read_input_tokens, 200)
  assert_eq(cs.total_requests, 5)
  assert_eq(cs.cache_hit_requests, 3)
}

// ── estimate_token_count Tests ───────────────────────────────────────────────

///|
test "ext_estimate_tokens_empty" {
  assert_eq(estimate_token_count(""), 0)
}

///|
test "ext_estimate_tokens_short" {
  // "hello" = 5 chars => (5+3)/4 = 2
  assert_eq(estimate_token_count("hello"), 2)
}

///|
test "ext_estimate_tokens_exact_multiple" {
  // 8 chars => (8+3)/4 = 2
  assert_eq(estimate_token_count("12345678"), 2)
}

///|
test "ext_estimate_tokens_long" {
  // 9 chars => (9+3)/4 = 3
  assert_eq(estimate_token_count("123456789"), 3)
}

///|
test "ext_estimate_tokens_single_char" {
  // 1 char => (1+3)/4 = 1
  assert_eq(estimate_token_count("a"), 1)
}

// ── IterationTokenData Tests ─────────────────────────────────────────────────

///|
test "ext_iteration_token_data_construction" {
  let data : IterationTokenData = {
    delta_tokens: 100,
    prompt_tokens: 50,
    completion_tokens: 50,
    total_tokens: 100,
    cache_write: 10,
    cache_read: 5,
    cost: 0.005,
    cost_source: CostSource::Price,
  }
  assert_eq(data.delta_tokens, 100)
  assert_eq(data.prompt_tokens, 50)
  assert_eq(data.completion_tokens, 50)
  assert_eq(data.total_tokens, 100)
  assert_eq(data.cache_write, 10)
  assert_eq(data.cache_read, 5)
  assert_true(data.cost_source == CostSource::Price)
}

///|
test "ext_iteration_token_data_equality" {
  let d1 : IterationTokenData = {
    delta_tokens: 10,
    prompt_tokens: 5,
    completion_tokens: 5,
    total_tokens: 10,
    cache_write: 0,
    cache_read: 0,
    cost: 0.0,
    cost_source: CostSource::Estimated,
  }
  let d2 : IterationTokenData = {
    delta_tokens: 10,
    prompt_tokens: 5,
    completion_tokens: 5,
    total_tokens: 10,
    cache_write: 0,
    cache_read: 0,
    cost: 0.0,
    cost_source: CostSource::Estimated,
  }
  assert_true(d1 == d2)
}

// ── Additional CostSource Tests ──────────────────────────────────────────────

///|
test "ext_cost_source_all_variants_distinct" {
  let sources = [Api, Price, Default, Estimated]
  assert_eq(sources.length(), 4)
  assert_true(Api != Price)
  assert_true(Price != Default)
  assert_true(Default != Estimated)
}

///|
test "ext_cost_source_to_json_all" {
  for s in [Api, Price, Default, Estimated] {
    match s.to_json() {
      String(_) => assert_true(true)
      _ => assert_true(false)
    }
  }
}

// ── Additional CacheStats Tests ──────────────────────────────────────────────

///|
test "ext_cache_stats_increment" {
  let cs = CacheStats::new()
  cs.total_requests = 1
  cs.cache_hit_requests = 1
  assert_eq(cs.total_requests, 1)
  assert_eq(cs.cache_hit_requests, 1)
}

///|
test "ext_cache_stats_large_values" {
  let cs = CacheStats::new()
  cs.cache_creation_input_tokens = 1000000
  cs.cache_read_input_tokens = 500000
  cs.total_requests = 1000
  cs.cache_hit_requests = 800
  assert_eq(cs.cache_creation_input_tokens, 1000000)
  assert_eq(cs.cache_read_input_tokens, 500000)
}

// ── Additional estimate_token_count Tests ─────────────────────────────────────

///|
test "ext_estimate_tokens_long_text" {
  let text = "a".repeat(100)
  let tokens = estimate_token_count(text)
  assert_eq(tokens, (100 + 3) / 4)
}

///|
test "ext_estimate_tokens_unicode" {
  let tokens = estimate_token_count("你好世界")
  assert_true(tokens > 0)
}

// ── IterationTokenData Tests ─────────────────────────────────────────────────

///|
test "ext_iteration_token_data_different_values" {
  let d1 : IterationTokenData = {
    delta_tokens: 10,
    prompt_tokens: 5,
    completion_tokens: 5,
    total_tokens: 10,
    cache_write: 0,
    cache_read: 0,
    cost: 0.0,
    cost_source: CostSource::Estimated,
  }
  let d2 : IterationTokenData = {
    delta_tokens: 20,
    prompt_tokens: 10,
    completion_tokens: 10,
    total_tokens: 20,
    cache_write: 1,
    cache_read: 1,
    cost: 0.01,
    cost_source: CostSource::Api,
  }
  assert_true(d1 != d2)
}
