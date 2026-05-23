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
/// Perform an LLM API call, returning the response.
///
/// Call flow:
/// 1. If mock_responses is non-empty, pop and return the first element.
/// 2. Build a SendRequest from history + tool definitions.
/// 3. Call client.build_request_body (sync stub — real HTTP in Phase 5+).
/// 4. On RetryableError: accumulate; after retries_before_fallback, try fallback.
/// 5. On BadRequestError with "context": handle_context_overflow.
/// 6. On success: handle_probe_success + track_cost.
///
/// Raises AgentError if no mock is available and HTTP is not wired.
pub fn Agent::call_llm(self : Agent) -> @client.LlmResponse raise {
  // ── Mock path (testing) ────────────────────────────────────────────
  if self.mock_responses.length() > 0 {
    let response = self.mock_responses.remove(0)
    // Track cost if usage is present
    match response.usage {
      Some(usage) => self.track_cost(usage) |> ignore
      None => ()
    }
    return response
  }

  // ── Real path (Phase 5+ HTTP) ──────────────────────────────────────
  // Build the request (validates the pipeline even without HTTP)
  let _request = self.build_send_request()
  let _body = self.client.build_request_body(_request)

  // No HTTP transport wired yet — raise a descriptive error
  raise @errors.AgentError(
    "LLM HTTP transport not yet available. Use mock_responses for testing.",
  )
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
