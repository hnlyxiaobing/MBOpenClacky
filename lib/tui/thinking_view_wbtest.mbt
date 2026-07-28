///|
/// Tests for Thinking Live View rendering.
fn make_test_state_with_thinking(buffer : String, active : Bool) -> TuiState {
  let state = {
    session_id: "test",
    model_name: "test-model",
    mode: Idle,
    agent_status: @mizchi/signals.signal("thinking"),
    iterations: 1,
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
    llm_call_count: 1,
    llm_calling: true,
    phase_stack: if active {
      ["llm_call", "thinking"]
    } else {
      ["llm_call"]
    },
    total_cost: 0.001,
    cost_source: "estimated",
    latest_delta: 100,
    last_input_tokens: 0,
    last_output_tokens: 0,
    input_text: "",
    last_error: None,
    progress_stack: ProgressStack::new(),
    todo_area: TodoArea::new(),
    pending_confirmation: None,
    theme: Theme::default_(),
    dialog: DialogState::NoDialog,
    shell_mode: ShellMode::Chat,
    thinking_buffer: @mizchi/signals.signal(buffer),
    tick_count: 0,
    run_start_ts: 0L,
    total_iterations: 0,
    approved_all_tools: false,
    time_machine: @agent.TimeMachineState::new("test"),
    paste_placeholder_count: 0,
    paste_placeholders: [],
  }
  state
}

///|
test "thinking: empty buffer returns Empty node" {
  let state = make_test_state_with_thinking("", true)
  let animator = ThinkingVerbAnimator::new()
  let node = render_thinking_live_view(state, animator)
  assert_true(node is Node::Empty)
}

///|
test "thinking: active renders Border with Thinking title" {
  let state = make_test_state_with_thinking(
    "Analyzing the problem\nStep 1\nStep 2", true,
  )
  let animator = ThinkingVerbAnimator::new()
  let node = render_thinking_live_view(state, animator)
  let text = node_to_text(node)
  assert_true(text.contains("Thinking"))
  assert_true(text.contains("Step 1"))
  assert_true(text.contains("Step 2"))
}

///|
test "thinking: inactive shows summary text" {
  let state = make_test_state_with_thinking("Some thinking content here", false)
  let animator = ThinkingVerbAnimator::new()
  let node = render_thinking_live_view(state, animator)
  let text = node_to_text(node)
  assert_true(text.contains("Thought"))
}

///|
test "thinking: summary returns Empty for empty buffer" {
  let state = make_test_state_with_thinking("", false)
  let node = render_thinking_summary(state)
  assert_true(node is Node::Empty)
}

///|
test "thinking: summary shows char and line count" {
  let state = make_test_state_with_thinking("Line 1\nLine 2\nLine 3", false)
  let node = render_thinking_summary(state)
  let text = node_to_text(node)
  assert_true(text.contains("Thought"))
  assert_true(text.contains("chars"))
  assert_true(text.contains("lines"))
}

///|
test "thinking: is_thinking_phase_active detects thinking" {
  let active = make_test_state_with_thinking("test", true)
  assert_true(is_thinking_phase_active(active))
  let inactive = make_test_state_with_thinking("test", false)
  assert_false(is_thinking_phase_active(inactive))
}

///|
test "thinking: truncate_thinking_buffer caps size" {
  let long_text = "x".repeat(20000)
  let state = make_test_state_with_thinking(long_text, true)
  truncate_thinking_buffer(state)
  assert_true(state.thinking_buffer.get().length() <= thinking_max_buffer_size)
}

///|
test "thinking: format_full includes llm_call_count and iterations" {
  let state = make_test_state_with_thinking("", true)
  let bar = StatusBar::new()
  bar.format_full(state)
  let text = bar.plain_text()
  assert_true(text.contains("1 calls"))
  assert_true(text.contains("1 iters"))
}

///|
test "thinking: format_from_state excludes calls/iters (SPEC-02)" {
  let state = make_test_state_with_thinking("", true)
  let bar = StatusBar::new()
  bar.format_from_state(state)
  let text = bar.plain_text()
  assert_false(text.contains("calls"))
  assert_false(text.contains("iters"))
}

///|
test "thinking: format_full includes thinking indicator" {
  let state = make_test_state_with_thinking("test", true)
  let bar = StatusBar::new()
  bar.format_full(state)
  let text = bar.plain_text()
  assert_true(text.contains("thinking"))
  assert_true(text.contains("tok"))
}
