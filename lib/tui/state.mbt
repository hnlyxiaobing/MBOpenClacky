///|
/// Shared mutable state for the TUI application.
///
/// All TUI components read from a single `Ref[TuiState]` to render
/// the current view. The state is updated by hook callbacks during
/// Agent execution, and by user input during idle mode.

///|
/// Operating mode of the TUI.
pub(all) enum TuiMode {
  /// User can type messages and browse history.
  Idle
  /// Agent is executing (ReAct loop is on the call stack).
  Running
} derive(Eq, Debug, Show)

///|
/// A record of a tool execution for display in the tool panel.
pub(all) struct ToolExecution {
  /// Tool name.
  name : String
  /// Tool arguments (JSON string).
  args : String
  /// Whether the tool has completed.
  mut completed : Bool
  /// Result summary (set after completion).
  mut result_summary : String
} derive(Debug)

///|
/// Shared state between TUI rendering and Agent hooks.
pub(all) struct TuiState {
  // ── Agent Identity ─────────────────────────────────────────
  /// Current session identifier.
  session_id : String
  /// Name of the LLM model in use.
  model_name : String

  // ── Mode ────────────────────────────────────────────────────
  /// Current TUI operating mode.
  mut mode : TuiMode

  // ── Status ──────────────────────────────────────────────────
  /// Current agent status as a display string.
  mut agent_status : String
  /// Number of completed iterations.
  mut iterations : Int

  // ── Messages ────────────────────────────────────────────────
  /// Formatted message lines for display ("[ROLE] content").
  mut messages : Array[String]

  // ── Tool Output ─────────────────────────────────────────────
  /// Latest tool execution summary text.
  mut tool_output : String
  /// Name of the currently executing tool (empty if none).
  mut current_tool_name : String
  /// Arguments of the currently executing tool.
  mut current_tool_args : String
  /// History of tool executions in the current run.
  mut tool_history : Array[ToolExecution]

  // ── LLM Call Tracking ──────────────────────────────────────
  /// Number of LLM calls made in the current run.
  mut llm_call_count : Int
  /// Whether an LLM call is currently in progress.
  mut llm_calling : Bool

  // ── Phase Stack ─────────────────────────────────────────────
  /// Stack of active phase names (e.g., "thinking", "tool_call").
  mut phase_stack : Array[String]

  // ── Cost ────────────────────────────────────────────────────
  /// Total accumulated cost in USD.
  mut total_cost : Double
  /// Source of the cost data.
  mut cost_source : String
  /// Token delta from the most recent LLM call.
  latest_delta : Int

  // ── Input ───────────────────────────────────────────────────
  /// Current text input content (shared with TextInput).
  input_text : String

  // ── Error ───────────────────────────────────────────────────
  /// Most recent error message, if any.
  mut last_error : String?
} derive(Debug)

///|
/// Create a new TuiState from an Agent's current state.
pub fn TuiState::from_agent(agent : @agent.Agent) -> TuiState {
  {
    session_id: agent.session_id,
    model_name: agent.client.model,
    mode: Idle,
    agent_status: agent.status.to_string_value(),
    iterations: agent.iterations,
    messages: [],
    tool_output: "",
    current_tool_name: "",
    current_tool_args: "",
    tool_history: [],
    llm_call_count: 0,
    llm_calling: false,
    phase_stack: [],
    total_cost: agent.total_cost,
    cost_source: agent.cost_source.to_string_value(),
    latest_delta: 0,
    input_text: "",
    last_error: None,
  }
}
