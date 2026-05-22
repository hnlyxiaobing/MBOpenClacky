///|
/// Token usage metrics from an LLM API response.
pub(all) struct Usage {
  input_tokens : Int
  output_tokens : Int
  cache_creation_input_tokens : Int
  cache_read_input_tokens : Int
} derive(Eq, Debug, ToJson, FromJson)

///|
/// Latency metrics from an LLM API response.
pub(all) struct Latency {
  duration_ms : Int
  ttft_ms : Int?
} derive(Eq, Debug, ToJson, FromJson)

///|
/// Response from an LLM API call.
pub(all) struct LlmResponse {
  content : String?
  tool_calls : Array[@message.ToolCall]?
  finish_reason : String?
  usage : Usage?
  latency : Latency?
} derive(Eq, Debug, ToJson)

///|
/// Create a simple text-only LLM response.
pub fn LlmResponse::text_only(content : String) -> LlmResponse {
  {
    content: Some(content),
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
