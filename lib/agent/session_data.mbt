///| Session data serialization for persisting and restoring Agent state.

///| Phase 4 implements the data structures and conversion methods.

///| Actual file I/O persistence is deferred to Phase 6.

///| Reference: openclacky/lib/clacky/agent/session_serializer.rb

///|

///|
/// Snapshot of an Agent session's statistics.
pub(all) struct SessionStats {
  total_iterations : Int
  total_cost_usd : Double
  total_tasks : Int
  cost_source : String
  cache_creation_input_tokens : Int
  cache_read_input_tokens : Int
  total_requests : Int
  cache_hit_requests : Int
} derive(Eq, Debug)

///|
/// Complete serializable snapshot of an Agent session.
pub(all) struct SessionData {
  session_id : String
  name : String
  messages : Array[@message.Message]
  stats : SessionStats
  working_dir : String
  created_at : String
  source : String
  reasoning_effort : String?
  model_name : String?
} derive(Eq, Debug)

///|
/// Export the current agent state as a SessionData snapshot.
pub fn Agent::to_session_data(self : Agent) -> SessionData {
  {
    session_id: self.session_id,
    name: self.name,
    messages: self.history.map(m => m.to_api_message()),
    stats: {
      total_iterations: self.iterations,
      total_cost_usd: self.total_cost,
      total_tasks: self.total_tasks,
      cost_source: self.cost_source.to_string_value(),
      cache_creation_input_tokens: self.cache_stats.cache_creation_input_tokens,
      cache_read_input_tokens: self.cache_stats.cache_read_input_tokens,
      total_requests: self.cache_stats.total_requests,
      cache_hit_requests: self.cache_stats.cache_hit_requests,
    },
    working_dir: self.working_dir,
    created_at: self.created_at,
    source: self.source.to_string_value(),
    reasoning_effort: self.reasoning_effort,
    model_name: Some(self.client.model),
  }
}

///|
/// Restore agent state from a SessionData snapshot.
///
/// Resets runtime counters and rebuilds conversation history.
pub fn Agent::restore_from_session(self : Agent, data : SessionData) -> Unit {
  // Restore identity
  self.working_dir = data.working_dir

  // Restore conversation history
  self.history.clear()
  for msg in data.messages {
    self.history.push(msg)
  }

  // Restore statistics
  self.iterations = data.stats.total_iterations
  self.total_cost = data.stats.total_cost_usd
  self.total_tasks = data.stats.total_tasks

  // Restore cache stats
  self.cache_stats = CacheStats::new()
  self.cache_stats.cache_creation_input_tokens = data.stats.cache_creation_input_tokens
  self.cache_stats.cache_read_input_tokens = data.stats.cache_read_input_tokens
  self.cache_stats.total_requests = data.stats.total_requests
  self.cache_stats.cache_hit_requests = data.stats.cache_hit_requests

  // Restore reasoning effort
  self.reasoning_effort = data.reasoning_effort

  // Reset transient state
  self.status = Idle
  self.error = None
  self.latest_latency = None
  self.fallback_state = PrimaryOk
  self.compression_level = 0
  self.previous_total_tokens = 0
  self.mock_responses.clear()
}
