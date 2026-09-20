///| Roundtrip property tests for the typed engine protocol (P1-1).
///
/// The contract under test: `Event::parse` is the inverse of `Event::to_json`.
/// Because the bodies contain nested `Json`, the assertion compares the
/// re-serialized JSON (`to_json(parse(to_json(e))) == to_json(e)`) rather than
/// the enum values, which also proves that no field is dropped by `parse`.

///|
/// Assert that one event survives a full JSON roundtrip.
fn assert_event_roundtrip(e : Event) -> Unit raise {
  let before = e.to_json().stringify()
  match Event::parse(e.to_json()) {
    None => fail("Event::parse returned None for \{e.type_name()}")
    Some(back) => {
      assert_eq(back.type_name(), e.type_name())
      assert_eq(back.to_json().stringify(), before)
    }
  }
}

///|
/// Assert that one command survives a full JSON roundtrip.
fn assert_command_roundtrip(c : Command) -> Unit raise {
  let before = c.to_json().stringify()
  match Command::parse(c.to_json()) {
    None => fail("Command::parse returned None for \{c.type_name()}")
    Some(back) => {
      assert_eq(back.type_name(), c.type_name())
      assert_eq(back.to_json().stringify(), before)
    }
  }
}

///|
/// One sample per `Event` variant, exercising both present and absent
/// optional fields.
fn event_samples() -> Array[Event] {
  [
    SessionUpdate({
      status: Some("running"),
      session_id: None,
      cost: None,
      cost_source: None,
      latency: None,
      session: None,
    }),
    SessionUpdate({
      status: Some("idle"),
      session_id: Some("s-1"),
      cost: None,
      cost_source: None,
      latency: None,
      session: None,
    }),
    SessionUpdate({
      status: None,
      session_id: None,
      cost: Some(0.25),
      cost_source: Some("provider"),
      latency: None,
      session: None,
    }),
    SessionUpdate({
      status: None,
      session_id: None,
      cost: None,
      cost_source: None,
      latency: Some(Json::object({ "total_ms": (12).to_json() })),
      session: None,
    }),
    Progress({
      phase: "active",
      message: Some("Thinking..."),
      progress_type: Some("thinking"),
      metadata: Some(Json::object({ "iteration": (2).to_json() })),
      started_at: Some("1700000000000"),
    }),
    Progress({
      phase: "done",
      message: None,
      progress_type: None,
      metadata: None,
      started_at: None,
    }),
    PhaseStart({
      phase_id: "llm_call",
      kind: Some("llm_call"),
      label: Some("LLM call"),
    }),
    PhaseEnd({ phase_id: "llm_call", summary: None, }),
    PhaseEnd({ phase_id: "sub-1", summary: Some("done"), }),
    ToolCall({
      name: "read",
      args: Json::object({ "path": "a.mbt".to_json() }),
      summary: None,
      created_at: None,
    }),
    ToolCall({
      name: "write",
      args: Json::null(),
      summary: Some(Json::string("4 lines")),
      created_at: None,
    }),
    ToolResult({ result: "ok", created_at: None, }),
    ToolError({ error: "Tool denied: terminal", }),
    ErrorMessage({ message: "boom", }),
    Complete({
      iterations: 3,
      cost: 0.0123,
      cost_source: "provider",
      cache_stats: {
        total_requests: 4,
        cache_hit_requests: 1,
        cache_read_input_tokens: 120,
      },
    }),
    AssistantMessage({
      content: "hello",
      role: Some("assistant"),
      partial: Some(true),
      created_at: None,
    }),
    AssistantMessage({
      content: "",
      role: None,
      partial: None,
      created_at: Some("1700000000000"),
    }),
    TokenUsage({
      cost: 0.01,
      prompt_tokens: Some(10),
      completion_tokens: Some(20),
      delta_tokens: Some(30),
      total_tokens: Some(30),
      cost_source: Some("provider"),
      cache_read: Some(5),
      cache_write: Some(6),
    }),
    TokenUsage({
      cost: 0.0,
      prompt_tokens: None,
      completion_tokens: None,
      delta_tokens: None,
      total_tokens: None,
      cost_source: None,
      cache_read: None,
      cache_write: None,
    }),
    TokenDelta({ content: "tok", }),
    Warning({ message: "careful", }),
    Info({ message: "fyi", }),
    Success({ message: "done", }),
    FilePreview({ path: "lib/a.mbt", op: "write", }),
    ToolStdout({ lines: "line1\nline2\n", }),
    RequestFeedback({
      question: "Continue?",
      id: Some("f-1"),
      context: Some("ctx"),
      options: Some(["yes", "no"]),
    }),
    RequestFeedback({
      question: "Continue?",
      id: None,
      context: None,
      options: None,
    }),
    RequestConfirmation({
      id: "c-1",
      message: "Allow tool \"terminal\" to execute?",
    }),
    Interrupted,
    SessionRestored({
      session: Json::object({ "session_id": "s-1".to_json() }),
    }),
    SessionRenamed({ name: "Renamed", }),
    SessionDeleted,
    HistoryUserMessage({
      content: "hi",
      role: "user",
      created_at: Some("1700000000000"),
      system_injected: None,
    }),
    TaskFinished({ session_id: "s-1", }),
    FeedbackResponse({ request_id: "f-1", received: true, }),
    ConfirmationResponse({ request_id: "c-1", confirmed: false, }),
    Connected({ session_id: "s-1", }),
    Subscribed({ session_id: "s-1", }),
    SessionList({
      sessions: [Json::object({ "session_id": "s-1".to_json() })],
      has_more: true,
      cron_count: 2,
      latest_cron_updated_at: Some(Json::string("1700000000000")),
    }),
    SessionList({
      sessions: [],
      has_more: false,
      cron_count: 0,
      latest_cron_updated_at: None,
    }),
    Pong,
  ]
}

///|
test "roundtrip: every Event variant survives to_json/parse" {
  for e in event_samples() {
    assert_event_roundtrip(e)
  }
}

///|
test "roundtrip: every Command variant survives to_json/parse" {
  let commands : Array[Command] = [
    Subscribe({ session_id: Some("s-1"), }),
    Subscribe({ session_id: None, }),
    Message({ content: "hi", session_id: Some("s-1"), }),
    EditMessage({ content: "hi", session_id: None, id: Some("m-1"), }),
    Interrupt({ session_id: Some("s-1"), }),
    Confirmation({ id: "c-1", confirmed: true, session_id: Some("s-1"), }),
    Feedback({ id: "f-1", content: "yes", session_id: Some("s-1"), }),
    RunTask({ session_id: Some("s-1"), }),
    Ping,
    ListSessions,
  ]
  for c in commands {
    assert_command_roundtrip(c)
  }
}

///|
test "parse: unknown event type returns None" {
  assert_true(Event::parse(Json::object({ "type": "nope".to_json() })) is None)
  assert_true(Event::parse(Json::string("not an object")) is None)
  assert_true(Event::parse(Json::object(Map([]))) is None)
}

///|
test "parse: missing required field returns None" {
  // progress requires phase; error requires message.
  assert_true(
    Event::parse(Json::object({ "type": "progress".to_json() })) is None,
  )
  assert_true(Event::parse(Json::object({ "type": "error".to_json() })) is None)
  assert_true(
    Command::parse(Json::object({ "type": "message".to_json() })) is None,
  )
}

///|
test "wire: session framing puts type first and payload wins" {
  let e = Progress({
    phase: "done",
    message: None,
    progress_type: None,
    metadata: None,
    started_at: None,
  })
  assert_eq(
    e.to_wire(Some("s-1")),
    "{\"type\":\"progress\",\"session_id\":\"s-1\",\"phase\":\"done\"}",
  )
  // A payload session_id overrides the framing value (same key).
  let started = SessionUpdate({
    status: Some("running"),
    session_id: Some("s-2"),
    cost: None,
    cost_source: None,
    latency: None,
    session: None,
  })
  assert_eq(
    started.to_wire(Some("s-1")),
    "{\"type\":\"session_update\",\"session_id\":\"s-2\",\"status\":\"running\"}",
  )
}

///|
test "wire: global events carry no session framing" {
  assert_eq(Pong.to_wire(None), "{\"type\":\"pong\"}")
  assert_true(Pong.is_global())
  assert_false(
    Progress({
      phase: "done",
      message: None,
      progress_type: None,
      metadata: None,
      started_at: None,
    }).is_global(),
  )
}

///|
test "wire: from_wire recovers an event from its framed message" {
  let text = Connected({ session_id: "s-1", }).to_wire(None)
  match Event::from_wire(text) {
    Some(Connected(c)) => assert_eq(c.session_id, "s-1")
    _ => fail("from_wire did not recover Connected")
  }
  assert_true(Event::from_wire("{not json") is None)
}

///|
test "options and metadata survive as JSON values" {
  let e = RequestFeedback({
    question: "q",
    id: None,
    context: None,
    options: Some(["a", "b"]),
  })
  match Event::parse(e.to_json()) {
    Some(RequestFeedback(f)) =>
      match f.options {
        Some(options) => {
          assert_eq(options.length(), 2)
          assert_eq(options[1], "b")
        }
        None => fail("options were dropped")
      }
    _ => fail("RequestFeedback did not round-trip")
  }
}
