///|
/// Tests for context-aware command suggestions (bare "/" reordering).

///|
/// Minimal TuiState for suggestion tests (mirrors modal_lifecycle_wbtest).
fn suggestion_test_state() -> TuiState {
  {
    session_id: "test",
    model_name: "test-model",
    mode: Idle,
    agent_status: @mizchi/signals.signal("idle"),
    iterations: 0,
    working_dir: "/tmp",
    permission_mode: "confirm_safes",
    active_tasks: 0,
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
    total_cost: 0.0,
    cost_source: "estimated",
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
    time_machine: @agent.TimeMachineState::new("test"),
    paste_placeholder_count: 0,
    paste_placeholders: [],
  }
}

///|
test "context suggestions: error context promotes /clear and /undo" {
  let state = suggestion_test_state()
  state.last_error = Some("boom")
  let suggestions = CommandSuggestions::new()
  suggestions.update_context_filter(state)
  // Context items lead the list...
  assert_eq(suggestions.filtered[0].name, "/clear")
  assert_eq(suggestions.filtered[1].name, "/undo")
  // ...but every command stays visible (context reorders, never hides).
  assert_eq(suggestions.filtered.length(), suggestions.commands.length())
  assert_true(suggestions.is_visible())
}

///|
test "context suggestions: file-write context promotes /undo" {
  let state = suggestion_test_state()
  state.tool_history.push({
    name: "write_file",
    args: "{}",
    completed: true,
    result_summary: "",
  })
  let suggestions = CommandSuggestions::new()
  suggestions.update_context_filter(state)
  assert_eq(suggestions.filtered[0].name, "/undo")
}

///|
test "context suggestions: neutral context promotes /help" {
  let state = suggestion_test_state()
  let suggestions = CommandSuggestions::new()
  suggestions.update_context_filter(state)
  assert_eq(suggestions.filtered[0].name, "/help")
  assert_eq(suggestions.filtered.length(), suggestions.commands.length())
}

///|
test "context suggestions: no duplicates between context items and rest" {
  let state = suggestion_test_state()
  state.last_error = Some("boom")
  let suggestions = CommandSuggestions::new()
  suggestions.update_context_filter(state)
  let names : Array[String] = []
  for item in suggestions.filtered {
    assert_true(!names.contains(item.name))
    names.push(item.name)
  }
}
