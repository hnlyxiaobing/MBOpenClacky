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
pub extend CostSource with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend CostSource with Eq::{not_equal, equal}

///|
pub extend CostSource with ToJson::{to_json}

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
pub extend CacheStats with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend CacheStats with Eq::{not_equal, equal}

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
pub extend IterationTokenData with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend IterationTokenData with Eq::{not_equal, equal}

///|
/// Estimate token count from character count.
/// ASCII printable chars (U+0020..U+007E) count as ~4 chars/token, all
/// other chars (CJK, emoji, other multibyte) as ~1.5 chars/token; the
/// weighted sum is rounded up once. Matches Ruby `estimate_content_tokens`
/// (openclacky message_history.rb: `count(" -~")` / 4.0 + rest / 1.5, ceil).
pub fn estimate_token_count(content : String) -> Int {
  let mut ascii_chars = 0
  let mut total_chars = 0
  for c in content {
    total_chars = total_chars + 1
    if c >= '\u{20}' && c <= '\u{7E}' {
      ascii_chars = ascii_chars + 1
    }
  }
  let multibyte_chars = total_chars - ascii_chars
  (ascii_chars.to_double() / 4.0 + multibyte_chars.to_double() / 1.5)
  .ceil()
  .to_int()
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
/// Cost source priority mirrors Ruby cost_tracker.rb: api (upstream-reported
/// cost, e.g. OpenRouter `usage.cost`) > price (model pricing table) >
/// estimated (unknown model, cost stays 0).
///
/// Updates Agent state: total_cost, cost_source, cache_stats,
/// previous_total_tokens. Persists exactly one billing record per call
/// (subagents skip persistence — their spend is absorbed by the parent,
/// Ruby `unless @is_subagent`). Returns the collected IterationTokenData.
fn Agent::track_cost(self : Agent, usage : @client.Usage) -> IterationTokenData {
  // Cost source: api > price > estimated (Ruby track_cost priority 1/2).
  let (cost, source) = match usage.api_cost {
    Some(api_cost) => (api_cost, Api)
    None =>
      match calculate_model_cost(self.client.model, usage) {
        Some(c) => (c, Price)
        None => (0.0, Estimated)
      }
  }
  // Update running total and session-level cost source
  self.total_cost = self.total_cost + cost
  self.cost_source = source
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
  // Calculate token data. Two total_tokens conventions exist across
  // providers (Ruby collect_iteration_tokens):
  //   - OpenAI: cumulative input+output — delta = total - previous_total.
  //   - Anthropic direct: per-turn new compute (`total_is_per_turn`) — the
  //     total IS the delta; treating it as cumulative yields negative or
  //     nonsensical deltas whenever cached prefixes shrink the new compute.
  let total_tokens = usage.input_tokens + usage.output_tokens
  let raw_delta = if usage.total_is_per_turn {
    total_tokens
  } else {
    total_tokens - self.previous_total_tokens
  }
  // Guard: negative deltas (usage fallback / cross-turn reset) record 0.
  let delta = if raw_delta < 0 { 0 } else { raw_delta }
  // Guard: do NOT overwrite previous_total_tokens with 0 when the upstream
  // returns zero usage (Ruby cost_tracker.rb) — resetting would poison the
  // delta baseline for every subsequent turn.
  if total_tokens > 0 {
    self.previous_total_tokens = total_tokens
  }
  // Record to billing store — single write point per API call. Subagents
  // skip persistence so the parent's absorbed cost is not double-counted.
  if !self.is_subagent {
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
    let _ = self.billing_store.append(billing_record)
  }
  let data : IterationTokenData = {
    delta_tokens: delta,
    prompt_tokens: usage.input_tokens,
    completion_tokens: usage.output_tokens,
    total_tokens,
    cache_write: usage.cache_creation_input_tokens,
    cache_read: usage.cache_read_input_tokens,
    cost,
    cost_source: source,
  }
  self.hook_manager.emit(UsageUpdated(data))
  data
}
