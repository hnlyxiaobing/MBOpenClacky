///|
test "get_pricing_claude_sonnet_4_5" {
  let pricing = get_pricing("claude-sonnet-4.5")
  match pricing {
    Some(p) => {
      @debug.assert_eq(p.input_default, 3.0)
      @debug.assert_eq(p.output_default, 15.0)
      @debug.assert_eq(p.input_over_200k, 6.0)
      @debug.assert_eq(p.output_over_200k, 22.5)
      @debug.assert_eq(p.cache_write_default, 3.75)
      @debug.assert_eq(p.cache_read_default, 0.3)
    }
    None => fail("expected Some for claude-sonnet-4.5")
  }
}

///|
test "get_pricing_o3" {
  let pricing = get_pricing("o3")
  match pricing {
    Some(p) => {
      @debug.assert_eq(p.input_default, 2.0)
      @debug.assert_eq(p.output_default, 8.0)
    }
    None => fail("expected Some for o3")
  }
}

///|
test "get_pricing_deepseek_v4_flash" {
  let pricing = get_pricing("deepseek-v4-flash")
  match pricing {
    Some(p) => {
      @debug.assert_eq(p.input_default, 0.14)
      @debug.assert_eq(p.output_default, 0.28)
      @debug.assert_eq(p.cache_read_default, 0.0028)
    }
    None => fail("expected Some for deepseek-v4-flash")
  }
}

///|
test "get_pricing_unknown_model" {
  let pricing = get_pricing("unknown-model-xyz")
  assert_true(pricing is None)
}

///|
test "normalize_model_name_claude_variations" {
  // dot vs dash separator
  @debug.assert_eq(
    normalize_model_name("claude-sonnet-4.5"),
    Some("claude-sonnet-4.5"),
  )
  @debug.assert_eq(
    normalize_model_name("claude-sonnet-4-5"),
    Some("claude-sonnet-4.5"),
  )
  // case insensitive
  @debug.assert_eq(
    normalize_model_name("Claude-Sonnet-4.5"),
    Some("claude-sonnet-4.5"),
  )
  // with prefix (Bedrock style)
  @debug.assert_eq(
    normalize_model_name("jp.anthropic.claude-sonnet-4-5"),
    Some("claude-sonnet-4.5"),
  )
}

///|
test "normalize_model_name_gpt_variations" {
  @debug.assert_eq(normalize_model_name("gpt-5.5"), Some("gpt-5.5"))
  @debug.assert_eq(normalize_model_name("gpt-5.4-mini"), Some("gpt-5.4-mini"))
  @debug.assert_eq(normalize_model_name("gpt-5.4-nano"), Some("gpt-5.4-nano"))
  @debug.assert_eq(normalize_model_name("gpt-5.4"), Some("gpt-5.4"))
}

///|
test "normalize_model_name_deepseek_legacy" {
  @debug.assert_eq(
    normalize_model_name("deepseek-chat"),
    Some("deepseek-v4-flash"),
  )
  @debug.assert_eq(
    normalize_model_name("deepseek-reasoner"),
    Some("deepseek-v4-flash"),
  )
}

///|
test "normalize_model_name_empty_string" {
  assert_true(normalize_model_name("") is None)
}

///|
test "normalize_model_name_o_series" {
  @debug.assert_eq(normalize_model_name("o3"), Some("o3"))
  @debug.assert_eq(normalize_model_name("o4-mini"), Some("o4-mini"))
  @debug.assert_eq(normalize_model_name("o4mini"), Some("o4-mini"))
}

///|
test "calculate_cost_basic" {
  // Claude Sonnet 4.5: 1000 prompt tokens, 500 output tokens, no cache
  let result = calculate_cost(
    model="claude-sonnet-4.5",
    prompt_tokens=1000,
    completion_tokens=500,
    cache_write_tokens=0,
    cache_read_tokens=0,
  )
  match result {
    Ok(r) => {
      assert_true(r.source == Price)
      // input_cost = 1000 / 1_000_000 * 3.0 = 0.003
      @debug.assert_eq(r.input_cost, 0.003)
      // output_cost = 500 / 1_000_000 * 15.0 = 0.0075
      @debug.assert_eq(r.output_cost, 0.0075)
      @debug.assert_eq(r.cache_write_cost, 0.0)
      @debug.assert_eq(r.cache_read_cost, 0.0)
      // total = 0.003 + 0.0075 = 0.0105 (approx due to floating point)
      assert_true(r.total_cost > 0.0104 && r.total_cost < 0.0106)
    }
    Err(e) => fail("unexpected error: " + e)
  }
}

///|
test "calculate_cost_over_threshold" {
  // Claude Sonnet 4.5 with over 200K prompt tokens (tiered pricing)
  let result = calculate_cost(
    model="claude-sonnet-4.5",
    prompt_tokens=250_000,
    completion_tokens=1000,
    cache_write_tokens=0,
    cache_read_tokens=0,
  )
  match result {
    Ok(r) => {
      // over_threshold: 250000 > 200000
      // input_cost = 250000 / 1_000_000 * 6.0 = 1.5
      @debug.assert_eq(r.input_cost, 1.5)
      // output_cost = 1000 / 1_000_000 * 22.5 = 0.0225
      @debug.assert_eq(r.output_cost, 0.0225)
    }
    Err(e) => fail("unexpected error: " + e)
  }
}

///|
test "calculate_cost_with_cache" {
  // Claude Sonnet 4.5 with cache tokens
  let result = calculate_cost(
    model="claude-sonnet-4.5",
    prompt_tokens=10_000,
    completion_tokens=2000,
    cache_write_tokens=5000,
    cache_read_tokens=3000,
  )
  match result {
    Ok(r) => {
      // total_input = 10000 + 5000 = 15000, not over threshold
      // regular_input = 10000 - 3000 = 7000
      // input_cost = 7000 / 1_000_000 * 3.0 = 0.021
      @debug.assert_eq(r.input_cost, 0.021)
      // output_cost = 2000 / 1_000_000 * 15.0 = 0.03
      @debug.assert_eq(r.output_cost, 0.03)
      // cache_write_cost = 5000 / 1_000_000 * 3.75 = 0.01875
      @debug.assert_eq(r.cache_write_cost, 0.01875)
      // cache_read_cost = 3000 / 1_000_000 * 0.3 = 0.0009
      @debug.assert_eq(r.cache_read_cost, 0.0009)
    }
    Err(e) => fail("unexpected error: " + e)
  }
}

///|
test "calculate_cost_unknown_model" {
  let result = calculate_cost(
    model="nonexistent-model",
    prompt_tokens=1000,
    completion_tokens=500,
    cache_write_tokens=0,
    cache_read_tokens=0,
  )
  assert_true(result is Err(_))
}

///|
test "get_pricing_all_providers" {
  // Verify we can look up at least one model from each provider
  assert_true(get_pricing("claude-sonnet-4.5") is Some(_))
  assert_true(get_pricing("deepseek-v4-flash") is Some(_))
  assert_true(get_pricing("mimo-v2.5-pro") is Some(_))
  assert_true(get_pricing("kimi-k2.5") is Some(_))
  assert_true(get_pricing("gemini-3.1-pro") is Some(_))
  assert_true(get_pricing("gpt-5.5") is Some(_))
  assert_true(get_pricing("o3") is Some(_))
  assert_true(get_pricing("glm-5.1") is Some(_))
  assert_true(get_pricing("minimax-m3") is Some(_))
  assert_true(get_pricing("qwen3.7-max") is Some(_))
}

///|
test "calculate_cost_gpt_5_5_threshold_272k" {
  // GPT-5.5 has a 272K threshold
  let pricing = get_pricing("gpt-5.5")
  match pricing {
    Some(p) => @debug.assert_eq(p.context_threshold, 272_000)
    None => fail("expected Some for gpt-5.5")
  }
  // 250K tokens: under 272K threshold -> default rate
  let result = calculate_cost(
    model="gpt-5.5",
    prompt_tokens=250_000,
    completion_tokens=1000,
    cache_write_tokens=0,
    cache_read_tokens=0,
  )
  match result {
    Ok(r) =>
      // input_cost = 250000 / 1_000_000 * 5.0 = 1.25 (default rate)
      @debug.assert_eq(r.input_cost, 1.25)
    Err(e) => fail("unexpected error: " + e)
  }
}
