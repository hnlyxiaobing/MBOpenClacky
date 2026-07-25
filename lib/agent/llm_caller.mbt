///| LLM caller with retry logic and Fallback state machine.

///| Manages the actual API call lifecycle: building requests,

///| consuming mock responses (test), handling errors, and

///| transitioning the Fallback state machine.

///| Reference: openclacky/lib/clacky/agent/llm_caller.rb

///|

///|
/// Number of consecutive RetryableErrors before activating fallback.
pub let retries_before_fallback : Int = 3

///|
/// Maximum retry attempts when operating on the fallback model.
pub let max_retries_on_fallback : Int = 5

///|
/// Cooldown period (seconds) before probing the primary model again.
pub let fallback_cooldown_seconds : Int = 1800

///|
/// Mode for context overflow recovery.
pub(all) enum OverflowMode {
  /// Remove 1 message from tail (preserves prompt cache hits).
  Standard
  /// Remove half the history (sacrifices cache for space).
  Aggressive
} derive(Eq, Debug)

///|
/// Record the details of a failed LLM call for the session summary (fix-09).
///
/// error_code is extracted from the provider error body; per upstream
/// semantics (client.rb raise_error) an HTTP 402 also maps to
/// "insufficient_credit" regardless of the body. top_up_url resolves to the
/// current provider preset's website_url — never a hardcoded console, since
/// the agent may run against any provider.
fn Agent::record_llm_error(self : Agent, status : Int, body : String) -> Unit {
  let extracted = @client.extract_error_code(body)
  let code = if extracted == Some("insufficient_credit") || status == 402 {
    Some("insufficient_credit")
  } else {
    extracted
  }
  self.error_code = code
  self.raw_message = Some(@client.extract_error_message(body))
  match code {
    Some(c) if c == "insufficient_credit" =>
      self.top_up_url = self.provider_website_url()
    _ => ()
  }
}

///|
/// Clear the recorded LLM error after a successful call, so a transient
/// failure that was retried away (e.g. 429/5xx) does not leak into the
/// session summary of an otherwise healthy session.
fn Agent::clear_llm_error(self : Agent) -> Unit {
  self.error_code = None
  self.top_up_url = None
  self.raw_message = None
}

///|
/// Website of the current provider (used as the top-up link), resolved from
/// the provider preset by provider_id first, then by base_url. Returns None
/// for custom/unknown providers — the frontend simply hides the link then.
fn Agent::provider_website_url(self : Agent) -> String? {
  match self.client.provider_id {
    Some(id) =>
      match @config.Providers::find(id) {
        Some(p) => return p.website_url
        None => ()
      }
    None => ()
  }
  match @config.Providers::resolve(self.client.base_url) {
    Some(p) => p.website_url
    None => None
  }
}

///|
/// Async LLM API call: performs the API request via non-blocking HTTP.
/// Mock path returns immediately (no HTTP). Real path uses http_post_async.
pub async fn Agent::call_llm_async(self : Agent) -> @client.LlmResponse {
  // ── Mock path (testing) ────────────────────────────────────────────
  if self.mock_responses.length() > 0 {
    let response = self.mock_responses.remove(0)
    match response.usage {
      Some(usage) => self.track_cost(usage) |> ignore
      None => ()
    }
    return response
  }

  // ── Real HTTP path (async, non-blocking) ───────────────────────
  let request = self.build_send_request()
  let body_json = self.client.build_request_body(request)
  let url = self.client.request_url()
  let headers_map = self.client.request_headers()
  let headers_arr : Array[(String, String)] = []
  for k, v in headers_map {
    headers_arr.push((k, v))
  }
  let body_str = body_json.stringify()
  let http_result = @client.http_post_async(url, body_str, headers_arr, 60000)
  match http_result {
    Err(err) =>
      raise @errors.RetryableError(
        "HTTP request failed (url=\{url}): \{err.to_repr()}",
      )
    Ok(http_resp) => {
      match @client.map_http_error(http_resp.status_code, http_resp.body) {
        Some(err_msg) => {
          self.record_llm_error(http_resp.status_code, http_resp.body)
          let detail = "\{err_msg} | url=\{url} status=\{http_resp.status_code} body=\{body_snippet(http_resp.body, 500)}"
          if http_resp.status_code == 429 ||
            (http_resp.status_code >= 500 && http_resp.status_code <= 599) {
            raise @errors.RetryableError(detail)
          }
          raise @errors.BadRequestError(http_resp.status_code, detail)
        }
        None => ()
      }
      if @client.is_html_response(http_resp.body) {
        raise @errors.AgentError(
          "LLM API returned HTML response (invalid endpoint): url=\{url} body=\{body_snippet(http_resp.body, 500)}",
        )
      }
      let json_data = @json.parse(http_resp.body) catch {
        _ =>
          raise @errors.AgentError(
            "Failed to parse LLM API response as JSON: url=\{url} body=\{body_snippet(http_resp.body, 500)}",
          )
      }
      let response = self.client.parse_response(json_data)
      match response.usage {
        Some(usage) => self.track_cost(usage) |> ignore
        None => ()
      }
      self.clear_llm_error()
      response
    }
  }
}

///|
/// Async streaming LLM API call: requests an SSE stream and invokes
/// `on_chunk` with each visible content delta as it arrives, while
/// reassembling the full response with the provider's stream aggregator.
///
/// - Mock path: emits the whole content as one chunk, returns immediately.
/// - Bedrock: no SSE-over-HTTP transport — falls back to `call_llm_async`.
/// - OpenAI-compatible: `stream:true` + `stream_options.include_usage`.
/// - Anthropic: `stream:true`.
///
/// Error semantics match `call_llm_async` (HTTP error mapping, HTML check,
/// cost tracking). If the stream breaks mid-way, the partial content
/// already emitted stays in the consumer's streaming buffer until the
/// RunCompleted/ErrorOccurred hooks clear it.
pub async fn Agent::call_llm_stream_async(
  self : Agent,
  on_chunk : (String) -> Unit,
) -> @client.LlmResponse {
  // ── Mock path (testing) ────────────────────────────────────────────
  if self.mock_responses.length() > 0 {
    let response = self.mock_responses.remove(0)
    match response.content {
      Some(c) => if c.length() > 0 { on_chunk(c) }
      None => ()
    }
    match response.usage {
      Some(usage) => self.track_cost(usage) |> ignore
      None => ()
    }
    return response
  }

  // ── Bedrock: no SSE-over-HTTP streaming, fall back ─────────────
  if self.client.is_bedrock_format() {
    return self.call_llm_async()
  }

  // ── Real HTTP path (async SSE streaming) ───────────────────────
  let is_anthropic = self.client.is_anthropic_format()
  let request = self.build_send_request()
  let body_json0 = self.client.build_request_body(request)
  let body_json = if is_anthropic {
    @client.add_stream_flag(body_json0)
  } else {
    @client.add_stream_options(body_json0, true)
  }
  let url = self.client.request_url()
  let headers_map = self.client.request_headers()
  let headers_arr : Array[(String, String)] = []
  for k, v in headers_map {
    headers_arr.push((k, v))
  }
  let body_str = body_json.stringify()

  let openai_agg = @client.OpenAiStreamAggregator::new()
  let anthropic_agg = @client.AnthropicStreamAggregator::new()
  let on_frame = fn(frame : @client.SseFrame) {
    let delta = if is_anthropic {
      anthropic_agg.handle_delta(frame.event, frame.data)
    } else {
      openai_agg.handle_delta(frame.data)
    }
    if delta.length() > 0 {
      on_chunk(delta)
    }
  }

  let http_result = @client.http_post_stream_async(
    url, body_str, headers_arr, 60000, on_frame,
  )
  match http_result {
    Err(err) =>
      raise @errors.RetryableError(
        "HTTP request failed (url=\{url}): \{err.to_repr()}",
      )
    Ok(http_resp) => {
      match @client.map_http_error(http_resp.status_code, http_resp.body) {
        Some(err_msg) => {
          self.record_llm_error(http_resp.status_code, http_resp.body)
          let detail = "\{err_msg} | url=\{url} status=\{http_resp.status_code} body=\{body_snippet(http_resp.body, 500)}"
          if http_resp.status_code == 429 ||
            (http_resp.status_code >= 500 && http_resp.status_code <= 599) {
            raise @errors.RetryableError(detail)
          }
          raise @errors.BadRequestError(http_resp.status_code, detail)
        }
        None => ()
      }
      if @client.is_html_response(http_resp.body) {
        raise @errors.AgentError(
          "LLM API returned HTML response (invalid endpoint): url=\{url} body=\{body_snippet(http_resp.body, 500)}",
        )
      }
      let response = if is_anthropic {
        anthropic_agg.to_response()
      } else {
        openai_agg.to_response()
      }
      match response.usage {
        Some(usage) => self.track_cost(usage) |> ignore
        None => ()
      }
      self.clear_llm_error()
      response
    }
  }
}

///|
/// Build a SendRequest from the current agent state.
pub fn Agent::build_send_request(self : Agent) -> @client.SendRequest {
  let messages = self.messages_for_api()
  let defs = self.tool_registry.all_definitions()
  let tools_json : Array[Json] = []
  for def in defs {
    tools_json.push(def.to_json())
  }
  {
    messages,
    model: self.client.model,
    tools: tools_json,
    max_tokens: self.config.max_tokens,
    enable_caching: self.config.enable_prompt_caching,
    reasoning_effort: self.reasoning_effort,
  }
}

///|
/// Prepare messages for API submission by stripping internal fields.
pub fn Agent::messages_for_api(self : Agent) -> Array[@message.Message] {
  let result : Array[@message.Message] = []
  for msg in self.history {
    result.push(msg.to_api_message())
  }
  result
}

// ── Fallback State Machine ────────────────────────────────────────────────────

///|
/// Attempt to activate the fallback model after repeated failures.
///
/// Returns true if fallback was activated, false if no fallback configured.
pub fn Agent::try_activate_fallback(
  self : Agent,
  _current_model : String,
) -> Bool {
  match self.fallback_model {
    None => false
    Some(_) => {
      self.fallback_state = FallbackActive(0)
      true
    }
  }
}

///|
/// Handle a successful probe: reset to PrimaryOk state.
pub fn Agent::handle_probe_success(self : Agent) -> Unit {
  match self.fallback_state {
    Probing => self.fallback_state = PrimaryOk
    _ => ()
  }
}

///|
/// Handle a failed probe: stay in FallbackActive with a fresh cooldown.
pub fn Agent::handle_probe_failure(self : Agent) -> Unit {
  match self.fallback_state {
    Probing => self.fallback_state = FallbackActive(0)
    _ => ()
  }
}

// ── Error Detection ───────────────────────────────────────────────────────────

///|
/// Detect upstream truncation in the response.
///
/// Raises UpstreamTruncatedError if the response contains truncated
/// tool call arguments (incomplete JSON).
pub fn Agent::detect_upstream_truncation(
  response : @client.LlmResponse,
) -> Unit raise {
  match response.tool_calls {
    Some(calls) =>
      for call in calls {
        let args_str = call.function.arguments
        if !is_valid_json(args_str) {
          let name = call.function.name
          raise @errors.UpstreamTruncatedError(
            "Tool call '\{name}' has truncated arguments",
          )
        }
      }
    None => ()
  }
}

///|
/// Handle context overflow by removing messages from history.
///
/// Standard mode: removes the last non-system message.
/// Aggressive mode: removes half the non-system messages.
///
/// Returns true if messages were removed, false if history is too small.
pub fn Agent::handle_context_overflow(
  self : Agent,
  mode : OverflowMode,
) -> Bool {
  let history = self.history
  // Find the first non-system message index
  let mut first_non_system = history.length()
  for i in 0..<history.length() {
    if history[i].role != @message.System {
      first_non_system = i
      break
    }
  }
  let removable = history.length() - first_non_system
  if removable <= 0 {
    return false
  }
  let remove_count = match mode {
    Standard => 1
    Aggressive => {
      let half = removable / 2
      if half < 1 {
        1
      } else {
        half
      }
    }
  }
  let actual_remove = if remove_count < removable {
    remove_count
  } else {
    removable
  }
  // Remove from the end
  for _ in 0..<actual_remove {
    history.pop() |> ignore
  }
  self.compression_level = self.compression_level + 1
  true
}

// ── Internal Helpers ──────────────────────────────────────────────────────────

///|
/// Return the first `max_chars` characters of `body` for diagnostics.
/// Appends "..." when the body was truncated.
fn body_snippet(body : String, max_chars : Int) -> String {
  let buf = StringBuilder::new()
  let mut count = 0
  let mut truncated = false
  for c in body {
    if count >= max_chars {
      truncated = true
      break
    }
    buf.write_char(c)
    count = count + 1
  }
  if truncated {
    buf.write_string("...")
  }
  buf.to_string()
}

///|
/// Check if a string is valid JSON (simple heuristic for truncation detection).
fn is_valid_json(s : String) -> Bool {
  let trimmed = s.trim()
  if trimmed.length() == 0 {
    return false
  }
  // Try parsing
  try {
    @json.parse(trimmed) |> ignore
    true
  } catch {
    _ => false
  }
}
