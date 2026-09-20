///| Engine → typed protocol adapter (P1-1).
///
/// The engine emits rich `HookEvent` values; the wire contract is the typed
/// `@protocol.Event`. This function is the single bridge between them, so the
/// Web, TUI and CLI consumers all observe the same event vocabulary.
///
/// Values are **raw engine values**: `AgentStatus::Completed` becomes the
/// string `"completed"`. Each consumer applies its own boundary adaptation —
/// the web layer maps `"completed"` to the frontend's `"idle"` (I-028), while
/// the TUI keeps displaying the raw status.
///
/// Two engine events intentionally collapse onto one protocol value because
/// the wire cannot tell them apart: `AfterIteration` / `MessageAdded` both
/// describe "the current phase is done", and `SessionStarted` /
/// `StatusChanged(...Running)` both describe "session running".

///|
/// Convert an agent `HookEvent` into the typed protocol event.
pub fn hook_event_to_protocol(event : HookEvent) -> @protocol.Event {
  match event {
    StatusChanged(_old, new) =>
      @protocol.SessionUpdate({
        status: Some(new.to_string_value()),
        session_id: None,
        cost: None,
        cost_source: None,
        latency: None,
        session: None,
      })
    BeforeIteration(n) =>
      @protocol.Progress({
        phase: "active",
        message: Some("Thinking..."),
        progress_type: Some("thinking"),
        metadata: Some(Json::object({ "iteration": n.to_json() })),
        started_at: Some(current_time_ms().to_string()),
      })
    AfterIteration(_n) =>
      @protocol.Progress({
        phase: "done",
        message: None,
        progress_type: None,
        metadata: None,
        started_at: None,
      })
    BeforeLlmCall =>
      @protocol.PhaseStart({
        phase_id: "llm_call",
        kind: Some("llm_call"),
        label: Some("LLM call"),
      })
    AfterLlmCall => @protocol.PhaseEnd({ phase_id: "llm_call", summary: None, })
    MessageAdded =>
      @protocol.Progress({
        phase: "done",
        message: None,
        progress_type: None,
        metadata: None,
        started_at: None,
      })
    ToolExecuting(name, args) =>
      @protocol.ToolCall({
        name,
        args: Json::string(args),
        summary: None,
        created_at: None,
      })
    ToolExecuted(_name, result) =>
      if result.is_error {
        @protocol.ToolError({ error: result.content, })
      } else {
        @protocol.ToolResult({ result: result.content, created_at: None, })
      }
    ToolDenied(name) => @protocol.ToolError({ error: "Tool denied: " + name, })
    UsageUpdated(data) =>
      @protocol.TokenUsage({
        cost: data.cost,
        prompt_tokens: Some(data.prompt_tokens),
        completion_tokens: Some(data.completion_tokens),
        delta_tokens: Some(data.delta_tokens),
        total_tokens: Some(data.total_tokens),
        cost_source: Some(data.cost_source.to_string_value()),
        cache_read: Some(data.cache_read),
        cache_write: Some(data.cache_write),
      })
    ErrorOccurred(msg) => @protocol.ErrorMessage({ message: msg, })
    RunCompleted(result) =>
      @protocol.Complete({
        iterations: result.iterations,
        cost: result.total_cost_usd,
        cost_source: result.cost_source.to_string_value(),
        cache_stats: {
          total_requests: result.cache_stats.total_requests,
          cache_hit_requests: result.cache_stats.cache_hit_requests,
          cache_read_input_tokens: result.cache_stats.cache_read_input_tokens,
        },
      })
    StreamChunk(chunk) =>
      @protocol.AssistantMessage({
        content: chunk,
        role: None,
        partial: Some(true),
        created_at: None,
      })
    SessionStarted(session_id) =>
      @protocol.SessionUpdate({
        status: Some("running"),
        session_id: Some(session_id),
        cost: None,
        cost_source: None,
        latency: None,
        session: None,
      })
    SessionEnded(session_id) =>
      @protocol.SessionUpdate({
        status: Some("idle"),
        session_id: Some(session_id),
        cost: None,
        cost_source: None,
        latency: None,
        session: None,
      })
    CostUpdated(cost) =>
      @protocol.TokenUsage({
        cost,
        prompt_tokens: None,
        completion_tokens: None,
        delta_tokens: None,
        total_tokens: None,
        cost_source: None,
        cache_read: None,
        cache_write: None,
      })
    WarningOccurred(msg) => @protocol.Warning({ message: msg, })
    FileAccessed(path, op) => @protocol.FilePreview({ path, op, })
    ThinkingStarted =>
      @protocol.PhaseStart({
        phase_id: "thinking",
        kind: Some("thinking"),
        label: Some("Thinking"),
      })
    ThinkingEnded =>
      @protocol.PhaseEnd({ phase_id: "thinking", summary: None, })
    SubagentStarted(name) =>
      @protocol.PhaseStart({
        phase_id: name,
        kind: Some("skill_evolution"),
        label: Some(name),
      })
    SubagentEnded(name) =>
      @protocol.PhaseEnd({ phase_id: name, summary: None, })
    RetryAttempt(n, reason) =>
      @protocol.Progress({
        phase: "active",
        message: Some("Retrying..."),
        progress_type: Some("retry"),
        metadata: Some(
          Json::object({ "attempt": n.to_json(), "reason": reason.to_json() }),
        ),
        started_at: Some(current_time_ms().to_string()),
      })
    ToolStdout(lines) => @protocol.ToolStdout({ lines, })
    InfoMessage(msg) => @protocol.Info({ message: msg, })
    SuccessMessage(msg) => @protocol.Success({ message: msg, })
    FeedbackRequested(question, context, options) =>
      @protocol.RequestFeedback({ question, id: None, context, options, })
  }
}
