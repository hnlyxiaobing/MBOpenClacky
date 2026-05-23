///| Run result types for Agent sessions.

///| Reference: openclacky/lib/clacky/agent.rb (build_result)

///|

///|
/// Status of a completed agent run.
pub(all) enum RunStatus {
  Success
  Error
  Interrupted
} derive(Eq, Debug)

///|
/// Result returned after an agent run completes.
pub(all) struct RunResult {
  status : RunStatus
  session_id : String
  iterations : Int
  total_cost_usd : Double
  cost_source : CostSource
  cache_stats : CacheStats
  error : String?
} derive(Eq, Debug)

///|
/// Build a RunResult from the current agent state.
fn Agent::build_result(
  self : Agent,
  status : RunStatus,
  error? : String? = None,
) -> RunResult {
  {
    status,
    session_id: self.session_id,
    iterations: self.iterations,
    total_cost_usd: self.total_cost,
    cost_source: self.cost_source,
    cache_stats: self.cache_stats,
    error,
  }
}
