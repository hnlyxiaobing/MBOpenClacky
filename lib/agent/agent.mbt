///|
/// An agent session that manages conversation history and tool execution.
pub(all) struct Agent {
  session_id : String
  name : String
  history : Array[@message.Message]
  iterations : Int
  total_cost : Double
  working_dir : String
  created_at : String
  status : AgentStatus
  error : String?
  source : AgentSource
  reasoning_effort : String?
  pinned : Bool
} derive(Eq, Debug)

///|
/// Create a new agent with default values.
pub fn Agent::new(
  session_id : String,
  name : String,
  working_dir : String,
) -> Agent {
  {
    session_id,
    name,
    history: [],
    iterations: 0,
    total_cost: 0.0,
    working_dir,
    created_at: "",
    status: Idle,
    error: None,
    source: Manual,
    reasoning_effort: None,
    pinned: false,
  }
}
