///|
/// Tests for the generic eval engine — unit tests.
test "EvalAssertionResult construction" {
  let r = EvalAssertionResult::{
    description: "test assertion",
    passed: true,
    detail: "",
  }
  inspect(r.passed, content="true")
  inspect(r.description, content="test assertion")
}

///|
test "EvalScenarioResult construction" {
  let r = EvalScenarioResult::{
    scenario_name: "test_scenario",
    passed: false,
    assertion_results: [
      EvalAssertionResult::{
        description: "check something",
        passed: false,
        detail: "NOT FOUND",
      },
    ],
    final_screen: "screen content",
    error: "",
  }
  inspect(r.passed, content="false")
  inspect(r.assertion_results.length(), content="1")
}

///|
test "format_eval_report formats correctly" {
  let batch = EvalBatchResult::{
    results: [
      EvalScenarioResult::{
        scenario_name: "pass_test",
        passed: true,
        assertion_results: [],
        final_screen: "",
        error: "",
      },
      EvalScenarioResult::{
        scenario_name: "fail_test",
        passed: false,
        assertion_results: [
          EvalAssertionResult::{
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
  let report = format_eval_report(batch)
  inspect(report.contains("PASS"), content="true")
  inspect(report.contains("FAIL"), content="true")
  inspect(report.contains("pass_test"), content="true")
  inspect(report.contains("fail_test"), content="true")
  inspect(report.contains("Total: 2"), content="true")
}

///|
test "EvalBatchResult empty" {
  let batch = EvalBatchResult::{
    results: [],
    passed_count: 0,
    failed_count: 0,
    total_count: 0,
  }
  let report = format_eval_report(batch)
  inspect(report.contains("Total: 0"), content="true")
}
