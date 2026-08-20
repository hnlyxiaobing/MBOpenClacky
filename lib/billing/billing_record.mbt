///| Billing record data structure for tracking LLM API usage costs.

///| Reference: openclacky/lib/clacky/billing/billing_record.rb

// ── ID Generation ───────────────────────────────────────────────

///|
/// Generate a unique record ID as a v4-style UUID string, matching Ruby
/// `SecureRandom.uuid` (spec 21 decision 7).
pub fn generate_id() -> String {
  let rng = @random.Rand::new()
  let hex = "0123456789abcdef"
  let mut id = ""
  for i = 0; i < 36; i = i + 1 {
    let piece = match i {
      8 | 13 | 18 | 23 => "-"
      14 => "4" // version nibble
      19 => {
        // variant nibble: 8, 9, a or b
        let idx = rng.int(limit=4) + 8
        hex[idx:idx + 1].to_owned()
      }
      _ => {
        let idx = rng.int(limit=16)
        hex[idx:idx + 1].to_owned()
      }
    }
    id = id + piece
  }
  id
}

// ── BillingRecord ───────────────────────────────────────────────

///|
/// A single billing record representing one LLM API call.
pub(all) struct BillingRecord {
  id : String // Unique record ID (UUID)
  session_id : String // Associated session ID
  timestamp : Int64 // Unix milliseconds (serialized as ISO 8601)
  model : String // Model name used
  prompt_tokens : Int // Input tokens
  completion_tokens : Int // Output tokens
  cache_read_tokens : Int // Cache hit tokens
  cache_write_tokens : Int // Cache creation tokens
  cost_usd : Double // Calculated cost in USD
  cost_source : String // "price", "estimated", or "api"
} derive(Eq, Debug)

///|
pub extend BillingRecord with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend BillingRecord with Eq::{not_equal, equal}

///|
/// Serialize with an ISO 8601 local timestamp, mirroring Ruby
/// BillingRecord#to_h (`timestamp.iso8601`, spec 21 decision 7).
pub extend BillingRecord with ToJson::{to_json}

///|
pub impl ToJson for BillingRecord with fn to_json(self) {
  Json::object({
    "id": ToJson::to_json(self.id),
    "session_id": ToJson::to_json(self.session_id),
    "timestamp": ToJson::to_json(ms_to_iso8601_local(self.timestamp)),
    "model": ToJson::to_json(self.model),
    "prompt_tokens": ToJson::to_json(self.prompt_tokens),
    "completion_tokens": ToJson::to_json(self.completion_tokens),
    "cache_read_tokens": ToJson::to_json(self.cache_read_tokens),
    "cache_write_tokens": ToJson::to_json(self.cache_write_tokens),
    "cost_usd": ToJson::to_json(self.cost_usd),
    "cost_source": ToJson::to_json(self.cost_source),
  })
}

///|
/// Deserialize, accepting ISO 8601 strings and legacy numeric
/// millisecond timestamps (records written before decision 7).
pub extend BillingRecord with @moonbitlang/core/json.FromJson::{from_json}

///|
pub impl FromJson for BillingRecord with fn from_json(json, path) {
  match json {
    Object(map) => {
      let timestamp = match map.get("timestamp") {
        Some(v) =>
          match parse_timestamp_to_ms(v) {
            Some(ms) => ms
            None => 0L
          }
        None => 0L
      }
      {
        id: field_string(map, "id"),
        session_id: field_string(map, "session_id"),
        timestamp,
        model: field_string(map, "model"),
        prompt_tokens: field_int(map, "prompt_tokens"),
        completion_tokens: field_int(map, "completion_tokens"),
        cache_read_tokens: field_int(map, "cache_read_tokens"),
        cache_write_tokens: field_int(map, "cache_write_tokens"),
        cost_usd: field_double(map, "cost_usd"),
        cost_source: field_string(map, "cost_source"),
      }
    }
    _ => raise JsonDecodeError((path, "BillingRecord: expected object"))
  }
}

///|
fn field_string(map : Map[String, Json], key : String) -> String {
  match map.get(key) {
    Some(String(s)) => s
    _ => ""
  }
}

///|
fn field_int(map : Map[String, Json], key : String) -> Int {
  match map.get(key) {
    Some(Number(d, ..)) => d.to_int()
    _ => 0
  }
}

///|
fn field_double(map : Map[String, Json], key : String) -> Double {
  match map.get(key) {
    Some(Number(d, ..)) => d
    _ => 0.0
  }
}

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
