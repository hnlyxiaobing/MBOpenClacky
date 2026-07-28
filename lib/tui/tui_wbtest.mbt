///|
/// Tests for TUI state management and utility functions.
///
/// These tests cover the pure logic of the TUI package:
/// - TuiState construction and initialization
/// - Hook event handling (state transitions)
/// - Cost formatting
///
/// Note: Full TUI rendering tests require a terminal and are
/// not included in this unit test suite.

///|
/// Helper to create a minimal Agent for testing.
fn make_test_agent() -> @agent.Agent {
  let client = @client.Client::new(
    "test-key",
    "https://test.api.com",
    "test-model",
    @config.OpenAICompletions,
  )
  let config = @config.AgentConfig::default()
  @agent.Agent::new("test-session", "test-agent", "/tmp", client, config)
}

///|
test "TuiState::from_agent creates correct initial state" {
  let agent = make_test_agent()
  let state = TuiState::from_agent(agent)
  @debug.debug_inspect(
    state.session_id,
    content=(
      #|"test-session"
    ),
  )
  @debug.debug_inspect(
    state.model_name,
    content=(
      #|"test-model"
    ),
  )
  @debug.debug_inspect(state.mode, content="Idle")
  @debug.debug_inspect(state.iterations, content="0")
  @debug.debug_inspect(state.messages.length(), content="0")
  @debug.debug_inspect(
    state.tool_output.get(),
    content=(
      #|""
    ),
  )
  @debug.debug_inspect(
    state.total_cost,
    content=(
      #|0
    ),
  )
  @debug.debug_inspect(state.latest_delta, content="0")
  @debug.debug_inspect(
    state.input_text,
    content=(
      #|""
    ),
  )
  @debug.debug_inspect(state.last_error, content="None")
}

///|
test "TuiState fields are mutable via Ref" {
  let agent = make_test_agent()
  let state_ref = Ref(TuiState::from_agent(agent))

  state_ref.val.mode = Running
  @debug.debug_inspect(state_ref.val.mode, content="Running")

  state_ref.val.agent_status.set("running")
  @debug.debug_inspect(
    state_ref.val.agent_status.get(),
    content=(
      #|"running"
    ),
  )

  state_ref.val.iterations = 5
  @debug.debug_inspect(state_ref.val.iterations, content="5")

  state_ref.val.tool_output.set("test output")
  @debug.debug_inspect(
    state_ref.val.tool_output.get(),
    content=(
      #|"test output"
    ),
  )

  state_ref.val.last_error = Some("test error")
  @debug.debug_inspect(
    state_ref.val.last_error,
    content=(
      #|Some("test error")
    ),
  )

  state_ref.val.total_cost = 0.05
  state_ref.val.cost_source = "api"
  @debug.debug_inspect(
    state_ref.val.cost_source,
    content=(
      #|"api"
    ),
  )
}

///|
test "format_cost pads to 4 decimal places" {
  @debug.debug_inspect(
    format_cost(0.0),
    content=(
      #|"0.0000"
    ),
  )
  @debug.debug_inspect(
    format_cost(1.5),
    content=(
      #|"1.5000"
    ),
  )
  @debug.debug_inspect(
    format_cost(0.1234),
    content=(
      #|"0.1234"
    ),
  )
}

///|
test "format_cost handles various cases" {
  @debug.debug_inspect(
    format_cost(0.123456),
    content=(
      #|"0.123456"
    ),
  )
  @debug.debug_inspect(
    format_cost(42.0),
    content=(
      #|"42.0000"
    ),
  )
  @debug.debug_inspect(
    format_cost(100.0),
    content=(
      #|"100.0000"
    ),
  )
}

///|
test "handle_hook_event updates state correctly" {
  let agent = make_test_agent()
  let state_ref = Ref(TuiState::from_agent(agent))

  dispatch_hook_event(
    state_ref,
    default_hook_config(),
    None,
    None,
    @agent.HookEvent::StatusChanged(
      @agent.AgentStatus::Idle,
      @agent.AgentStatus::Running,
    ),
  )
  @debug.debug_inspect(
    state_ref.val.agent_status.get(),
    content=(
      #|"running"
    ),
  )

  dispatch_hook_event(
    state_ref,
    default_hook_config(),
    None,
    None,
    @agent.HookEvent::BeforeIteration(3),
  )
  @debug.debug_inspect(state_ref.val.iterations, content="3")

  dispatch_hook_event(
    state_ref,
    default_hook_config(),
    None,
    None,
    @agent.HookEvent::ToolExecuting("read_file", "test.txt"),
  )
  @debug.debug_inspect(
    state_ref.val.tool_output.get(),
    content=(
      #|"Running: read_file(test.txt)"
    ),
  )

  dispatch_hook_event(
    state_ref,
    default_hook_config(),
    None,
    None,
    @agent.HookEvent::ErrorOccurred("something broke"),
  )
  @debug.debug_inspect(
    state_ref.val.last_error,
    content=(
      #|Some("something broke")
    ),
  )
  @debug.debug_inspect(
    state_ref.val.agent_status.get(),
    content=(
      #|"error"
    ),
  )
}

///|
test "handle_hook_event_simple_events_no_crash" {
  let agent = make_test_agent()
  let state_ref = Ref(TuiState::from_agent(agent))

  dispatch_hook_event(
    state_ref,
    default_hook_config(),
    None,
    None,
    @agent.HookEvent::BeforeLlmCall,
  )
  dispatch_hook_event(
    state_ref,
    default_hook_config(),
    None,
    None,
    @agent.HookEvent::AfterLlmCall,
  )
  dispatch_hook_event(
    state_ref,
    default_hook_config(),
    None,
    None,
    @agent.HookEvent::MessageAdded,
  )
  dispatch_hook_event(
    state_ref,
    default_hook_config(),
    None,
    None,
    @agent.HookEvent::BeforeIteration(1),
  )
  @debug.debug_inspect(state_ref.val.iterations, content="1")
}

///|
test "handle_hook_event_ToolExecuted" {
  let agent = make_test_agent()
  let state_ref = Ref(TuiState::from_agent(agent))

  let entry = @agent.ToolResultEntry::{
    id: "call_1",
    content: "file contents",
    is_error: false,
  }
  dispatch_hook_event(
    state_ref,
    default_hook_config(),
    None,
    None,
    @agent.HookEvent::ToolExecuted("read_file", entry),
  )
  @debug.debug_inspect(
    state_ref.val.tool_output.get(),
    content=(
      #|"Completed: read_file"
    ),
  )
}

///|
test "TuiState::from_agent maps agent status correctly" {
  let agent = make_test_agent()
  let state = TuiState::from_agent(agent)
  @debug.debug_inspect(
    state.agent_status.get(),
    content=(
      #|"idle"
    ),
  )
}

///|
test "TuiMode equality works" {
  @debug.debug_inspect(Idle == Idle, content="true")
  @debug.debug_inspect(Running == Running, content="true")
  @debug.debug_inspect(Idle != Running, content="true")
}
