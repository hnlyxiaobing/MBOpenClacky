///|
/// An agent session that manages conversation history and tool execution.
///
/// The Agent struct is the central orchestrator for the ReAct loop,
/// coordinating LLM calls, tool execution, cost tracking, and
/// conversation management.
///
/// Reference: openclacky/lib/clacky/agent.rb
pub(all) struct Agent {
  // ── Identity & Session ─────────────────────────────────────────────
  mut session_id : String
  mut name : String
  mut working_dir : String
  created_at : String
  source : AgentSource
  // ── Core Dependencies ──────────────────────────────────────────────
  mut client : @client.Client
  mut config : @config.AgentConfig
  mut tool_registry : @tool.ToolRegistry
  // ── Skill, Memory & Task System ───────────────────────────────────
  mut skill_registry : @skill.SkillRegistry
  mut memory_store : MemoryStore?
  mut todo_manager : TodoManager
  mut agent_pool : AgentPool
  // ── Session-scoped Model Overlay ─────────────────────────────────
  /// Per-session sub-model overlay (Ruby agent.set_session_sub_model):
  /// when set, request building uses it instead of the config card's
  /// model name. Persisted via SessionData.sub_model, never in config.yml.
  mut session_sub_model : String?
  // ── Conversation State ─────────────────────────────────────────────
  history : Array[@message.Message]
  mut iterations : Int
  mut total_tasks : Int
  mut status : AgentStatus
  mut error : String?
  mut error_code : String?
  mut top_up_url : String?
  mut raw_message : String?
  mut reasoning_effort : String?
  pinned : Bool
  // ── Cost & Cache Tracking ──────────────────────────────────────────
  mut total_cost : Double
  mut cost_source : CostSource
  mut cache_stats : CacheStats
  mut previous_total_tokens : Int
  // ── LLM Call State ─────────────────────────────────────────────────
  mut latest_latency : @client.Latency?
  mut fallback_state : FallbackState
  mut fallback_model : String?
  mut url_fallback_active : Bool
  mut consecutive_retryable_failures : Int
  mut fallback_activated_at_ms : Int64
  // ── Compression State ──────────────────────────────────────────────
  mut compression_level : Int
  mut idle_timer : IdleCompressionTimer
  // ── Upstream Truncation Retry ─────────────────────────────────────
  /// One-shot [SYSTEM] truncation hint injected per task (mirrors Ruby's
  /// @task_upstream_truncation_hint_injected): reset at the start of
  /// `Agent::run`, set on the first UpstreamTruncatedError within a task.
  mut upstream_truncation_hint_injected : Bool
  // ── Hook System ─────────────────────────────────────────────────
  /// Hook manager for lifecycle event observers.
  hook_manager : HookManager
  // ── Patch System ────────────────────────────────────────────────
  /// Ordered chain of patch rules evaluated before/after every tool call.
  /// Owned by the Agent; extension patches are folded in at construction
  /// or via `register_patch_rule`. An empty chain is a no-op.
  patch_chain : PatchChain
  // ── Confirmation ──────────────────────────────────────────────────
  /// UI confirmation callback: (tool_name, args_summary) -> approved?
  /// None = headless (tools needing confirmation are denied).
  mut confirmation_callback : ((String, String) -> Bool)?
  /// Async confirmation: agent pushes (tool_name, args) and awaits response.
  /// Set by TUI controller for interactive mode.
  mut confirmation_request : @aqueue.Queue[(String, String)]?
  mut confirmation_response : @aqueue.Queue[Bool]?
  // ── Feedback ─────────────────────────────────────────────────────
  /// Async feedback: agent pushes (question, context, options) and awaits response.
  /// Set by WS controller for interactive mode; None = headless (feedback denied).
  mut feedback_request : @aqueue.Queue[(String, String?, Array[String]?)]?
  mut feedback_response : @aqueue.Queue[String]?
  // ── Test Support ─────────────────────────────────────────────────
  /// call_llm pops and returns the first element instead of
  /// making a real API call.
  mock_responses : Array[@client.LlmResponse]
}

///|
/// Fallback state machine for model switching.
///
/// State transitions:
/// - PrimaryOk → FallbackActive: after 3 consecutive RetryableErrors
/// - FallbackActive → Probing: after cooldown period expires
/// - Probing → PrimaryOk: on successful probe call
/// - Probing → FallbackActive: on failed probe call (resets cooldown)
pub(all) enum FallbackState {
  PrimaryOk
  FallbackActive(Int)
  Probing
} derive(Eq, Debug)

///|
pub extend FallbackState with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend FallbackState with Eq::{not_equal, equal}

///|
/// Create a new agent with the given client and configuration.
pub fn Agent::new(
  session_id : String,
  name : String,
  working_dir : String,
  client : @client.Client,
  config : @config.AgentConfig,
) -> Agent {
  {
    session_id,
    name,
    working_dir,
    created_at: current_timestamp_iso(),
    source: Manual,
    // Core dependencies
    client,
    config,
    tool_registry: @tool.make_default_registry(),
    // Skill, memory & task system
    skill_registry: @skill.SkillRegistry::new(),
    memory_store: None,
    todo_manager: TodoManager::new(),
    agent_pool: AgentPool::new(4, 4),
    session_sub_model: None,
    // Conversation state
    history: [],
    iterations: 0,
    total_tasks: 0,
    status: Idle,
    error: None,
    error_code: None,
    top_up_url: None,
    raw_message: None,
    reasoning_effort: None,
    pinned: false,
    // Cost tracking
    total_cost: 0.0,
    cost_source: Estimated,
    cache_stats: CacheStats::new(),
    previous_total_tokens: 0,
    // LLM call state
    latest_latency: None,
    fallback_state: PrimaryOk,
    fallback_model: None,
    url_fallback_active: false,
    consecutive_retryable_failures: 0,
    fallback_activated_at_ms: 0L,
    // Compression
    compression_level: 0,
    idle_timer: IdleCompressionTimer::new(),
    // Upstream truncation retry
    upstream_truncation_hint_injected: false,
    // Clear any hook callbacks from prior runs
    hook_manager: HookManager::new(),
    // Empty patch chain — extension patches are added via
    // `register_patch_rule` after extensions have been discovered.
    patch_chain: PatchChain::new(),
    // No confirmation callback by default (headless mode)
    confirmation_callback: None,
    confirmation_request: None,
    confirmation_response: None,
    // Feedback (headless by default)
    feedback_request: None,
    feedback_response: None,
    // Test support
    mock_responses: [],
  }
}

///|
/// Rename the agent (in-memory). Callers that need persistence should
/// follow up with `save_session(agent.to_session_data())`.
pub fn Agent::rename(self : Agent, new_name : String) -> Unit {
  self.name = new_name
}

///|
/// Register an additional patch rule on the agent's chain.
///
/// Rules accumulate in registration order. Use this to fold in rules
/// loaded from extension manifests via `lib/extension/patch_loader`.
pub fn Agent::register_patch_rule(self : Agent, rule : PatchRule) -> Unit {
  self.patch_chain.add_rule(rule)
}

///|
/// Read-only access to the agent's patch chain (for inspection / tests).
pub fn Agent::patch_chain_view(self : Agent) -> PatchChain {
  self.patch_chain
}

///|
/// Get the current model name from the client configuration.
pub fn Agent::current_model(self : Agent) -> String {
  self.client.model
}

///|
/// Rebuild the LLM client from the CURRENT agent config.
///
/// Used after a model switch and by `/clear`. Never reuse the old client:
/// it may carry stale model state from before a `/config` switch (Ruby
/// cli.rb:1004-1008 documents the DSK → Opus 404 regression that caused).
/// The api_type is re-derived from the new card (anthropic_format flag,
/// falling back to the provider preset for its base_url) — carrying over
/// the old api_type would break cross-protocol switches (e.g. OpenAI card
/// → Claude card). Vision support is carried over (connection-level).
pub fn Agent::rebuild_client_from_config(self : Agent) -> Unit {
  match self.config.current_model() {
    Some(m) => {
      let api_type = if m.anthropic_format {
        @config.AnthropicMessages
      } else {
        @config.Providers::api_type_for_model(m.base_url, m.model)
      }
      self.client = @client.Client::new(
        m.api_key,
        m.base_url,
        m.model,
        api_type,
        provider_id=self.client.provider_id,
        vision_supported=self.client.vision_supported,
      )
    }
    None => ()
  }
}

///|
/// Set (or clear) the per-session sub-model overlay.
///
/// The overlay replaces the config card's model name when building LLM
/// requests; it is persisted in the session file (SessionData.sub_model),
/// never in config.yml (Ruby agent.set_session_sub_model).
pub fn Agent::set_session_sub_model(self : Agent, sub_model : String?) -> Unit {
  self.session_sub_model = sub_model
}

///|
/// The model name used for primary (non-fallback) LLM requests:
/// the session sub-model overlay when set, otherwise the config model.
pub fn Agent::effective_primary_model(self : Agent) -> String {
  match self.session_sub_model {
    Some(m) if m.length() > 0 => m
    _ => self.client.model
  }
}

///|
/// Reset the agent to a fresh session, in place (Ruby `/clear`,
/// cli.rb:998-1026).
///
/// In-place field reset (rather than replacing the Agent reference) because
/// the same Agent object is shared by the TUI controller, hook handler, web
/// handlers, and eval adapter — rebinding all of them would be fragile.
///
/// Steps mirror the original order: cancel the idle timer FIRST (stale
/// timers must never fire against the new session), then reset identity,
/// conversation, cost, LLM/fallback/compression state, rebuild the client
/// from the current config, and finally rebind a fresh idle timer and todo
/// manager.
pub fn Agent::reset_session(self : Agent) -> Unit {
  // 1. Cancel the idle timer before resetting (Ruby cli.rb:1002).
  self.idle_timer.cancel()
  // 2. New session identity.
  self.session_id = generate_session_id()
  // 3. Conversation state.
  self.history.clear()
  self.iterations = 0
  self.total_tasks = 0
  self.status = Idle
  self.error = None
  self.error_code = None
  self.top_up_url = None
  self.raw_message = None
  // 4. Cost & cache tracking.
  self.total_cost = 0.0
  self.cost_source = Estimated
  self.cache_stats = CacheStats::new()
  self.previous_total_tokens = 0
  // 5. LLM call & fallback state.
  self.latest_latency = None
  self.fallback_state = PrimaryOk
  self.fallback_model = None
  self.url_fallback_active = false
  self.consecutive_retryable_failures = 0
  self.fallback_activated_at_ms = 0L
  // 6. Compression state and the per-session sub-model overlay.
  self.compression_level = 0
  self.session_sub_model = None
  // 7. Rebuild the client from the current config (see the warning on
  // rebuild_client_from_config — never reuse the old client).
  self.rebuild_client_from_config()
  // 8. Fresh todo manager and idle timer (Ruby cli.rb:1011-1020 rebind).
  self.todo_manager = TodoManager::new()
  self.idle_timer = IdleCompressionTimer::new()
}

///|
/// Set the reasoning effort level.
/// Values "off", "none", or "" are normalized to None.
pub fn Agent::set_reasoning_effort(self : Agent, value : String?) -> Unit {
  self.reasoning_effort = normalize_reasoning_effort(value)
}

///|
/// Normalize reasoning effort string to canonical form.
fn normalize_reasoning_effort(value : String?) -> String? {
  match value {
    None => None
    Some(v) => {
      let lower = v.to_lower().trim().to_owned()
      if lower == "" || lower == "off" || lower == "none" {
        None
      } else {
        Some(lower)
      }
    }
  }
}
