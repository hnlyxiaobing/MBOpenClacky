///|
/// Tests for modal lifecycle state machine and dialog rendering.

///|
/// Helper: create a minimal TuiState for testing
fn test_state() -> TuiState {
  {
    session_id: "test",
    model_name: "test-model",
    mode: Idle,
    agent_status: "idle",
    iterations: 0,
    working_dir: "/tmp",
    permission_mode: "confirm_safes",
    active_tasks: 0,
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
    total_cost: 0.0,
    cost_source: "estimated",
    latest_delta: 0,
    input_text: "",
    last_error: None,
    progress_stack: ProgressStack::new(),
    todo_area: TodoArea::new(),
    pending_confirmation: None,
    theme: Theme::default_(),
  }
}

// ══════════════════════════════════════════════════════════════════════
// Modal Lifecycle State Machine Tests
// ══════════════════════════════════════════════════════════════════════

///|
test "modal: no pending confirmation returns None" {
  let state = test_state()
  let result = handle_confirmation_input(state, Some('y'), false, false)
  assert_true(result == None)
}

///|
test "modal: y key approves" {
  let state = test_state()
  request_confirmation(
    state, "terminal", "rm -rf /tmp/cache", "Run: rm -rf /tmp/cache",
  )
  let result = handle_confirmation_input(state, Some('y'), false, false)
  assert_true(result == Some(true))
}

///|
test "modal: n key denies" {
  let state = test_state()
  request_confirmation(
    state, "write", "/etc/passwd", "Modify file: /etc/passwd",
  )
  let result = handle_confirmation_input(state, Some('n'), false, false)
  assert_true(result == Some(false))
}

///|
test "modal: uppercase Y approves" {
  let state = test_state()
  request_confirmation(state, "terminal", "ls", "Run: ls")
  let result = handle_confirmation_input(state, Some('Y'), false, false)
  assert_true(result == Some(true))
}

///|
test "modal: uppercase N denies" {
  let state = test_state()
  request_confirmation(state, "terminal", "ls", "Run: ls")
  let result = handle_confirmation_input(state, Some('N'), false, false)
  assert_true(result == Some(false))
}

///|
test "modal: Enter uses default_yes=false" {
  let state = test_state()
  request_confirmation(
    state,
    "terminal",
    "rm -rf /tmp",
    "Run: rm -rf /tmp",
    default_yes=false,
  )
  let result = handle_confirmation_input(state, None, true, false)
  assert_true(result == Some(false))
}

///|
test "modal: Enter uses default_yes=true" {
  let state = test_state()
  request_confirmation(state, "terminal", "ls", "Run: ls", default_yes=true)
  let result = handle_confirmation_input(state, None, true, false)
  assert_true(result == Some(true))
}

///|
test "modal: Escape denies" {
  let state = test_state()
  request_confirmation(state, "terminal", "rm -rf /tmp", "Run: rm -rf /tmp")
  let result = handle_confirmation_input(state, None, false, true)
  assert_true(result == Some(false))
}

///|
test "modal: non-confirmation key returns None" {
  let state = test_state()
  request_confirmation(state, "terminal", "ls", "Run: ls")
  let result = handle_confirmation_input(state, Some('x'), false, false)
  assert_true(result == None)
}

///|
test "modal: has_pending_confirmation" {
  let state = test_state()
  assert_false(has_pending_confirmation(state))
  request_confirmation(state, "terminal", "ls", "Run: ls")
  assert_true(has_pending_confirmation(state))
}

///|
test "modal: consume clears state" {
  let state = test_state()
  request_confirmation(state, "terminal", "ls", "Run: ls")
  assert_true(has_pending_confirmation(state))
  consume_confirmation(state)
  assert_false(has_pending_confirmation(state))
}

///|
test "modal: confirmation_prompt_text" {
  let state = test_state()
  @debug.assert_eq(confirmation_prompt_text(state), "")
  request_confirmation(
    state, "write", "/tmp/test.txt", "Modify file: /tmp/test.txt",
  )
  @debug.assert_eq(
    confirmation_prompt_text(state),
    "Modify file: /tmp/test.txt",
  )
}

// ══════════════════════════════════════════════════════════════════════
// Dialog Rendering Tests
// ══════════════════════════════════════════════════════════════════════

///|
test "dialog: render_confirmation_lines empty when no pending" {
  let state = test_state()
  let lines = render_confirmation_lines(state)
  @debug.assert_eq(lines.length(), 0)
}

///|
test "dialog: render_confirmation_lines shows tool name and prompt" {
  let state = test_state()
  request_confirmation(
    state, "terminal", "rm -rf /tmp/cache", "Run: rm -rf /tmp/cache",
  )
  let lines = render_confirmation_lines(state)
  @debug.assert_eq(lines.length(), 1)
  let line = lines[0]
  assert_true(line.contains("terminal"))
  assert_true(line.contains("Run: rm -rf /tmp/cache"))
  assert_true(line.contains("[y/N]"))
}

///|
test "dialog: default_yes shows [Y/n]" {
  let state = test_state()
  request_confirmation(state, "terminal", "ls", "Run: ls", default_yes=true)
  let lines = render_confirmation_lines(state)
  let line = lines[0]
  assert_true(line.contains("[Y/n]"))
}

///|
test "dialog: render_confirmation_line returns single string" {
  let state = test_state()
  request_confirmation(state, "write", "/tmp/test", "Modify file: /tmp/test")
  let line = render_confirmation_line(state)
  assert_true(line.length() > 0)
  assert_true(line.contains("write"))
}

///|
test "dialog: render_confirmation_line empty when no pending" {
  let state = test_state()
  let line = render_confirmation_line(state)
  @debug.assert_eq(line, "")
}

///|
test "dialog: clear_confirmation_sequence produces ANSI" {
  let seq = clear_confirmation_sequence()
  assert_true(seq.contains("\r"))
  assert_true(seq.contains("\u{1b}[K"))
}

///|
test "dialog: build_tool_prompt for terminal" {
  let prompt = build_tool_prompt("terminal", "rm -rf /tmp/cache")
  assert_true(prompt.contains("Run:"))
  assert_true(prompt.contains("rm -rf /tmp/cache"))
}

///|
test "dialog: build_tool_prompt for write" {
  let prompt = build_tool_prompt("write", "/etc/passwd")
  assert_true(prompt.contains("Modify file:"))
}

///|
test "dialog: build_tool_prompt truncates long args" {
  let long_args = "a".repeat(100)
  let prompt = build_tool_prompt("terminal", long_args)
  assert_true(prompt.contains("..."))
}

///|
test "dialog: build_tool_prompt for unknown tool" {
  let prompt = build_tool_prompt("custom_tool", "arg1 arg2")
  assert_true(prompt.contains("Execute"))
}
