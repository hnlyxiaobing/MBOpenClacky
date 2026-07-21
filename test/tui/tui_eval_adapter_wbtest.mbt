///|
/// Tests for TUI EvalAdapter — L2 integration tests.
///
/// These tests verify:
/// - JSON scenario parsing
/// - Eval scenario execution
/// - Assertion checking
/// - Report formatting
test "parse_eval_scenario parses valid JSON" {
  let json = "{\"name\":\"test_scenario\",\"description\":\"A test\",\"setup\":{\"cols\":40,\"rows\":10},\"actions\":[{\"type\":\"type\",\"text\":\"hi\"},{\"type\":\"press\",\"key\":\"Enter\"}],\"assertions\":[{\"check\":\"contains\",\"text\":\"hi\",\"region\":\"\"}]}"
  match parse_eval_scenario(json) {
    Ok(scenario) => {
      @debug.debug_inspect(
        scenario.name,
        content=(
          #|"test_scenario"
        ),
      )
      @debug.debug_inspect(scenario.setup.cols, content="40")
      @debug.debug_inspect(scenario.setup.rows, content="10")
      @debug.debug_inspect(scenario.actions.length(), content="2")
      @debug.debug_inspect(scenario.assertions.length(), content="1")
    }
    Err(e) => @debug.debug_inspect("expected Ok", content=e)
  }
}

///|
test "parse_eval_scenario handles missing setup" {
  let json = "{\"name\":\"minimal\",\"description\":\"\",\"actions\":[],\"assertions\":[]}"
  match parse_eval_scenario(json) {
    Ok(scenario) => {
      @debug.debug_inspect(
        scenario.name,
        content=(
          #|"minimal"
        ),
      )
      @debug.debug_inspect(scenario.setup.cols, content="80")
      @debug.debug_inspect(scenario.setup.rows, content="24")
    }
    Err(e) => @debug.debug_inspect("expected Ok", content=e)
  }
}

///|
test "parse_eval_scenario rejects invalid JSON" {
  match parse_eval_scenario("not json") {
    Ok(_) => @debug.debug_inspect("expected Err", content="got Ok")
    Err(e) =>
      @debug.debug_inspect(
        e,
        content=(
          #|"Failed to parse JSON"
        ),
      )
  }
}

///|
test "TuiEvalSimulator type_text inserts characters" {
  let sim = TuiEvalSimulator::new(40, 10)
  sim.full_redraw()
  sim.type_text("hello")
  sim.full_redraw()
  @debug.debug_inspect(sim.screen.contains("hello"), content="true")
}

///|
test "TuiEvalSimulator press_key Enter submits message" {
  let sim = TuiEvalSimulator::new(40, 10)
  sim.full_redraw()
  sim.type_text("test message")
  sim.press_key("Enter")
  sim.full_redraw()
  @debug.debug_inspect(sim.screen.contains("[user]"), content="true")
  @debug.debug_inspect(sim.screen.contains("test message"), content="true")
}

///|
test "TuiEvalSimulator press_key Backspace removes character" {
  let sim = TuiEvalSimulator::new(40, 10)
  sim.full_redraw()
  sim.type_text("abc")
  sim.press_key("Backspace")
  sim.full_redraw()
  @debug.debug_inspect(sim.screen.contains("ab"), content="true")
}

///|
test "TuiEvalSimulator check_assertion contains" {
  let sim = TuiEvalSimulator::new(40, 10)
  sim.full_redraw()
  sim.type_text("hello world")
  sim.full_redraw()
  let result = sim.check_assertion(
    EvalAssertion::Contains(text="hello", region=""),
  )
  @debug.debug_inspect(result.passed, content="true")
}

///|
test "TuiEvalSimulator check_assertion not_contains" {
  let sim = TuiEvalSimulator::new(40, 10)
  sim.full_redraw()
  let result = sim.check_assertion(
    EvalAssertion::NotContains(text="nonexistent"),
  )
  @debug.debug_inspect(result.passed, content="true")
}

///|
test "TuiEvalSimulator slash help outputs command list" {
  let sim = TuiEvalSimulator::new(80, 24)
  sim.full_redraw()
  sim.type_text("/help")
  sim.press_key("Enter")
  @debug.debug_inspect(sim.screen.contains("/config"), content="true")
  @debug.debug_inspect(sim.screen.contains("/model"), content="true")
  @debug.debug_inspect(sim.screen.contains("/clear"), content="true")
  @debug.debug_inspect(sim.screen.contains("/help"), content="true")
  // Slash commands must not be submitted as user messages
  @debug.debug_inspect(sim.screen.contains("[user] /help"), content="false")
}

///|
test "TuiEvalSimulator slash clear empties output area" {
  let sim = TuiEvalSimulator::new(80, 24)
  sim.full_redraw()
  sim.type_text("hello")
  sim.press_key("Enter")
  @debug.debug_inspect(sim.screen.contains("[user] hello"), content="true")
  sim.type_text("/clear")
  sim.press_key("Enter")
  @debug.debug_inspect(sim.screen.contains("[user] hello"), content="false")
}

///|
test "TuiEvalSimulator slash theme outputs system message" {
  let sim = TuiEvalSimulator::new(80, 24)
  sim.full_redraw()
  sim.type_text("/theme hacker")
  sim.press_key("Enter")
  @debug.debug_inspect(
    sim.screen.contains("[system] Theme switched to: hacker"),
    content="true",
  )
}

///|
test "TuiEvalSimulator unknown slash command sent as regular input" {
  let sim = TuiEvalSimulator::new(80, 24)
  sim.full_redraw()
  sim.type_text("/foobar")
  sim.press_key("Enter")
  @debug.debug_inspect(sim.screen.contains("[user] /foobar"), content="true")
}

///|
test "TuiEvalSimulator screenshot captures state" {
  let sim = TuiEvalSimulator::new(40, 10)
  sim.full_redraw()
  sim.type_text("captured")
  sim.full_redraw()
  let shot = sim.screenshot()
  @debug.debug_inspect(shot.contains("captured"), content="true")
  @debug.debug_inspect(sim.screenshots.length(), content="1")
}

///|
test "run_eval_scenario executes full scenario" {
  let scenario = EvalScenario::{
    name: "inline_test",
    description: "Test scenario",
    setup: { cols: 40, rows: 10, mock_response: "" },
    actions: [EvalAction::Type(text="hi")],
    assertions: [EvalAssertion::Contains(text="hi", region="")],
  }
  let result = run_eval_scenario(scenario)
  @debug.debug_inspect(
    result.scenario_name,
    content=(
      #|"inline_test"
    ),
  )
  @debug.debug_inspect(result.passed, content="true")
}

///|
test "TuiEvalSimulator renders confirmation dialog" {
  let sim = TuiEvalSimulator::new(80, 24)
  sim.full_redraw()
  @libtui.request_confirmation(
    sim.state.val,
    "terminal",
    "ls -la",
    "Run: ls -la",
    default_yes=false,
  )
  sim.full_redraw()
  @debug.debug_inspect(sim.screen.contains("terminal"), content="true")
  @debug.debug_inspect(sim.screen.contains("Run: ls -la"), content="true")
  @debug.debug_inspect(sim.screen.contains("[y/N]"), content="true")
}

///|
test "format_eval_report formats correctly" {
  let batch = @eval.EvalBatchResult::{
    results: [
      @eval.EvalScenarioResult::{
        scenario_name: "pass_test",
        passed: true,
        assertion_results: [],
        final_screen: "",
        error: "",
      },
      @eval.EvalScenarioResult::{
        scenario_name: "fail_test",
        passed: false,
        assertion_results: [
          @eval.EvalAssertionResult::{
            description: "screen contains xyz",
            passed: false,
            detail: "NOT FOUND in screen",
          },
        ],
        final_screen: "",
        error: "",
      },
    ],
    passed_count: 1,
    failed_count: 1,
    total_count: 2,
  }
  let report = @eval.format_eval_report(batch)
  @debug.debug_inspect(report.contains("PASS"), content="true")
  @debug.debug_inspect(report.contains("FAIL"), content="true")
  @debug.debug_inspect(report.contains("pass_test"), content="true")
  @debug.debug_inspect(report.contains("fail_test"), content="true")
  @debug.debug_inspect(report.contains("Total: 2"), content="true")
}

///|
/// Regression test for the `long_output_scroll` scenario: a mock response
/// with real newlines must produce one entry line per response line, and the
/// message area must show the tail (line25 visible, line01 scrolled out).
test "run_eval_scenario long output shows tail lines" {
  let json = "{\"name\":\"long_output_scroll\",\"description\":\"Verify output area shows tail lines for long responses\",\"setup\":{\"cols\":80,\"rows\":24,\"mock_response\":\"line01\\nline02\\nline03\\nline04\\nline05\\nline06\\nline07\\nline08\\nline09\\nline10\\nline11\\nline12\\nline13\\nline14\\nline15\\nline16\\nline17\\nline18\\nline19\\nline20\\nline21\\nline22\\nline23\\nline24\\nline25\"},\"actions\":[{\"type\":\"type\",\"text\":\"test\"},{\"type\":\"press\",\"key\":\"Enter\"}],\"assertions\":[{\"check\":\"output_contains\",\"text\":\"line25\"},{\"check\":\"not_contains\",\"text\":\"line01\"}]}"
  match parse_eval_scenario(json) {
    Ok(scenario) => {
      // JSON \n escape must decode to a real newline.
      @debug.debug_inspect(
        scenario.setup.mock_response.contains("\n"),
        content="true",
      )
      @debug.debug_inspect(
        scenario.setup.mock_response.contains("\\n"),
        content="false",
      )
      let result = run_eval_scenario(scenario)
      @debug.debug_inspect(result.passed, content="true")
      @debug.debug_inspect(
        result.final_screen.contains("line25"),
        content="true",
      )
      @debug.debug_inspect(
        result.final_screen.contains("line01"),
        content="false",
      )
    }
    Err(e) => @debug.debug_inspect("expected Ok", content=e)
  }
}
