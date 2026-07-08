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
  session_id : String
  name : String
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
  // ── Conversation State ─────────────────────────────────────────────
  history : Array[@message.Message]
  mut iterations : Int
  mut total_tasks : Int
  mut status : AgentStatus
  mut error : String?
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
  // ── Compression State ──────────────────────────────────────────────
  mut compression_level : Int
  // ── Hook System ─────────────────────────────────────────────────
  /// Hook manager for lifecycle event observers.
  hook_manager : HookManager
  // ── Confirmation ──────────────────────────────────────────────────
  /// UI confirmation callback: (tool_name, args_summary) -> approved?
  /// None = headless (tools needing confirmation are denied).
  mut confirmation_callback : ((String, String) -> Bool)?
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
    created_at: current_timestamp_ms(),
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
    // Conversation state
    history: [],
    iterations: 0,
    total_tasks: 0,
    status: Idle,
    error: None,
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
    // Compression
    compression_level: 0,
    // Clear any hook callbacks from prior runs
    hook_manager: HookManager::new(),
    // No confirmation callback by default (headless mode)
    confirmation_callback: None,
    // Test support
    mock_responses: [],
  }
}

///|
/// Get the current model name from the client configuration.
pub fn Agent::current_model(self : Agent) -> String {
  self.client.model
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
