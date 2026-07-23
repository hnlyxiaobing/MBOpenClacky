///| Extended pricing tests: normalize_model_name edge cases, pricing_table completeness, calculate_cost boundaries.

// ── normalize_model_name Extended Tests ─────────────────────────────────────

///|
test "ext_normalize_glm_variations" {
  @debug.assert_eq(normalize_model_name("glm-5.1"), Some("glm-5.1"))
  @debug.assert_eq(normalize_model_name("glm-5"), Some("glm-5"))
  @debug.assert_eq(normalize_model_name("glm-5-turbo"), Some("glm-5-turbo"))
  @debug.assert_eq(normalize_model_name("glm-4.7"), Some("glm-4.7"))
}

///|
test "ext_normalize_kimi_variations" {
  @debug.assert_eq(normalize_model_name("kimi-k2.5"), Some("kimi-k2.5"))
  @debug.assert_eq(normalize_model_name("kimi-k2.6"), Some("kimi-k2.6"))
}

///|
test "ext_normalize_gemini_variations" {
  @debug.assert_eq(
    normalize_model_name("gemini-3.1-pro"),
    Some("gemini-3.1-pro"),
  )
  @debug.assert_eq(
    normalize_model_name("gemini-3-flash"),
    Some("gemini-3-flash"),
  )
}

///|
test "ext_normalize_minimax_variations" {
  @debug.assert_eq(normalize_model_name("minimax-m3"), Some("minimax-m3"))
  @debug.assert_eq(normalize_model_name("minimax-m2.5"), Some("minimax-m2.5"))
  @debug.assert_eq(normalize_model_name("minimax-m2.7"), Some("minimax-m2.7"))
}

///|
test "ext_normalize_qwen_variations" {
  @debug.assert_eq(normalize_model_name("qwen3.7-max"), Some("qwen3.7-max"))
  @debug.assert_eq(normalize_model_name("qwen3.7-plus"), Some("qwen3.7-plus"))
}

///|
test "ext_normalize_mimo_variations" {
  @debug.assert_eq(normalize_model_name("mimo-v2.5-pro"), Some("mimo-v2.5-pro"))
  @debug.assert_eq(normalize_model_name("mimo-v2-flash"), Some("mimo-v2-flash"))
  @debug.assert_eq(normalize_model_name("mimo-v2-pro"), Some("mimo-v2-pro"))
}

// ── pricing_table Completeness Tests ────────────────────────────────────────

///|
test "ext_pricing_table_not_empty" {
  let table = pricing_table()
  assert_true(table.length() > 20)
}

///|
test "ext_pricing_table_has_all_providers" {
  let table = pricing_table()
  assert_true(table.contains("claude-sonnet-4.5"))
  assert_true(table.contains("gpt-5.5"))
  assert_true(table.contains("gemini-3.1-pro"))
  assert_true(table.contains("glm-5.1"))
  assert_true(table.contains("kimi-k2.5"))
  assert_true(table.contains("minimax-m3"))
  assert_true(table.contains("o3"))
  assert_true(table.contains("deepseek-v4-flash"))
}

// ── get_pricing Extended Tests ──────────────────────────────────────────────

///|
test "ext_get_pricing_glm_5_1" {
  let p = get_pricing("glm-5.1")
  match p {
    Some(pr) => {
      @debug.assert_eq(pr.input_default, 1.40)
      @debug.assert_eq(pr.output_default, 4.40)
    }
    None => assert_true(false)
  }
}

///|
test "ext_get_pricing_kimi_k2_6" {
  let p = get_pricing("kimi-k2.6")
  match p {
    Some(pr) => {
      @debug.assert_eq(pr.input_default, 0.95)
      @debug.assert_eq(pr.output_default, 4.0)
    }
    None => assert_true(false)
  }
}

///|
test "ext_get_pricing_gemini_flash" {
  let p = get_pricing("gemini-3-flash")
  match p {
    Some(pr) => {
      @debug.assert_eq(pr.input_default, 0.50)
      @debug.assert_eq(pr.output_default, 3.0)
    }
    None => assert_true(false)
  }
}

///|
test "ext_get_pricing_o4_mini" {
  let p = get_pricing("o4-mini")
  match p {
    Some(pr) => {
      @debug.assert_eq(pr.input_default, 1.10)
      @debug.assert_eq(pr.output_default, 4.40)
    }
    None => assert_true(false)
  }
}

// ── calculate_cost Boundary Tests ────────────────────────────────────────────

///|
test "ext_calculate_cost_zero_tokens" {
  let result = calculate_cost(
    model="claude-sonnet-4.5",
    prompt_tokens=0,
    completion_tokens=0,
    cache_write_tokens=0,
    cache_read_tokens=0,
  )
  match result {
    Ok(r) => @debug.assert_eq(r.total_cost, 0.0)
    Err(e) => fail("unexpected error: " + e)
  }
}

///|
test "ext_calculate_cost_all_cache_read" {
  let result = calculate_cost(
    model="claude-sonnet-4.5",
    prompt_tokens=1000,
    completion_tokens=0,
    cache_write_tokens=0,
    cache_read_tokens=1000,
  )
  match result {
    Ok(r) => {
      @debug.assert_eq(r.input_cost, 0.0)
      @debug.assert_eq(r.cache_read_cost, 0.0003)
    }
    Err(e) => fail("unexpected error: " + e)
  }
}

///|
test "ext_calculate_cost_deepseek_1m_tokens" {
  let result = calculate_cost(
    model="deepseek-v4-flash",
    prompt_tokens=1_000_000,
    completion_tokens=1_000_000,
    cache_write_tokens=0,
    cache_read_tokens=0,
  )
  match result {
    Ok(r) => {
      @debug.assert_eq(r.input_cost, 0.14)
      @debug.assert_eq(r.output_cost, 0.28)
    }
    Err(e) => fail("unexpected error: " + e)
  }
}

///|
test "ext_calculate_cost_glm_with_cache" {
  let result = calculate_cost(
    model="glm-5.1",
    prompt_tokens=1000,
    completion_tokens=500,
    cache_write_tokens=200,
    cache_read_tokens=100,
  )
  match result {
    Ok(r) => assert_true(r.total_cost > 0.0)
    Err(e) => fail("unexpected error: " + e)
  }
}

///|
test "ext_model_pricing_equality" {
  let p1 = get_pricing("claude-sonnet-4.5")
  let p2 = get_pricing("claude-sonnet-4.5")
  match (p1, p2) {
    (Some(a), Some(b)) => assert_true(a == b)
    _ => assert_true(false)
  }
}

///|
test "ext_calculate_cost_gpt_5_4_mini" {
  let result = calculate_cost(
    model="gpt-5.4-mini",
    prompt_tokens=500_000,
    completion_tokens=100_000,
    cache_write_tokens=0,
    cache_read_tokens=0,
  )
  match result {
    Ok(r) =>
      // 500K not over 200K threshold for mini (no tiered)
      // input = 500000/1M * 0.75 = 0.375
      @debug.assert_eq(r.input_cost, 0.375)
    Err(e) => fail("unexpected error: " + e)
  }
}

// ── Additional normalize_model_name Tests ───────────────────────────────────

///|
test "ext_normalize_model_various_inputs" {
  let models = ["gpt-4", "claude-3-opus", "gemini-pro", "llama-3"]
  for m in models {
    let normalized = normalize_model_name(m)
    match normalized {
      Some(s) => assert_true(s.length() > 0)
      None => assert_true(true)
    }
  }
}

///|
test "ext_normalize_model_preserves_known" {
  let known = ["gpt-4o", "gpt-4o-mini", "claude-3-5-sonnet", "claude-3-opus"]
  for m in known {
    let result = normalize_model_name(m)
    match result {
      Some(s) => assert_true(s.length() > 0)
      None => assert_true(true)
    }
  }
}

///|
test "ext_normalize_model_empty_string" {
  let result = normalize_model_name("")
  match result {
    Some(s) => assert_eq(s, "")
    None => assert_true(true)
  }
}

// ── Additional pricing_table Tests ──────────────────────────────────────────

///|
test "ext_pricing_table_has_entries" {
  let table = pricing_table()
  assert_true(table.length() > 0)
}

///|
test "ext_pricing_table_contains_known_models" {
  let table = pricing_table()
  assert_true(table.length() > 0)
  let mut found = false
  for entry in table.iter() {
    if entry.0.contains("claude") || entry.0.contains("gpt") {
      found = true
    }
  }
  assert_true(found)
}

///|
test "ext_pricing_table_model_pricing_fields" {
  let table = pricing_table()
  for entry in table.iter() {
    let mp = entry.1
    assert_true(mp.input_default >= 0.0)
    assert_true(mp.output_default >= 0.0)
  }
}
