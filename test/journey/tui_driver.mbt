///|
/// TUI journey driver: assertion bridge from the shared AssertionKind
/// vocabulary to the simulator's own EvalAssertion checks, plus the
/// simulator step actions (driven in task 8).
///
/// The journey runner reuses TuiEvalSimulator::check_assertion verbatim so
/// screen-region semantics (status/input/output/dialog rows) stay identical
/// to layer 4.

///|
/// Bridge a shared-vocabulary screen assertion to the simulator.
fn evaluate_tui_screen_assertion(
  state : JourneyState,
  kind : String,
  text : String,
  region : String,
) -> @eval.EvalAssertionResult {
  match state.tui {
    Some(sim) => {
      let assertion : @test_tui.EvalAssertion = match kind {
        "not_contains" => @test_tui.EvalAssertion::NotContains(text~)
        "screen_empty" => @test_tui.EvalAssertion::ScreenEmpty
        "status_contains" => @test_tui.EvalAssertion::StatusContains(text~)
        "input_contains" => @test_tui.EvalAssertion::InputContains(text~)
        "output_contains" => @test_tui.EvalAssertion::OutputContains(text~)
        "dialog_contains" => @test_tui.EvalAssertion::DialogContains(text~)
        _ => @test_tui.EvalAssertion::Contains(text~, region~)
      }
      sim.check_assertion(assertion)
    }
    None => {
      let desc = if kind == "screen_empty" {
        "screen is empty"
      } else {
        "screen check '\{kind}' '\{text}'"
      }
      journey_assert(desc, false, "no TUI simulator in this journey")
    }
  }
}

///|
/// Bridge a row assertion to the simulator.
fn evaluate_tui_row_assertion(
  state : JourneyState,
  row : Int,
  text : String,
) -> @eval.EvalAssertionResult {
  match state.tui {
    Some(sim) =>
      sim.check_assertion(@test_tui.EvalAssertion::RowContains(row~, text~))
    None =>
      journey_assert(
        "row \{row} contains '\{text}'",
        false,
        "no TUI simulator in this journey",
      )
  }
}
