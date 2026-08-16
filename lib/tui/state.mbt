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
pub extend TuiMode with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend TuiMode with Eq::{not_equal, equal}

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
pub extend ToolExecution with @moonbitlang/core/debug.Debug::{to_repr}

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
pub extend PendingConfirmation with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// Approval dialog state (TUI-03).
pub(all) struct ApprovalDialog {
  /// Tool name requesting approval.
  mut tool_name : String
  /// Brief tool arguments summary.
  mut tool_args : String
  /// Whether details section is expanded.
  mut show_details : Bool
  /// Full detailed arguments for the details section.
  mut detailed_args : String
} derive(Debug)

///|
pub extend ApprovalDialog with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// Configuration menu dialog item (TUI-03).
pub(all) struct ConfigMenuItem {
  /// Display label.
  label : String
  /// Item value (for single-select).
  mut value : String
  /// Whether this is a multi-select item.
  multi_select : Bool
  /// Whether this item is checked (for multi-select).
  mut checked : Bool
} derive(Debug)

///|
pub extend ConfigMenuItem with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// Configuration menu dialog state (TUI-03).
pub(all) struct ConfigMenuDialog {
  /// Dialog title.
  mut title : String
  /// Menu items.
  mut items : Array[ConfigMenuItem]
  /// Currently selected item index.
  mut selected_idx : Int
  /// Checked state array (parallel to items, for multi-select).
  mut checked : Array[Bool]
} derive(Debug)

///|
pub extend ConfigMenuDialog with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// Form field for multi-field form dialogs (TUI-03).
pub(all) struct FormField {
  /// Field label.
  label : String
  /// Current input value.
  mut value : String
  /// Whether this field is required.
  required : Bool
  /// Placeholder text.
  placeholder : String
  /// Whether to mask the value in display (e.g. API keys).
  masked : Bool
} derive(Debug)

///|
pub extend FormField with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// Form dialog state (TUI-03).
pub(all) struct FormDialog {
  /// Dialog title.
  mut title : String
  /// Form fields.
  mut fields : Array[FormField]
  /// Currently focused field index.
  mut focused_idx : Int
} derive(Debug)

///|
pub extend FormDialog with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// Configuration menu mode discriminator.
pub(all) enum ConfigMode {
  /// Full config menu (add/edit/delete/switch models).
  ConfigMenu
  /// Model-only selector (switch only).
  ModelSelector
} derive(Eq, Debug)

///|
pub extend ConfigMode with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ConfigMode with Eq::{not_equal, equal}

///|
/// A config form submit waiting for its connection test to finish.
///
/// Values are already merged (empty Edit fields fell back to the existing
/// model's values) — applying the pending change needs no form access.
pub(all) struct PendingConfigTest {
  /// Which menu to return to after success.
  mode : ConfigMode
  /// Add a new card or edit an existing one.
  action : ConfigAction
  /// Target model index for Edit (-1 for Add).
  target_idx : Int
  /// Card id (from the form for Add; existing id for Edit).
  name : String
  /// Model name sent to the API.
  model : String
  /// API key.
  api_key : String
  /// Base URL.
  base_url : String
  /// Protocol flag of the card (Anthropic Messages vs OpenAI).
  anthropic_format : Bool
} derive(Debug)

///|
pub extend PendingConfigTest with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// Config form action type.
pub(all) enum ConfigAction {
  Add
  Edit
} derive(Eq, Debug)

///|
pub extend ConfigAction with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ConfigAction with Eq::{not_equal, equal}

///|
/// Level of the two-level /model drawer.
pub(all) enum ModelDrawerLevel {
  /// Level 1: model card list.
  Cards
  /// Level 2: sub-model drawer of one card.
  SubModels
} derive(Eq, Debug)

///|
pub extend ModelDrawerLevel with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend ModelDrawerLevel with Eq::{not_equal, equal}

///|
/// Unified dialog state for the TUI (TUI-03).
pub(all) enum DialogState {
  /// No dialog active.
  NoDialog
  /// Tool approval dialog.
  Approval(ApprovalDialog)
  /// Configuration menu dialog.
  ConfigMenu(ConfigMenuDialog)
  /// Multi-field form dialog.
  Form(FormDialog)
  /// Config form with mode/action tracking.
  ConfigForm(
    mode~ : ConfigMode,
    form~ : FormDialog,
    action~ : ConfigAction,
    target_idx~ : Int
  )
  /// Time Machine navigation menu (task undo/redo).
  TimeMachineMenu(ConfigMenuDialog)
  /// Two-level /model drawer (Ruby ui2 show_model_switch_modal):
  /// card list → per-card sub-model drawer.
  ModelDrawer(
    level~ : ModelDrawerLevel,
    dialog~ : ConfigMenuDialog,
    card_id~ : String,
    card_model~ : String
  )
} derive(Debug)

///|
pub extend DialogState with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// Shared state between TUI rendering and Agent hooks.
pub(all) struct TuiState {
  // ── Agent Identity ─────────────────────────────────────────
  /// Current session identifier.
  mut session_id : String
  /// Name of the LLM model in use.
  mut model_name : String
  // ── Mode ────────────────────────────────────────────────────
  /// Current TUI operating mode.
  mut mode : TuiMode

  // ── Status ──────────────────────────────────────────────────
  /// Current agent status as a display string.
  agent_status : @mizchi/signals.Signal[String]
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
  streaming_buffer : @mizchi/signals.Signal[String]
  /// Whether streaming is currently active.
  streaming_active : @mizchi/signals.Signal[Bool]

  // ── Tool Output ─────────────────────────────────────────────
  /// Latest tool execution summary text.
  tool_output : @mizchi/signals.Signal[String]
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
  mut latest_delta : Int
  /// Input token count from the most recent LLM call.
  mut last_input_tokens : Int
  /// Output token count from the most recent LLM call.
  mut last_output_tokens : Int

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

  // ── Dialog State (TUI-03) ────────────────────────────────────
  /// Active dialog state (NoDialog when none).
  mut dialog : DialogState

  // ── Thinking Buffer (TUI-04) ─────────────────────────────────
  /// Buffer for live thinking/reasoning stream display.
  thinking_buffer : @mizchi/signals.Signal[String]
  // ── Tick Counter (for spinner animation) ────────────────────────
  /// Increments on every Tick event; used by StatusBar spinner.
  mut tick_count : Int
  // ── Run Timing (TUI-04) ──────────────────────────────────────────
  /// Millisecond timestamp when the current agent run started.
  mut run_start_ts : Int64
  /// Total iterations in the current run (mirrors `iterations` but
  /// available for the completion summary after RunCompleted).
  mut total_iterations : Int
  /// Whether the user has pressed Shift+Tab to approve all tools
  /// for the remainder of this session.
  mut approved_all_tools : Bool
  // ── Time Machine (TUI-05) ────────────────────────────────────────
  /// Time machine state for undo/redo task history.
  /// Rebound on /clear (task history belongs to the old session).
  mut time_machine : @agent.TimeMachineState
  // ── Paste Placeholders (TUI-05) ──────────────────────────────────
  /// Counter for paste placeholder numbering ([#1 Paste Text], ...).
  mut paste_placeholder_count : Int
  /// Stored paste texts keyed by placeholder number for expansion on submit.
  mut paste_placeholders : Array[(Int, String)]
}

///|
/// Create a new TuiState from an Agent's current state.
pub fn TuiState::from_agent(agent : @agent.Agent) -> TuiState {
  {
    session_id: agent.session_id,
    model_name: agent.client.model,
    mode: Idle,
    agent_status: @mizchi/signals.signal(agent.status.to_string_value()),
    iterations: agent.iterations,
    working_dir: agent.working_dir,
    permission_mode: agent.config.permission_mode.to_string_value(),
    active_tasks: agent.todo_manager.size(),
    messages: [],
    streaming_buffer: @mizchi/signals.signal(""),
    streaming_active: @mizchi/signals.signal(false),
    tool_output: @mizchi/signals.signal(""),
    current_tool_name: "",
    current_tool_args: "",
    tool_history: [],
    llm_call_count: 0,
    llm_calling: false,
    phase_stack: [],
    total_cost: agent.total_cost,
    cost_source: agent.cost_source.to_string_value(),
    latest_delta: 0,
    last_input_tokens: 0,
    last_output_tokens: 0,
    input_text: "",
    last_error: None,
    progress_stack: ProgressStack::new(),
    todo_area: TodoArea::new(),
    pending_confirmation: None,
    theme: Theme::default_(),
    dialog: DialogState::NoDialog,
    thinking_buffer: @mizchi/signals.signal(""),
    tick_count: 0,
    run_start_ts: 0L,
    total_iterations: 0,
    approved_all_tools: false,
    time_machine: @agent.TimeMachineState::new(agent.session_id),
    paste_placeholder_count: 0,
    paste_placeholders: [],
  }
}

///|
/// Cycle the permission mode between the two interactive states:
/// ConfirmSafes ⇄ AutoApprove (spec tui-parity-05, task 2).
/// ConfirmAll (non-interactive default) falls back to ConfirmSafes.
pub fn cycle_permission_mode(
  mode : @config.PermissionMode,
) -> @config.PermissionMode {
  match mode {
    @config.AutoApprove => @config.ConfirmSafes
    @config.ConfirmSafes => @config.AutoApprove
    @config.ConfirmAll => @config.ConfirmSafes
  }
}

///|
/// Reset TUI-side session state after `Agent::reset_session` (Ruby
/// cli.rb:1011-1026): status bar shows the new session id, zero tasks and
/// $0.0; todo display cleared and hidden; the time machine is rebound to
/// the new session (task history belongs to the old one); mirrored
/// messages/streaming state dropped. Shared by the TUI controller and the
/// eval adapter so both stay in lockstep.
pub fn reset_tui_session_state(state : TuiState, agent : @agent.Agent) -> Unit {
  state.session_id = agent.session_id
  state.model_name = agent.client.model
  state.iterations = 0
  state.total_iterations = 0
  state.active_tasks = 0
  state.total_cost = 0.0
  state.messages.clear()
  state.streaming_buffer.set("")
  state.streaming_active.set(false)
  state.tool_output.set("")
  state.todo_area.update([], 0, 0)
  state.todo_area.hide()
  state.time_machine = @agent.TimeMachineState::new(agent.session_id)
}

///|
/// Look up a paste placeholder text by its number.
pub fn TuiState::get_paste_placeholder(self : TuiState, num : Int) -> String? {
  for pair in self.paste_placeholders {
    let (n, text) = pair
    if n == num {
      return Some(text)
    }
  }
  None
}

///|
/// Expand all paste placeholders in the given text.
/// Every occurrence of each `[#N Paste Text]` tag is replaced.
pub fn TuiState::expand_paste_placeholders(
  self : TuiState,
  text : String,
) -> String {
  let mut result = text
  for pair in self.paste_placeholders {
    let (n, stored) = pair
    let tag = "[#\{n} Paste Text]"
    result = result.replace_all(old=tag, new=stored)
  }
  result
}

///|
/// Clear all stored paste placeholders (called after submit).
pub fn TuiState::clear_paste_placeholders(self : TuiState) -> Unit {
  self.paste_placeholder_count = 0
  self.paste_placeholders.clear()
}
