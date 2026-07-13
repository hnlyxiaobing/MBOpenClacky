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
} derive(Eq, Debug)

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
/// Pending confirmation data for tool approval prompts.
///
/// Set when the agent requests user confirmation for a tool call.
/// The TUI renders this as an inline dialog and reads a key synchronously.
pub(all) struct PendingConfirmation {
  /// Name of the tool requesting confirmation.
  tool_name : String
  /// Brief summary of tool arguments.
  tool_args : String
  /// Full prompt text shown to the user.
  prompt_text : String
  /// Whether the default action (Enter) is "yes".
  default_yes : Bool
} derive(Debug)

///|
/// Shared state between TUI rendering and Agent hooks.
pub(all) struct TuiState {
  // ── Agent Identity ─────────────────────────────────────────
  /// Current session identifier.
  mut session_id : String
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
  /// Current working directory.
  mut working_dir : String
  /// Permission mode.
  mut permission_mode : String
  /// Active task count.
  mut active_tasks : Int

  // ── Messages ────────────────────────────────────────────────
  /// Formatted message lines for display ("[ROLE] content").
  mut messages : Array[String]

  // ── Streaming ─────────────────────────────────────────────────
  /// Buffer for accumulating streaming LLM output.
  mut streaming_buffer : String
  /// Whether streaming is currently active.
  mut streaming_active : Bool

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

  // ── Progress ────────────────────────────────────────────────
  /// Stack-based progress tracker for spinner animation.
  progress_stack : ProgressStack

  // ── Sidebar ─────────────────────────────────────────────────
  // (Removed in Phase 6.5: sidebar_panel deprecated, inline mode doesn't use it)

  // ── Session Bar ───────────────────────────────────────────────
  // (Removed in Phase 6.5: session_bar deprecated, merged into status_bar.mbt)

  // ── Todo Area ─────────────────────────────────────────────────
  /// Todo area displaying active task list.
  todo_area : TodoArea

  // ── Confirmation ──────────────────────────────────────────────
  /// Pending confirmation prompt for tool approval (None = no pending).
  mut pending_confirmation : PendingConfirmation?

  // ── Theme ─────────────────────────────────────────────────
  /// Current UI theme for rendering.
  mut theme : Theme
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
    working_dir: agent.working_dir,
    permission_mode: agent.config.permission_mode.to_string_value(),
    active_tasks: agent.todo_manager.size(),
    messages: [],
    streaming_buffer: "",
    streaming_active: false,
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
    progress_stack: ProgressStack::new(),
    todo_area: TodoArea::new(),
    pending_confirmation: None,
    theme: Theme::default_(),
  }
}
