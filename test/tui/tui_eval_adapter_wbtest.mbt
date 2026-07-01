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
      inspect(scenario.name, content="test_scenario")
      inspect(scenario.setup.cols, content="40")
      inspect(scenario.setup.rows, content="10")
      inspect(scenario.actions.length(), content="2")
      inspect(scenario.assertions.length(), content="1")
    }
    Err(e) => inspect("expected Ok", content=e)
  }
}

///|
test "parse_eval_scenario handles missing setup" {
  let json = "{\"name\":\"minimal\",\"description\":\"\",\"actions\":[],\"assertions\":[]}"
  match parse_eval_scenario(json) {
    Ok(scenario) => {
      inspect(scenario.name, content="minimal")
      inspect(scenario.setup.cols, content="80")
      inspect(scenario.setup.rows, content="24")
    }
    Err(e) => inspect("expected Ok", content=e)
  }
}

///|
test "parse_eval_scenario rejects invalid JSON" {
  match parse_eval_scenario("not json") {
    Ok(_) => inspect("expected Err", content="got Ok")
    Err(e) => inspect(e, content="Failed to parse JSON")
  }
}

///|
test "TuiEvalSimulator type_text inserts characters" {
  let sim = TuiEvalSimulator::new(40, 10)
  sim.full_redraw()
  sim.type_text("hello")
  sim.full_redraw()
  inspect(sim.screen.contains("hello"), content="true")
}

///|
test "TuiEvalSimulator press_key Enter submits message" {
  let sim = TuiEvalSimulator::new(40, 10)
  sim.full_redraw()
  sim.type_text("test message")
  sim.press_key("Enter")
  sim.full_redraw()
  inspect(sim.screen.contains("[user]"), content="true")
  inspect(sim.screen.contains("test message"), content="true")
}

///|
test "TuiEvalSimulator press_key Backspace removes character" {
  let sim = TuiEvalSimulator::new(40, 10)
  sim.full_redraw()
  sim.type_text("abc")
  sim.press_key("Backspace")
  sim.full_redraw()
  inspect(sim.screen.contains("ab"), content="true")
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
  inspect(result.passed, content="true")
}

///|
test "TuiEvalSimulator check_assertion not_contains" {
  let sim = TuiEvalSimulator::new(40, 10)
  sim.full_redraw()
  let result = sim.check_assertion(
    EvalAssertion::NotContains(text="nonexistent"),
  )
  inspect(result.passed, content="true")
}

///|
test "TuiEvalSimulator screenshot captures state" {
  let sim = TuiEvalSimulator::new(40, 10)
  sim.full_redraw()
  sim.type_text("captured")
  sim.full_redraw()
  let shot = sim.screenshot()
  inspect(shot.contains("captured"), content="true")
  inspect(sim.screenshots.length(), content="1")
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
  inspect(result.scenario_name, content="inline_test")
  inspect(result.passed, content="true")
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
  inspect(report.contains("PASS"), content="true")
  inspect(report.contains("FAIL"), content="true")
  inspect(report.contains("pass_test"), content="true")
  inspect(report.contains("fail_test"), content="true")
  inspect(report.contains("Total: 2"), content="true")
}
