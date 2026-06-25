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
  inspect(
    state.session_id,
    content=(
      #|test-session
    ),
  )
  inspect(
    state.model_name,
    content=(
      #|test-model
    ),
  )
  inspect(state.mode, content="Idle")
  inspect(state.iterations, content="0")
  inspect(state.messages.length(), content="0")
  inspect(
    state.tool_output,
    content=(
      #|
    ),
  )
  inspect(
    state.total_cost,
    content=(
      #|0
    ),
  )
  inspect(state.latest_delta, content="0")
  inspect(
    state.input_text,
    content=(
      #|
    ),
  )
  inspect(state.last_error, content="None")
}

///|
test "TuiState fields are mutable via Ref" {
  let agent = make_test_agent()
  let state_ref = Ref::new(TuiState::from_agent(agent))

  state_ref.val.mode = Running
  inspect(state_ref.val.mode, content="Running")

  state_ref.val.agent_status = "running"
  inspect(
    state_ref.val.agent_status,
    content=(
      #|running
    ),
  )

  state_ref.val.iterations = 5
  inspect(state_ref.val.iterations, content="5")

  state_ref.val.tool_output = "test output"
  inspect(
    state_ref.val.tool_output,
    content=(
      #|test output
    ),
  )

  state_ref.val.last_error = Some("test error")
  inspect(
    state_ref.val.last_error,
    content=(
      #|Some(test error)
    ),
  )

  state_ref.val.total_cost = 0.05
  state_ref.val.cost_source = "api"
  inspect(
    state_ref.val.cost_source,
    content=(
      #|api
    ),
  )
}

///|
test "format_cost pads to 4 decimal places" {
  inspect(
    format_cost(0.0),
    content=(
      #|0.0000
    ),
  )
  inspect(
    format_cost(1.5),
    content=(
      #|1.5000
    ),
  )
  inspect(
    format_cost(0.1234),
    content=(
      #|0.1234
    ),
  )
}

///|
test "format_cost handles various cases" {
  inspect(
    format_cost(0.123456),
    content=(
      #|0.123456
    ),
  )
  inspect(
    format_cost(42.0),
    content=(
      #|42.0000
    ),
  )
  inspect(
    format_cost(100.0),
    content=(
      #|100.0000
    ),
  )
}

///|
test "handle_hook_event updates state correctly" {
  let agent = make_test_agent()
  let state_ref = Ref::new(TuiState::from_agent(agent))

  handle_hook_event(
    state_ref,
    @agent.HookEvent::StatusChanged(
      @agent.AgentStatus::Idle,
      @agent.AgentStatus::Running,
    ),
  )
  inspect(
    state_ref.val.agent_status,
    content=(
      #|running
    ),
  )

  handle_hook_event(state_ref, @agent.HookEvent::BeforeIteration(3))
  inspect(state_ref.val.iterations, content="3")

  handle_hook_event(
    state_ref,
    @agent.HookEvent::ToolExecuting("read_file", "test.txt"),
  )
  inspect(
    state_ref.val.tool_output,
    content=(
      #|Running: read_file(test.txt)
    ),
  )

  handle_hook_event(
    state_ref,
    @agent.HookEvent::ErrorOccurred("something broke"),
  )
  inspect(
    state_ref.val.last_error,
    content=(
      #|Some(something broke)
    ),
  )
  inspect(
    state_ref.val.agent_status,
    content=(
      #|error
    ),
  )
}

///|
test "handle_hook_event_simple_events_no_crash" {
  let agent = make_test_agent()
  let state_ref = Ref::new(TuiState::from_agent(agent))

  handle_hook_event(state_ref, @agent.HookEvent::BeforeLlmCall)
  handle_hook_event(state_ref, @agent.HookEvent::AfterLlmCall)
  handle_hook_event(state_ref, @agent.HookEvent::MessageAdded)
  handle_hook_event(state_ref, @agent.HookEvent::BeforeIteration(1))
  inspect(state_ref.val.iterations, content="1")
}

///|
test "handle_hook_event_ToolExecuted" {
  let agent = make_test_agent()
  let state_ref = Ref::new(TuiState::from_agent(agent))

  let entry = @agent.ToolResultEntry::{
    id: "call_1",
    content: "file contents",
    is_error: false,
  }
  handle_hook_event(
    state_ref,
    @agent.HookEvent::ToolExecuted("read_file", entry),
  )
  inspect(
    state_ref.val.tool_output,
    content=(
      #|Completed: read_file
    ),
  )
}

///|
test "TuiState::from_agent maps agent status correctly" {
  let agent = make_test_agent()
  let state = TuiState::from_agent(agent)
  inspect(
    state.agent_status,
    content=(
      #|idle
    ),
  )
}

///|
test "TuiMode equality works" {
  inspect(Idle == Idle, content="true")
  inspect(Running == Running, content="true")
  inspect(Idle != Running, content="true")
}
