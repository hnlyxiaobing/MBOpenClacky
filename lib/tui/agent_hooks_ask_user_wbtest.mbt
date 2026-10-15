///|
/// Regression test for BUG-0061: the ask_user family must not print the generic
/// `[=>] ask_user(...)` / `[<=] ask_user ...` lines next to its card.
///
/// Ruby's `show_tool_call` returns early for that family
/// (`agent.rb`: `unless Tools::AskUser.feedback_tool? ... show_tool_call`) and
/// `ui2/ui_controller.rb` renders only the question card, so printing the tool
/// call *and* the card showed the question twice.

///|
fn ask_user_tui_state() -> @agent.Agent {
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
/// Join an output buffer's visible lines for substring assertions.
fn joined_output_lines(buf : OutputBuffer, n : Int32) -> String {
  let mut acc = ""
  for line in buf.tail_lines(n) {
    acc = acc + line + "\n"
  }
  acc
}

///|
test "ask_user_family_skips_tool_call_and_result_lines" {
  let agent = ask_user_tui_state()
  let state_ref = Ref(TuiState::from_agent(agent))
  let output = OutputBuffer::new()
  let config = default_hook_config()
  // 1. ask_user call: state bookkeeping still happens, no visible line.
  dispatch_hook_event(
    state_ref,
    config,
    None,
    Some(output),
    @agent.HookEvent::ToolExecuting(
      "ask_user", "{\"questions\":[{\"question\":\"Which database?\"}]}",
    ),
  )
  assert_eq(state_ref.val.agent_status.get(), "tool_call")
  assert_eq(state_ref.val.current_tool_name, "ask_user")
  assert_false(joined_output_lines(output, 20).contains("ask_user"))
  // The legacy alias spelling is suppressed too.
  dispatch_hook_event(
    state_ref,
    config,
    None,
    Some(output),
    @agent.HookEvent::ToolExecuting("request_user_feedback", "{}"),
  )
  assert_false(
    joined_output_lines(output, 20).contains("request_user_feedback"),
  )
  // 2. ask_user result: no visible line either.
  dispatch_hook_event(
    state_ref,
    config,
    None,
    Some(output),
    @agent.HookEvent::ToolExecuted("ask_user", @agent.ToolResultEntry::{
      id: "c1",
      content: "**Question #1:** Which database?",
      is_error: false,
      image_inject: None,
    }),
  )
  assert_eq(state_ref.val.agent_status.get(), "tool_done")
  // The rendered card text must not leak through the tool-result line.
  assert_false(
    joined_output_lines(output, 20).contains("**Question #1:** Which database?"),
  )
  // 3. The FeedbackRequested card is what the user sees.
  dispatch_hook_event(
    state_ref,
    config,
    None,
    Some(output),
    @agent.HookEvent::FeedbackRequested("Which database?", None, None, [
      @tool.AskQuestion::{
        question: "Which database?",
        description: "",
        options: ["PostgreSQL", "SQLite"],
        multi: false,
        allow_free_text: true,
        recommended: Some(0),
      },
    ]),
  )
  let card_view = joined_output_lines(output, 20)
  assert_true(card_view.contains("Which database?"))
  assert_true(card_view.contains("PostgreSQL"))
  assert_true(card_view.contains("recommended"))
  // 4. Control: an ordinary tool still renders both lines.
  dispatch_hook_event(
    state_ref,
    config,
    None,
    Some(output),
    @agent.HookEvent::ToolExecuting("read_file", "{\"path\":\"a.txt\"}"),
  )
  dispatch_hook_event(
    state_ref,
    config,
    None,
    Some(output),
    @agent.HookEvent::ToolExecuted("read_file", @agent.ToolResultEntry::{
      id: "c2",
      content: "file contents",
      is_error: false,
      image_inject: None,
    }),
  )
  let tool_view = joined_output_lines(output, 20)
  assert_true(tool_view.contains("read_file"))
  assert_true(tool_view.contains("file contents"))
}
