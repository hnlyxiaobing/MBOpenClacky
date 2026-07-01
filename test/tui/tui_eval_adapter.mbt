///|
/// TUI Eval Adapter: headless TUI eval execution engine.
///
/// Drives the TUI components (InputArea, OutputBuffer, StatusBar) with a
/// VirtualScreen instead of a real terminal, enabling deterministic testing
/// without PTY, raw mode, or async TTY dependencies.
///
/// Architecture (from adversarial review):
/// - No PTY dependency → works on Windows 25H2
/// - No async TTY → avoids MoonBit async-in-sync limitations
/// - No real LLM → mock agent with canned responses
/// - Deterministic → same input → same output every time
///
/// Flow:
/// 1. Create TuiEvalSimulator with terminal dimensions from scenario setup
/// 2. Execute actions sequentially (type, press, screenshot)
/// 3. Render full screen state after each action
/// 4. Check assertions against the final VirtualScreen state
/// 5. Return @eval.EvalScenarioResult with pass/fail and diagnostic info

// ── TUI-Specific Scenario Types ─────────────────────────────────────

///|
/// Terminal setup configuration for an eval scenario.
pub(all) struct EvalSetup {
  /// Terminal width in columns.
  cols : Int
  /// Terminal height in rows.
  rows : Int
  /// Mock LLM response text (empty = no mock).
  mock_response : String
} derive(Debug)

///|
/// A single action in a TUI eval scenario.
pub(all) enum EvalAction {
  /// Type a string of text character by character.
  Type(text~ : String)
  /// Press a special key (Enter, Ctrl+C, arrows, etc.).
  Press(key~ : String)
  /// Capture a screenshot of the virtual screen.
  Screenshot
  /// Wait (no-op, useful for pacing).
  Wait(ms~ : Int)
} derive(Debug)

///|
/// An assertion to verify the screen state after actions.
pub(all) enum EvalAssertion {
  /// Screen (or region) contains the given text.
  Contains(text~ : String, region~ : String)
  /// Screen does NOT contain the given text.
  NotContains(text~ : String)
  /// Screen is empty (all spaces).
  ScreenEmpty
  /// A specific row contains the given text.
  RowContains(row~ : Int, text~ : String)
  /// Status bar (row 1) contains the given text.
  StatusContains(text~ : String)
  /// Input area contains the given text.
  InputContains(text~ : String)
  /// Output area contains the given text.
  OutputContains(text~ : String)
} derive(Debug)

///|
/// A complete TUI eval scenario.
pub(all) struct EvalScenario {
  /// Scenario name.
  name : String
  /// Description of what this scenario tests.
  description : String
  /// Terminal setup.
  setup : EvalSetup
  /// Ordered sequence of actions.
  actions : Array[EvalAction]
  /// Assertions to check after all actions complete.
  assertions : Array[EvalAssertion]
} derive(Debug)

// ── JSON Parsing ──────────────────────────────────────────────────────

///|
/// Parse an EvalScenario from a JSON string.
/// Returns the scenario or an error message.
pub fn parse_eval_scenario(json_text : String) -> Result[EvalScenario, String] {
  let json = @json.parse(json_text) catch {
    _ => return Err("Failed to parse JSON")
  }
  match json {
    Object(obj) => {
      let name = match obj.get("name") {
        Some(String(s)) => s
        _ => ""
      }
      let desc = match obj.get("description") {
        Some(String(s)) => s
        _ => ""
      }
      let setup = match obj.get("setup") {
        Some(Object(s)) => {
          let cols = match s.get("cols") {
            Some(Number(n)) => n.to_int()
            _ => 80
          }
          let rows = match s.get("rows") {
            Some(Number(n)) => n.to_int()
            _ => 24
          }
          let mock = match s.get("mock_response") {
            Some(String(sv)) => sv
            _ => ""
          }
          {
            cols: if cols > 0 {
              cols
            } else {
              80
            },
            rows: if rows > 0 {
              rows
            } else {
              24
            },
            mock_response: mock,
          }
        }
        _ => { cols: 80, rows: 24, mock_response: "" }
      }
      let actions : Array[EvalAction] = []
      match obj.get("actions") {
        Some(Array(arr)) =>
          for item in arr {
            match item {
              Object(a) => {
                let get_s = fn(k : String) -> String {
                  match a.get(k) {
                    Some(String(sv)) => sv
                    _ => ""
                  }
                }
                let get_i = fn(k : String) -> Int {
                  match a.get(k) {
                    Some(Number(n)) => n.to_int()
                    _ => 0
                  }
                }
                let atype = get_s("type")
                let action = match atype {
                  "type" => {
                    let text = get_s("text")
                    EvalAction::Type(text~)
                  }
                  "press" => {
                    let key = get_s("key")
                    EvalAction::Press(key~)
                  }
                  "screenshot" => EvalAction::Screenshot
                  "wait" => {
                    let ms = get_i("ms")
                    EvalAction::Wait(ms~)
                  }
                  _ => EvalAction::Wait(ms=0)
                }
                actions.push(action)
              }
              _ => ()
            }
          }
        _ => ()
      }
      let assertions : Array[EvalAssertion] = []
      match obj.get("assertions") {
        Some(Array(arr)) =>
          for item in arr {
            match item {
              Object(a) => {
                let get_s = fn(k : String) -> String {
                  match a.get(k) {
                    Some(String(sv)) => sv
                    _ => ""
                  }
                }
                let get_i = fn(k : String) -> Int {
                  match a.get(k) {
                    Some(Number(n)) => n.to_int()
                    _ => 0
                  }
                }
                let check = get_s("check")
                let assertion = match check {
                  "contains" => {
                    let text = get_s("text")
                    let region = get_s("region")
                    EvalAssertion::Contains(text~, region~)
                  }
                  "not_contains" => {
                    let text = get_s("text")
                    EvalAssertion::NotContains(text~)
                  }
                  "screen_empty" => EvalAssertion::ScreenEmpty
                  "row_contains" => {
                    let row = get_i("row")
                    let text = get_s("text")
                    EvalAssertion::RowContains(row~, text~)
                  }
                  "status_contains" => {
                    let text = get_s("text")
                    EvalAssertion::StatusContains(text~)
                  }
                  "input_contains" => {
                    let text = get_s("text")
                    EvalAssertion::InputContains(text~)
                  }
                  "output_contains" => {
                    let text = get_s("text")
                    EvalAssertion::OutputContains(text~)
                  }
                  _ => EvalAssertion::ScreenEmpty
                }
                assertions.push(assertion)
              }
              _ => ()
            }
          }
        _ => ()
      }
      Ok({ name, description: desc, setup, actions, assertions })
    }
    _ => Err("Scenario must be a JSON object")
  }
}

// ── TuiEvalSimulator ─────────────────────────────────────────────────

///|
/// Headless TUI simulator for eval scenarios.
/// Replaces TuiController + ScreenBuffer with pure-sync components.
pub(all) struct TuiEvalSimulator {
  /// Virtual terminal screen.
  screen : VirtualScreen
  /// Input area (wraps LineEditor, all sync).
  input : @libtui.InputArea
  /// Output buffer for messages.
  output : @libtui.OutputBuffer
  /// Status bar formatter.
  status_bar : @libtui.StatusBar
  /// TUI state.
  state : Ref[@libtui.TuiState]
  /// Whether the simulator has quit.
  mut quit : Bool
  /// Screenshot history.
  mut screenshots : Array[String]
  /// Status bar height.
  status_h : Int
  /// Input area height.
  input_h : Int
}

///|
/// Create a new eval simulator with given dimensions.
pub fn TuiEvalSimulator::new(cols : Int, rows : Int) -> TuiEvalSimulator {
  let agent = make_eval_agent()
  let state = Ref(@libtui.TuiState::from_agent(agent))
  {
    screen: VirtualScreen::new(cols, rows),
    input: @libtui.InputArea::multiline_new(),
    output: @libtui.OutputBuffer::new(),
    status_bar: @libtui.StatusBar::new(),
    state,
    quit: false,
    screenshots: [],
    status_h: 1,
    input_h: 4,
  }
}

///|
/// Create a minimal agent for eval (no LLM calls needed).
fn make_eval_agent() -> @agent.Agent {
  let client = @client.Client::new(
    "eval-key",
    "http://localhost:1",
    "eval-model",
    @config.OpenAICompletions,
  )
  let config = @config.AgentConfig::default()
  @agent.Agent::new("eval-session", "Eval Agent", "/tmp/eval", client, config)
}

// ── Rendering ─────────────────────────────────────────────────────────

///|
/// Full screen redraw using VirtualScreen (synchronous).
pub fn TuiEvalSimulator::full_redraw(self : TuiEvalSimulator) -> Unit {
  self.screen.clear_display()
  self.render_status()
  self.render_output()
  self.render_input()
}

///|
/// Render status bar at row 1.
fn TuiEvalSimulator::render_status(self : TuiEvalSimulator) -> Unit {
  self.status_bar.format_from_state(self.state.val)
  let text = self.status_bar.plain_text()
  self.screen.render_status_text(text)
}

///|
/// Render output/message area between status bar and input area.
fn TuiEvalSimulator::render_output(self : TuiEvalSimulator) -> Unit {
  let msg_top = self.status_h + 1
  let msg_bottom = self.screen.height - self.input_h
  let msg_height = msg_bottom - msg_top + 1
  if msg_height < 1 {
    return
  }
  let tail = self.output.tail_lines(msg_height)
  self.screen.render_output_lines(tail, msg_top, msg_height)
}

///|
/// Render input area with border at the bottom.
fn TuiEvalSimulator::render_input(self : TuiEvalSimulator) -> Unit {
  let input_lines = self.input.render_lines()
  self.screen.render_input_area(input_lines)
}

///|
/// Take a screenshot (capture current screen state).
pub fn TuiEvalSimulator::screenshot(self : TuiEvalSimulator) -> String {
  let content = self.screen.content()
  self.screenshots.push(content)
  content
}

// ── Actions ───────────────────────────────────────────────────────────

///|
/// Type text character by character into the input area.
pub fn TuiEvalSimulator::type_text(
  self : TuiEvalSimulator,
  text : String,
) -> Unit {
  for ch in text.iter() {
    self.input.insert_char(ch)
  }
  self.render_input()
}

///|
/// Simulate pressing a special key.
pub fn TuiEvalSimulator::press_key(
  self : TuiEvalSimulator,
  key : String,
) -> Unit {
  match key {
    "Enter" => self.handle_enter()
    "Ctrl+J" => self.input.handle_enter()
    "Ctrl+C" => self.quit = true
    "Ctrl+D" if self.input.is_empty() => self.quit = true
    "Ctrl+K" => self.input.kill_to_end()
    "Ctrl+U" => self.input.kill_to_start()
    "Ctrl+W" => self.input.kill_word()
    "Ctrl+L" => self.full_redraw()
    "Backspace" => self.input.backspace()
    "Delete" => self.input.delete_forward()
    "Left" => self.input.cursor_left()
    "Right" => self.input.cursor_right()
    "Up" => self.input.cursor_up()
    "Down" => self.input.cursor_down()
    "Home" => self.input.cursor_home()
    "End" => self.input.cursor_end()
    _ => ()
  }
  if key != "Enter" {
    self.render_input()
  }
}

///|
/// Handle Enter key: submit to output buffer (no real agent call).
fn TuiEvalSimulator::handle_enter(self : TuiEvalSimulator) -> Unit {
  if self.input.is_empty() {
    return
  }
  let text = self.input.submit()
  if text.length() > 0 {
    // Add user message to output
    ignore(self.output.append_text("[user] \{text}", @libtui.OutputKind::Text))
    // Commit it
    self.output.commit_through(self.output.entry_count())
    // Update state
    self.state.val.mode = @libtui.TuiMode::Running
    // Simulate agent response (append mock response)
    ignore(
      self.output.append_text(
        "[assistant] (eval mock response)",
        @libtui.OutputKind::Text,
      ),
    )
    self.output.commit_through(self.output.entry_count())
    // Reset state
    self.state.val.mode = @libtui.TuiMode::Idle
    self.state.val.agent_status = "idle"
    // Full redraw
    self.full_redraw()
  }
}

// ── Assertions ────────────────────────────────────────────────────────

///|
/// Check a single assertion against the current screen state.
pub fn TuiEvalSimulator::check_assertion(
  self : TuiEvalSimulator,
  assertion : EvalAssertion,
) -> @eval.EvalAssertionResult {
  match assertion {
    Contains(text~, region~) => {
      let passed = match region {
        "input" => self.check_input_region(text)
        "status" => self.check_status_region(text)
        "output" => self.check_output_region(text)
        _ => self.screen.contains(text)
      }
      let desc = "screen contains '\{text}'"
      let region_label = if region.length() > 0 { region } else { "screen" }
      let detail = if passed { "" } else { "NOT FOUND in \{region_label}" }
      { description: desc, passed, detail }
    }
    NotContains(text~) => {
      let passed = !self.screen.contains(text)
      let desc = "screen does NOT contain '\{text}'"
      let detail = if passed { "" } else { "FOUND (should not be present)" }
      { description: desc, passed, detail }
    }
    ScreenEmpty => {
      let content = self.screen.content_trimmed()
      let passed = content.length() == 0
      {
        description: "screen is empty",
        passed,
        detail: if passed {
          ""
        } else {
          "Screen has content"
        },
      }
    }
    RowContains(row~, text~) => {
      let passed = self.screen.row_contains(row, text)
      let desc = "row \{row} contains '\{text}'"
      let detail = if passed {
        ""
      } else {
        "Row \{row}: '\{self.screen.get_row_trimmed(row)}'"
      }
      { description: desc, passed, detail }
    }
    StatusContains(text~) => {
      let passed = self.check_status_region(text)
      let desc = "status bar contains '\{text}'"
      let detail = if passed {
        ""
      } else {
        "Status: '\{self.screen.get_row_trimmed(1)}'"
      }
      { description: desc, passed, detail }
    }
    InputContains(text~) => {
      let passed = self.check_input_region(text)
      let desc = "input area contains '\{text}'"
      let detail = if passed { "" } else { "NOT FOUND in input area" }
      { description: desc, passed, detail }
    }
    OutputContains(text~) => {
      let passed = self.check_output_region(text)
      let desc = "output area contains '\{text}'"
      let detail = if passed { "" } else { "NOT FOUND in output area" }
      { description: desc, passed, detail }
    }
  }
}

///|
/// Check if the status region (row 1) contains text.
fn TuiEvalSimulator::check_status_region(
  self : TuiEvalSimulator,
  text : String,
) -> Bool {
  self.screen.row_contains(1, text)
}

///|
/// Check if the input region (bottom 4 rows) contains text.
fn TuiEvalSimulator::check_input_region(
  self : TuiEvalSimulator,
  text : String,
) -> Bool {
  let top = self.screen.height - self.input_h + 1
  for row = top; row <= self.screen.height; row = row + 1 {
    if self.screen.row_contains(row, text) {
      return true
    }
  }
  false
}

///|
/// Check if the output region (between status and input) contains text.
fn TuiEvalSimulator::check_output_region(
  self : TuiEvalSimulator,
  text : String,
) -> Bool {
  let top = self.status_h + 1
  let bottom = self.screen.height - self.input_h
  for row = top; row <= bottom; row = row + 1 {
    if self.screen.row_contains(row, text) {
      return true
    }
  }
  false
}

// ── Scenario Execution ────────────────────────────────────────────────

///|
/// Execute a complete TUI eval scenario and return the result.
pub fn run_eval_scenario(scenario : EvalScenario) -> @eval.EvalScenarioResult {
  let sim = TuiEvalSimulator::new(scenario.setup.cols, scenario.setup.rows)

  // Initial full redraw
  sim.full_redraw()

  // Execute actions
  for action in scenario.actions {
    match action {
      Type(text~) => sim.type_text(text)
      Press(key~) => sim.press_key(key)
      Screenshot => ignore(sim.screenshot())
      Wait(_) => ()
    }
    if sim.quit {
      break
    }
  }

  // Final render
  sim.full_redraw()

  // Check assertions
  let results : Array[@eval.EvalAssertionResult] = []
  let mut all_passed = true
  for assertion in scenario.assertions {
    let result = sim.check_assertion(assertion)
    if !result.passed {
      all_passed = false
    }
    results.push(result)
  }

  let final_screen = sim.screen.content()

  {
    scenario_name: scenario.name,
    passed: all_passed,
    assertion_results: results,
    final_screen,
    error: "",
  }
}

///|
/// Run all TUI eval scenarios from a directory and return batch results.
pub fn run_eval_scenarios(dir_path : String) -> @eval.EvalBatchResult {
  let json_texts = @eval.load_scenario_files(dir_path)
  let results : Array[@eval.EvalScenarioResult] = []
  let mut passed = 0
  let mut failed = 0

  for json_text in json_texts {
    match parse_eval_scenario(json_text) {
      Ok(scenario) => {
        let result = run_eval_scenario(scenario)
        if result.passed {
          passed = passed + 1
        } else {
          failed = failed + 1
        }
        results.push(result)
      }
      Err(_) => ()
    }
  }

  {
    results,
    passed_count: passed,
    failed_count: failed,
    total_count: results.length(),
  }
}
