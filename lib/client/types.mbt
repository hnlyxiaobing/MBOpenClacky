///|
/// Token usage metrics from an LLM API response.
///
/// Mirrors Ruby's canonical usage shape (OpenAI-style):
/// - `input_tokens` = total input incl. cache_read, excl. cache_creation
/// - `total_tokens` = THIS TURN'S new compute volume (non-cached +
///   cache_creation + output); for Anthropic this is a per-turn delta
///   (`total_is_per_turn = true`), for OpenAI it is the cumulative
///   `total_tokens` reported by the upstream.
/// - `api_cost` = upstream-reported cost (e.g. OpenRouter `usage.cost`),
///   stored as Double (Ruby's Float is IEEE-754 double precision).
pub(all) struct Usage {
  input_tokens : Int
  output_tokens : Int
  cache_creation_input_tokens : Int
  cache_read_input_tokens : Int
  total_tokens : Int
  api_cost : Double?
  total_is_per_turn : Bool
} derive(Eq, Debug, ToJson)

///|
pub extend Usage with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend Usage with Eq::{not_equal, equal}

///|
pub extend Usage with ToJson::{to_json}

///|
/// FromJson for Usage tolerates missing fields (old persisted sessions):
/// absent counters default to 0, optional cost to None.
pub impl FromJson for Usage with fn from_json(json, path) {
  match json {
    Object(map) => {
      let int_of = fn(key : String) -> Int {
        match map.get(key) {
          Some(Number(n, ..)) => n.to_int()
          _ => 0
        }
      }
      let bool_of = fn(key : String, default : Bool) -> Bool {
        match map.get(key) {
          Some(True) => true
          Some(False) => false
          _ => default
        }
      }
      let float_of = fn(key : String) -> Double? {
        match map.get(key) {
          Some(Number(n, ..)) => Some(n)
          _ => None
        }
      }
      {
        input_tokens: int_of("input_tokens"),
        output_tokens: int_of("output_tokens"),
        cache_creation_input_tokens: int_of("cache_creation_input_tokens"),
        cache_read_input_tokens: int_of("cache_read_input_tokens"),
        total_tokens: int_of("total_tokens"),
        api_cost: float_of("api_cost"),
        total_is_per_turn: bool_of("total_is_per_turn", false),
      }
    }
    _ => raise JsonDecodeError((path, "Usage: expected object"))
  }
}

///|
/// Latency metrics from an LLM API response.
///
/// `ttft_ms` is the time to first token (falls back to duration for
/// non-streaming calls); `tps` is output tokens per second (None when the
/// measurement is unreliable, e.g. fewer than 10 output tokens).
pub(all) struct Latency {
  duration_ms : Int
  ttft_ms : Int?
  tps : Double?
} derive(Eq, Debug, ToJson)

///|
pub extend Latency with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend Latency with Eq::{not_equal, equal}

///|
pub extend Latency with ToJson::{to_json}

///|
/// FromJson for Latency tolerates missing optional fields.
pub impl FromJson for Latency with fn from_json(json, path) {
  match json {
    Object(map) => {
      let int_of = fn(key : String) -> Int {
        match map.get(key) {
          Some(Number(n, ..)) => n.to_int()
          _ => 0
        }
      }
      let opt_int_of = fn(key : String) -> Int? {
        match map.get(key) {
          Some(Number(n, ..)) => Some(n.to_int())
          _ => None
        }
      }
      let opt_float_of = fn(key : String) -> Double? {
        match map.get(key) {
          Some(Number(n, ..)) => Some(n)
          _ => None
        }
      }
      {
        duration_ms: int_of("duration_ms"),
        ttft_ms: opt_int_of("ttft_ms"),
        tps: opt_float_of("tps"),
      }
    }
    _ => raise JsonDecodeError((path, "Latency: expected object"))
  }
}

///|
/// Response from an LLM API call.
pub(all) struct LlmResponse {
  content : String?
  reasoning_content : String?
  tool_calls : Array[@message.ToolCall]?
  finish_reason : String?
  usage : Usage?
  latency : Latency?
} derive(Eq, Debug, ToJson)

///|
pub extend LlmResponse with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend LlmResponse with Eq::{not_equal, equal}

///|
pub extend LlmResponse with ToJson::{to_json}

///|
/// Create a simple text-only LLM response.
pub fn LlmResponse::text_only(content : String) -> LlmResponse {
  {
    content: Some(content),
    reasoning_content: None,
    tool_calls: None,
    finish_reason: Some("stop"),
    usage: None,
    latency: None,
  }
}

///|
/// Check if this response contains tool calls.
pub fn LlmResponse::has_tool_calls(self : LlmResponse) -> Bool {
  match self.tool_calls {
    Some(calls) => calls.length() > 0
    None => false
  }
}

///|
/// Check if the response indicates the conversation is finished.
pub fn LlmResponse::is_finished(self : LlmResponse) -> Bool {
  match self.finish_reason {
    Some("stop") => true
    Some("end_turn") => true
    _ => false
  }
}

///|
/// Create Usage from raw API token counts (OpenAI-style naming).
///
/// `total_tokens` mirrors the upstream `total_tokens` value; when not
/// provided it is derived as prompt + completion. `total_is_per_turn`
/// stays false (OpenAI's total_tokens is a cumulative counter).
pub fn Usage::from_openai(
  prompt_tokens : Int,
  completion_tokens : Int,
  cache_creation? : Int = 0,
  cache_read? : Int = 0,
  total_tokens? : Int = 0,
  api_cost? : Double? = None,
) -> Usage {
  {
    input_tokens: prompt_tokens,
    output_tokens: completion_tokens,
    cache_creation_input_tokens: cache_creation,
    cache_read_input_tokens: cache_read,
    total_tokens: if total_tokens > 0 {
      total_tokens
    } else {
      prompt_tokens + completion_tokens
    },
    api_cost,
    total_is_per_turn: false,
  }
}

///|
/// Create Usage from raw Anthropic API token counts, applying Ruby's
/// two-convention prompt-token normalisation to avoid double-billing the
/// cached prefix.
///
/// Anthropic reports `input_tokens` as the post-breakpoint tail only, with
/// the cache buckets disjoint from it. Some /v1/messages-compatible
/// gateways instead report `input_tokens` as the FULL input with both cache
/// buckets already folded in; adding `cache_read` there would bill the whole
/// cached prefix twice. Detect that by whether the cache buckets already fit
/// inside `input_tokens`.
pub fn Usage::from_anthropic(
  raw_input_tokens : Int,
  output_tokens : Int,
  cache_creation? : Int = 0,
  cache_read? : Int = 0,
) -> Usage {
  let cached_input = cache_read + cache_creation
  let prompt_tokens = if cached_input > 0 && raw_input_tokens >= cached_input {
    raw_input_tokens - cache_creation
  } else {
    raw_input_tokens + cache_read
  }
  {
    input_tokens: prompt_tokens,
    output_tokens,
    cache_creation_input_tokens: cache_creation,
    cache_read_input_tokens: cache_read,
    // Per-turn new compute: excludes cache_read (nearly free), includes
    // cache_creation (new work billed at write rate) + output.
    total_tokens: prompt_tokens - cache_read + cache_creation + output_tokens,
    api_cost: None,
    total_is_per_turn: true,
  }
}

///|
/// Create a Latency from timing measurements.
pub fn Latency::new(
  duration_ms : Int,
  ttft_ms? : Int,
  tps? : Double? = None,
) -> Latency {
  { duration_ms, ttft_ms, tps }
}
