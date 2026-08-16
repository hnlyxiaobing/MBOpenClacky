///| Cost calculation engine for LLM API usage.

///| Reference: openclacky/lib/clacky/utils/model_pricing.rb

///|
/// Result of a cost calculation with breakdown.
pub(all) struct CostResult {
  total_cost : Double
  source : CostSource
  input_cost : Double
  output_cost : Double
  cache_write_cost : Double
  cache_read_cost : Double
} derive(Eq, Debug)

///|
pub extend CostResult with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend CostResult with Eq::{not_equal, equal}

///|
/// Source of cost data.
pub(all) enum CostSource {
  Price
  Estimated
  Api
} derive(Eq, Debug)

///|
pub extend CostSource with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend CostSource with Eq::{not_equal, equal}

///| Calculate cost for a given model and token usage.

///|

///| Returns Ok(CostResult) with full breakdown, or Err(String) if model is unknown.

///|

///| Logic:

///| 1. Look up pricing via get_pricing(normalize_model_name(model))

///| 2. Determine if over threshold (total_input_tokens > context_threshold)

///| 3. Calculate input_cost = (prompt_tokens - cache_read_tokens) * rate / 1_000_000

///| 4. Calculate output_cost = completion_tokens * output_rate / 1_000_000

///| 5. Calculate cache costs separately

///|
/// 6. Return CostResult with breakdown
pub fn calculate_cost(
  model~ : String,
  prompt_tokens~ : Int,
  completion_tokens~ : Int,
  cache_write_tokens~ : Int,
  cache_read_tokens~ : Int,
) -> Result[CostResult, String] {
  let pricing = match get_pricing(model) {
    Some(p) => p
    None => return Err("Unknown model: " + model + " - no pricing available")
  }
  // Determine if we're in the over_threshold tier
  // prompt_tokens includes cache_read_tokens; cache_write_tokens are additional
  let total_input_tokens = prompt_tokens + cache_write_tokens
  let over_threshold = total_input_tokens > pricing.context_threshold
  // Calculate regular input cost (non-cached tokens)
  // prompt_tokens already includes cache_read_tokens, subtract them
  let regular_input_tokens = prompt_tokens - cache_read_tokens
  let input_rate = if over_threshold {
    pricing.input_over_200k
  } else {
    pricing.input_default
  }
  let input_cost = regular_input_tokens.to_double() / 1_000_000.0 * input_rate
  // Calculate output cost
  let output_rate = if over_threshold {
    pricing.output_over_200k
  } else {
    pricing.output_default
  }
  let output_cost = completion_tokens.to_double() / 1_000_000.0 * output_rate
  // Calculate cache write cost
  let cache_write_cost = if cache_write_tokens > 0 {
    let write_rate = if over_threshold {
      pricing.cache_write_over_200k
    } else {
      pricing.cache_write_default
    }
    cache_write_tokens.to_double() / 1_000_000.0 * write_rate
  } else {
    0.0
  }
  // Calculate cache read cost
  let cache_read_cost = if cache_read_tokens > 0 {
    let read_rate = if over_threshold {
      pricing.cache_read_over_200k
    } else {
      pricing.cache_read_default
    }
    cache_read_tokens.to_double() / 1_000_000.0 * read_rate
  } else {
    0.0
  }
  let total_cost = input_cost + output_cost + cache_write_cost + cache_read_cost
  Ok({
    total_cost,
    source: Price,
    input_cost,
    output_cost,
    cache_write_cost,
    cache_read_cost,
  })
}
