///| Billing record data structure for tracking LLM API usage costs.

///| Reference: openclacky/lib/clacky/billing/billing_record.rb

// ── ID Generation ───────────────────────────────────────────────

///|
/// Global counter for unique ID generation.
let id_counter : Ref[Int] = Ref(0)

///|
/// Generate a unique record ID using timestamp + counter pattern.
pub fn generate_id() -> String {
  let ts = current_time_ms()
  let count = id_counter.val
  id_counter.val = count + 1
  ts.to_string() + "-" + count.to_string()
}

// ── BillingRecord ───────────────────────────────────────────────

///|
/// A single billing record representing one LLM API call.
pub(all) struct BillingRecord {
  id : String // Unique record ID
  session_id : String // Associated session ID
  timestamp : Int64 // Unix milliseconds
  model : String // Model name used
  prompt_tokens : Int // Input tokens
  completion_tokens : Int // Output tokens
  cache_read_tokens : Int // Cache hit tokens
  cache_write_tokens : Int // Cache creation tokens
  cost_usd : Double // Calculated cost in USD
  cost_source : String // "price", "estimated", or "api"
} derive(Eq, Debug, ToJson, FromJson)

///|
/// Create a new BillingRecord with auto-generated ID and timestamp.
pub fn BillingRecord::new(
  session_id~ : String,
  model~ : String,
  prompt_tokens~ : Int,
  completion_tokens~ : Int,
  cache_read_tokens? : Int = 0,
  cache_write_tokens? : Int = 0,
  cost_usd~ : Double,
  cost_source~ : String,
) -> BillingRecord {
  {
    id: generate_id(),
    session_id,
    timestamp: current_time_ms(),
    model,
    prompt_tokens,
    completion_tokens,
    cache_read_tokens,
    cache_write_tokens,
    cost_usd,
    cost_source,
  }
}

///|
/// Total tokens used (prompt + completion).
pub fn BillingRecord::total_tokens(self : BillingRecord) -> Int {
  self.prompt_tokens + self.completion_tokens
}

// ── Time Helper ─────────────────────────────────────────────────

///|
/// Get current time in milliseconds (Unix epoch).
fn current_time_ms() -> Int64 {
  @env.now().reinterpret_as_int64()
}
