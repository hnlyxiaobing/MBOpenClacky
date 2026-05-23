///| LLM API client: connection management, request dispatch, error handling.

///|

///| Supports OpenAI-compatible and Anthropic Messages API protocols.

///| Routes requests to the appropriate format module based on ApiType.

///|

///| NOTE: Async HTTP calls require moonbitlang/async (currently pending

///| dependency version resolution). The send_* methods below are

///| synchronous stubs that build requests and parse responses using

///| the format modules. The actual HTTP transport will be wired in

///|
/// when the async dependency is compatible.
using @config {type ApiType}

///|
/// LLM API client configuration and connection state.
pub(all) struct Client {
  api_key : String
  base_url : String
  model : String
  api_type : ApiType
  provider_id : String?
  vision_supported : Bool
}

///|
/// Request parameters for send_messages_with_tools.
pub(all) struct SendRequest {
  messages : Array[@message.Message]
  model : String
  tools : Array[Json]
  max_tokens : Int
  enable_caching : Bool
  reasoning_effort : String?
}

///|
/// Result of a connection test.
pub(all) struct TestResult {
  success : Bool
  error : String?
} derive(Debug)

// ── Client Construction ─────────────────────────────────────────────────────

///|
/// Create a new LLM client.
pub fn Client::new(
  api_key : String,
  base_url : String,
  model : String,
  api_type : ApiType,
  provider_id? : String? = None,
  vision_supported? : Bool = true,
) -> Client {
  { api_key, base_url, model, api_type, provider_id, vision_supported }
}

///|
/// Check if this client uses the Anthropic Messages API (not Bedrock).
pub fn Client::is_anthropic_format(self : Client) -> Bool {
  match self.api_type {
    @config.AnthropicMessages => true
    _ => false
  }
}

// ── Request Building ────────────────────────────────────────────────────────

///|
/// Build the HTTP request body JSON for the given parameters.
/// Dispatches to the appropriate format module based on API type.
pub fn Client::build_request_body(self : Client, request : SendRequest) -> Json {
  let caching_enabled = if request.enable_caching {
    self.supports_prompt_caching(request.model)
  } else {
    false
  }
  if self.is_anthropic_format() {
    build_anthropic_request(
      request.messages,
      request.model,
      request.tools,
      request.max_tokens,
      caching_enabled,
      reasoning_effort=request.reasoning_effort,
    )
  } else {
    build_openai_request(
      request.messages,
      request.model,
      request.tools,
      request.max_tokens,
      caching_enabled,
      vision_supported=self.vision_supported,
      reasoning_effort=request.reasoning_effort,
    )
  }
}

///|
/// Build a simple (non-agent) request body for a text-only message.
pub fn Client::build_simple_request(
  self : Client,
  content : String,
  model : String,
  max_tokens : Int,
) -> Json {
  let messages = [@message.Message::user(content)]
  if self.is_anthropic_format() {
    build_anthropic_request(messages, model, [], max_tokens, false)
  } else {
    build_openai_request(
      messages,
      model,
      [],
      max_tokens,
      false,
      vision_supported=self.vision_supported,
    )
  }
}

// ── Response Parsing ────────────────────────────────────────────────────────

///|
/// Parse an API response JSON into an LlmResponse.
/// Dispatches to the appropriate format module based on API type.
pub fn Client::parse_response(self : Client, data : Json) -> LlmResponse {
  if self.is_anthropic_format() {
    parse_anthropic_response(data)
  } else {
    parse_openai_response(data)
  }
}

// ── Tool Result Formatting ──────────────────────────────────────────────────

///|
/// Format tool results into canonical messages for the next API turn.
/// Delegates to the appropriate format module based on API type.
pub fn Client::format_tool_results(
  self : Client,
  response : LlmResponse,
  tool_results : Map[String, String],
) -> Array[@message.Message] {
  if self.is_anthropic_format() {
    format_anthropic_tool_results(response, tool_results)
  } else {
    format_openai_tool_results(response, tool_results)
  }
}

// ── API Endpoint Helpers ────────────────────────────────────────────────────

///|
/// Get the API endpoint path for this client's protocol.
pub fn Client::api_path(self : Client) -> String {
  if self.is_anthropic_format() {
    anthropic_messages_path(self.base_url)
  } else {
    "chat/completions"
  }
}

///|
/// Build the full URL for an API path.
pub fn Client::build_url(self : Client, path : String) -> String {
  let base = self.base_url.trim_end()
  if base.length() > 0 && base[base.length() - 1:].to_string() == "/" {
    "\{base}\{path}"
  } else {
    "\{base}/\{path}"
  }
}

///|
/// Build the complete request URL for the current API type.
pub fn Client::request_url(self : Client) -> String {
  self.build_url(self.api_path())
}

// ── HTTP Headers ────────────────────────────────────────────────────────────

///|
/// Build headers for OpenAI-compatible API requests.
pub fn Client::openai_headers(self : Client) -> Map[String, String] {
  {
    "Content-Type": "application/json",
    "Authorization": "Bearer \{self.api_key}",
  }
}

///|
/// Build headers for Anthropic Messages API requests.
pub fn Client::anthropic_headers(self : Client) -> Map[String, String] {
  let headers : Map[String, String] = {
    "Content-Type": "application/json",
    "x-api-key": self.api_key,
    "anthropic-version": "2023-06-01",
    "anthropic-dangerous-direct-browser-access": "true",
  }
  // For OpenRouter: also send Bearer token
  match self.provider_id {
    Some("openrouter") => headers["Authorization"] = "Bearer \{self.api_key}"
    _ => ()
  }
  headers
}

///|
/// Get the appropriate headers for this client's API type.
pub fn Client::request_headers(self : Client) -> Map[String, String] {
  if self.is_anthropic_format() {
    self.anthropic_headers()
  } else {
    self.openai_headers()
  }
}

// ── Prompt Caching ──────────────────────────────────────────────────────────

///|
/// Check if a model supports prompt caching.
/// Currently only Claude models (gen 3.5+) support cache_control.
pub fn Client::supports_prompt_caching(_ : Client, model : String) -> Bool {
  let model_lower = model.to_lower()
  // Strip "abs-" prefix used by ClackyAI Bedrock proxy
  let stripped : String = if model_lower.length() > 4 &&
    model_lower[:4].to_string() == "abs-" {
    model_lower[4:].to_string()
  } else {
    model_lower
  }
  // Must be a Claude model
  guard stripped.find("claude") is Some(_) else { return false }
  // Match gen 3.5+ or gen 4+ patterns
  has_claude_cache_gen(stripped)
}

///|
/// Check if the model string matches a Claude generation that supports caching.
fn has_claude_cache_gen(model : String) -> Bool {
  let patterns = [
    "claude-3-5", "claude-3.5", "claude-3-6", "claude-3.6", "claude-3-7", "claude-3.7",
    "claude-3-8", "claude-3.8", "claude-3-9", "claude-3.9", "-4-", "-4.", "-5-",
    "-5.", "-6-", "-6.", "-7-", "-7.", "-8-", "-8.", "-9-", "-9.",
  ]
  for pat in patterns {
    if model.find(pat) is Some(_) {
      return true
    }
  }
  false
}

// ── Error Handling ──────────────────────────────────────────────────────────

///|
/// Map an HTTP status code and response body to a project error.
/// Returns None for 200 OK, or Some(error_description) for errors.
pub fn map_http_error(status : Int, body_text : String) -> String? {
  guard status != 200 else { return None }
  let error_message = extract_error_message(body_text)

  let msg = match status {
    400 =>
      if contains_any(error_message, [
          "ThrottlingException", "unavailable", "quota",
        ]) {
        let hint = if error_message.find("quota") is Some(_) {
          " (possibly out of credits)"
        } else {
          ""
        }
        "[LLM] Rate limit or service issue: \{error_message}\{hint}"
      } else {
        "[LLM] Client request error: \{error_message}"
      }
    401 => "[LLM] Invalid API key"
    402 => "[LLM] Billing or payment issue: \{error_message}"
    403 => "[LLM] Access denied: \{error_message}"
    404 => "[LLM] API endpoint not found: \{error_message}"
    429 => "[LLM] Rate limit exceeded, please wait a moment"
    500..=599 =>
      "[LLM] Service temporarily unavailable (\{status}), retrying..."
    _ => "[LLM] Unexpected error (\{status}): \{error_message}"
  }
  Some(msg)
}

///|
/// Check if the response body is HTML (gateway error page).
pub fn is_html_response(body_text : String) -> Bool {
  let trimmed = body_text.trim_start()
  if trimmed.length() >= 9 {
    let prefix = trimmed[:9].to_string().to_lower()
    if prefix == "<!doctype" {
      return true
    }
  }
  if trimmed.length() >= 5 {
    let prefix5 = trimmed[:5].to_string().to_lower()
    if prefix5 == "<html" {
      return true
    }
  }
  false
}

///|
/// Extract a human-readable error message from a JSON error response body.
pub fn extract_error_message(raw_body : String) -> String {
  // Check for HTML response
  if is_html_response(raw_body) {
    return "Invalid API endpoint or server error (received HTML instead of JSON)"
  }

  // Try to parse as JSON
  let json = @json.parse(raw_body) catch {
    _ =>
      if raw_body.length() > 200 {
        return raw_body[:200].to_string() + "..."
      } else {
        return raw_body
      }
  }

  // Try various error message locations
  match (if json is Object(obj) { obj.get("upstreamMessage") } else { None }) {
    Some(String(msg)) if msg.length() > 0 => return msg
    _ => ()
  }
  match (if json is Object(obj) { obj.get("error") } else { None }) {
    Some(error) =>
      match (if error is Object(obj) { obj.get("message") } else { None }) {
        Some(String(msg)) => return msg
        _ => ()
      }
    _ => ()
  }
  match (if json is Object(obj) { obj.get("error") } else { None }) {
    Some(String(msg)) => return msg
    _ => ()
  }
  match (if json is Object(obj) { obj.get("message") } else { None }) {
    Some(String(msg)) => return msg
    _ => ()
  }

  // Fallback to truncated raw body
  if raw_body.length() > 200 {
    raw_body[:200].to_string() + "..."
  } else {
    raw_body
  }
}

// ── Stream Body Helpers ─────────────────────────────────────────────────────

///|
/// Add stream:true and stream_options to a JSON request body.
pub fn add_stream_options(body : Json, include_usage : Bool) -> Json {
  match body {
    Object(obj) => {
      let new_obj : Map[String, Json] = {}
      for k, v in obj {
        new_obj[k] = v
      }
      new_obj["stream"] = true.to_json()
      if include_usage {
        new_obj["stream_options"] = Json::object({
          "include_usage": true.to_json(),
        })
      }
      Json::object(new_obj)
    }
    _ => body
  }
}

///|
/// Add stream:true to a JSON request body.
pub fn add_stream_flag(body : Json) -> Json {
  match body {
    Object(obj) => {
      let new_obj : Map[String, Json] = {}
      for k, v in obj {
        new_obj[k] = v
      }
      new_obj["stream"] = true.to_json()
      Json::object(new_obj)
    }
    _ => body
  }
}

// ── Utility Functions ───────────────────────────────────────────────────────

///|
/// Check if a string contains any of the given substrings (case-insensitive).
fn contains_any(text : String, patterns : Array[String]) -> Bool {
  let lower = text.to_lower()
  for pat in patterns {
    if lower.find(pat.to_lower()) is Some(_) {
      return true
    }
  }
  false
}
