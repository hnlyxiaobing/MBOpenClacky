///| Token and cost tracking for Agent sessions.

///| Reference: openclacky/lib/clacky/agent/cost_tracker.rb

///|

///| Source of cost calculation.

///| - Api: cost provided directly by the API (e.g., OpenRouter)

///| - Price: calculated from model pricing table

///| - Default: fallback default pricing

///|
/// - Estimated: rough token-based estimate
pub(all) enum CostSource {
  Api
  Price
  Default
  Estimated
} derive(Eq, Debug)

///|
pub fn CostSource::to_string_value(self : CostSource) -> String {
  match self {
    Api => "api"
    Price => "price"
    Default => "default"
    Estimated => "estimated"
  }
}

///|
pub impl ToJson for CostSource with fn to_json(self) {
  self.to_string_value().to_json()
}

///|
/// Cache hit/miss statistics for prompt caching.
pub(all) struct CacheStats {
  mut cache_creation_input_tokens : Int
  mut cache_read_input_tokens : Int
  mut total_requests : Int
  mut cache_hit_requests : Int
} derive(Eq, Debug)

///|
/// Create a new CacheStats with all counters at zero.
pub fn CacheStats::new() -> CacheStats {
  {
    cache_creation_input_tokens: 0,
    cache_read_input_tokens: 0,
    total_requests: 0,
    cache_hit_requests: 0,
  }
}

///|
/// Token data collected from a single LLM iteration.
pub(all) struct IterationTokenData {
  delta_tokens : Int
  prompt_tokens : Int
  completion_tokens : Int
  total_tokens : Int
  cache_write : Int
  cache_read : Int
  cost : Double
  cost_source : CostSource
} derive(Eq, Debug)

///|
/// Estimate token count from character count (rough: chars / 4).
pub fn estimate_token_count(content : String) -> Int {
  let chars = content.length()
  if chars == 0 {
    0
  } else {
    (chars + 3) / 4
  }
}

///|
/// Calculate cost for a model using the pricing table.
/// Returns None when the model is unknown to the pricing table.
fn calculate_model_cost(model : String, usage : @client.Usage) -> Double? {
  match
    @pricing.calculate_cost(
      model~,
      prompt_tokens=usage.input_tokens,
      completion_tokens=usage.output_tokens,
      cache_write_tokens=usage.cache_creation_input_tokens,
      cache_read_tokens=usage.cache_read_input_tokens,
    ) {
    Ok(result) => Some(result.total_cost)
    Err(_) => None
  }
}

///|
/// Track cost from an LLM API usage response.
///
/// Updates Agent state: total_cost, cache_stats, previous_total_tokens.
/// Returns the collected IterationTokenData for this iteration.
fn Agent::track_cost(self : Agent, usage : @client.Usage) -> IterationTokenData {
  // Calculate cost: try model pricing, fall back to 0
  let cost = match calculate_model_cost(self.client.model, usage) {
    Some(c) => c
    None => 0.0
  }
  let source = match calculate_model_cost(self.client.model, usage) {
    Some(_) => Price
    None => Estimated
  }
  // Update running total
  self.total_cost = self.total_cost + cost
  // Update cache stats
  self.cache_stats.cache_creation_input_tokens = self.cache_stats.cache_creation_input_tokens +
    usage.cache_creation_input_tokens
  self.cache_stats.cache_read_input_tokens = self.cache_stats.cache_read_input_tokens +
    usage.cache_read_input_tokens
  self.cache_stats.total_requests = self.cache_stats.total_requests + 1
  if usage.cache_read_input_tokens > 0 {
    self.cache_stats.cache_hit_requests = self.cache_stats.cache_hit_requests +
      1
  }
  // Calculate token data
  let total_tokens = usage.input_tokens + usage.output_tokens
  let delta = total_tokens - self.previous_total_tokens
  self.previous_total_tokens = total_tokens
  // Record to billing store
  let billing_record = @billing.BillingRecord::new(
    session_id=self.session_id,
    model=self.client.model,
    prompt_tokens=usage.input_tokens,
    completion_tokens=usage.output_tokens,
    cache_read_tokens=usage.cache_read_input_tokens,
    cache_write_tokens=usage.cache_creation_input_tokens,
    cost_usd=cost,
    cost_source=source.to_string_value(),
  )
  let store = @billing.BillingStore::default()
  let _ = store.append(billing_record)
  {
    delta_tokens: delta,
    prompt_tokens: usage.input_tokens,
    completion_tokens: usage.output_tokens,
    total_tokens,
    cache_write: usage.cache_creation_input_tokens,
    cache_read: usage.cache_read_input_tokens,
    cost,
    cost_source: source,
  }
}
