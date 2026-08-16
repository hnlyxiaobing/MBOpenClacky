///|
/// Token usage metrics from an LLM API response.
pub(all) struct Usage {
  input_tokens : Int
  output_tokens : Int
  cache_creation_input_tokens : Int
  cache_read_input_tokens : Int
} derive(Eq, Debug, ToJson, FromJson)

///|
pub extend Usage with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend Usage with @moonbitlang/core/json.FromJson::{from_json}

///|
pub extend Usage with Eq::{not_equal, equal}

///|
pub extend Usage with ToJson::{to_json}

///|
/// Latency metrics from an LLM API response.
pub(all) struct Latency {
  duration_ms : Int
  ttft_ms : Int?
} derive(Eq, Debug, ToJson, FromJson)

///|
pub extend Latency with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend Latency with @moonbitlang/core/json.FromJson::{from_json}

///|
pub extend Latency with Eq::{not_equal, equal}

///|
pub extend Latency with ToJson::{to_json}

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
pub fn Usage::from_openai(
  prompt_tokens : Int,
  completion_tokens : Int,
  cache_creation? : Int = 0,
  cache_read? : Int = 0,
) -> Usage {
  {
    input_tokens: prompt_tokens,
    output_tokens: completion_tokens,
    cache_creation_input_tokens: cache_creation,
    cache_read_input_tokens: cache_read,
  }
}

///|
/// Create Usage from raw Anthropic API token counts.
/// Anthropic reports input_tokens separately from cache tokens,
/// so we normalize to OpenAI-style: input_tokens = raw_input + cache_read.
pub fn Usage::from_anthropic(
  raw_input_tokens : Int,
  output_tokens : Int,
  cache_creation? : Int = 0,
  cache_read? : Int = 0,
) -> Usage {
  {
    input_tokens: raw_input_tokens + cache_read,
    output_tokens,
    cache_creation_input_tokens: cache_creation,
    cache_read_input_tokens: cache_read,
  }
}

///|
/// Create a Latency from timing measurements.
pub fn Latency::new(duration_ms : Int, ttft_ms? : Int) -> Latency {
  { duration_ms, ttft_ms }
}
