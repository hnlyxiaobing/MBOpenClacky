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
pub extend EvalSetup with @moonbitlang/core/debug.Debug::{to_repr}

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
  /// Set a pending confirmation dialog.
  SetConfirmation(
    tool_name~ : String,
    tool_args~ : String,
    prompt_text~ : String,
    default_yes~ : Bool
  )
  /// Inject text directly into the output buffer.
  InjectOutput(text~ : String, kind~ : String)
  /// Emit a real agent hook event through the agent's hook manager
  /// (drives the production hook → state/output pipeline).
  EmitHook(event~ : String, args~ : Map[String, Json])
  /// Check an assertion immediately and record the result.
  Assert(assertion~ : EvalAssertion)
} derive(Debug)

///|
pub extend EvalAction with @moonbitlang/core/debug.Debug::{to_repr}

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
  /// Confirmation dialog contains the given text.
  DialogContains(text~ : String)
} derive(Debug)

///|
pub extend EvalAssertion with @moonbitlang/core/debug.Debug::{to_repr}

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

///|
pub extend EvalScenario with @moonbitlang/core/debug.Debug::{to_repr}

// ── JSON Parsing ──────────────────────────────────────────────────────

///|
/// Parse a single EvalAssertion from a JSON object.
fn parse_single_assertion(a : Map[String, Json]) -> EvalAssertion {
  let get_s = fn(k : String) -> String {
    match a.get(k) {
      Some(String(sv)) => sv
      _ => ""
    }
  }
  let get_i = fn(k : String) -> Int {
    match a.get(k) {
      Some(Number(n, ..)) => n.to_int()
      _ => 0
    }
  }
  let check = get_s("check")
  match check {
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
    "dialog_contains" => {
      let text = get_s("text")
      EvalAssertion::DialogContains(text~)
    }
    _ => EvalAssertion::ScreenEmpty
  }
}

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
            Some(Number(n, ..)) => n.to_int()
            _ => 80
          }
          let rows = match s.get("rows") {
            Some(Number(n, ..)) => n.to_int()
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
                    Some(Number(n, ..)) => n.to_int()
                    _ => 0
                  }
                }
                let get_b = fn(k : String) -> Bool {
                  match a.get(k) {
                    Some(True) => true
                    Some(False) => false
                    _ => false
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
                  "set_confirmation" => {
                    let tool_name = get_s("tool_name")
                    let tool_args = get_s("tool_args")
                    let prompt_text = get_s("prompt_text")
                    let default_yes = get_b("default_yes")
                    EvalAction::SetConfirmation(
                      tool_name~,
                      tool_args~,
                      prompt_text~,
                      default_yes~,
                    )
                  }
                  "inject_output" => {
                    let text = get_s("text")
                    let kind = get_s("kind")
                    EvalAction::InjectOutput(text~, kind~)
                  }
                  "emit_hook" => {
                    let event = get_s("event")
                    EvalAction::EmitHook(event~, args=a)
                  }
                  "assert" => {
                    let assertion = parse_single_assertion(a)
                    EvalAction::Assert(assertion~)
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
              Object(a) => assertions.push(parse_single_assertion(a))
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
  /// Pending confirmation result (Some(true)=approved, Some(false)=denied, None=pending).
  mut confirmation_result : Bool?
  /// Mock LLM response text for eval scenarios.
  mut mock_response : String
  /// Mock agent backing slash-command execution (no real LLM calls).
  agent : @agent.Agent
  /// Hook handler wiring hook events to state/output (production pipeline).
  hooks : @libtui.AgentHookHandler
}

///|
/// Create a new eval simulator with given dimensions.
pub fn TuiEvalSimulator::new(cols : Int, rows : Int) -> TuiEvalSimulator {
  let agent = make_eval_agent()
  let state = Ref(@libtui.TuiState::from_agent(agent))
  let output = @libtui.OutputBuffer::new()
  // Render startup banner into the output buffer so eval scenarios
  // can assert on banner content.
  let banner_width = @libtui.Banner::adaptive_width(cols)
  let banner = @libtui.Banner::block_with_width(banner_width)
  let rules = @utils.WorkspaceRules::find_main(state.val.working_dir)
  let has_rules = rules.has_rules()
  let startup_text = banner.render_startup(
    "0.1.0",
    state.val.working_dir,
    state.val.permission_mode,
    has_rules,
    false, // eval agent has an API key
    terminal_width=cols,
  )
  output.width = cols
  ignore(output.append_text(startup_text, @libtui.OutputKind::Text))
  // Wire the production hook pipeline so emit_hook scenarios exercise the
  // real event → state/output path (tool symbols, token stats, banners).
  let hooks = @libtui.AgentHookHandler::new(state, agent=Some(agent))
  hooks.set_output(output)
  hooks.register_all(agent.hook_manager)
  {
    screen: VirtualScreen::new(cols, rows),
    input: @libtui.InputArea::multiline_new(),
    output,
    status_bar: @libtui.StatusBar::new(),
    state,
    quit: false,
    screenshots: [],
    confirmation_result: None,
    mock_response: "",
    agent,
    hooks,
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
  // Add sample models so /config and /model eval scenarios have data
  config.models = [
    @config.ModelConfig::new(
      "eval-openai", "sk-eval-test-key-12345678", "https://api.openai.com/v1", "gpt-4o",
    ),
    @config.ModelConfig::new(
      "eval-anthropic", "sk-ant-eval-key-87654321", "https://api.anthropic.com",
      "claude-sonnet-4-6",
    ),
  ]
  config.current_model_id = Some("eval-openai")
  let agent = @agent.Agent::new(
    "eval-session", "Eval Agent", "/tmp/eval", client, config,
  )
  // Register a user-invocable test skill for skill slash-command scenarios.
  agent.skill_registry.register({
    ..@skill.Skill::default("test-skill", "builtin"),
    description: Some("A test skill for eval"),
    argument_hint: Some("<topic>"),
  })
  agent
}

// ── Rendering ─────────────────────────────────────────────────────────

///|
/// Number of todo-area rows rendered above the status bar (0 when hidden
/// or empty), mirroring the production layout.
fn TuiEvalSimulator::todo_row_count(self : TuiEvalSimulator) -> Int {
  if self.state.val.todo_area.visible() {
    self.state.val.todo_area.render_lines().length()
  } else {
    0
  }
}

///|
/// Height in rows of the bottom fixed area, mirroring the production
/// layout (TuiController::fixed_area_height): todo (0-N) + status bar (1)
/// + separator (1) + attachments (0-N) + input lines (1-N wrapped at 90%
/// width) + separator (1). The simulator has no suggestions dropdown or
/// tips row.
fn TuiEvalSimulator::fixed_area_height(self : TuiEvalSimulator) -> Int {
  let content_width = @libtui.effective_content_width(self.screen.width)
  let input_rows = self.input.render_wrapped_lines(content_width).length()
  let attach_rows = self.state.val.paste_placeholders.length()
  self.todo_row_count() + 1 + 1 + attach_rows + input_rows + 1
}

///|
/// 1-based row of the status bar (after the todo rows in the fixed area).
fn TuiEvalSimulator::status_row(self : TuiEvalSimulator) -> Int {
  self.screen.height - self.fixed_area_height() + 1 + self.todo_row_count()
}

///|
/// 1-based row where the bottom fixed area starts (todo rows or status bar).
fn TuiEvalSimulator::first_fixed_row(self : TuiEvalSimulator) -> Int {
  self.status_row() - self.todo_row_count()
}

///|
/// 1-based row where the (wrapped) input lines start.
fn TuiEvalSimulator::input_top_row(self : TuiEvalSimulator) -> Int {
  // status row + separator + attachment rows
  self.status_row() + 2 + self.state.val.paste_placeholders.length()
}

///|
/// Full screen redraw using VirtualScreen (synchronous).
pub fn TuiEvalSimulator::full_redraw(self : TuiEvalSimulator) -> Unit {
  self.screen.clear_display()
  self.render_output()
  self.render_fixed_area()
  self.render_confirmation()
  self.render_config_dialog()
}

///|
/// Render the bottom fixed area: todo rows, status bar, separator,
/// attachments, input lines, separator (aligned with the production layout).
fn TuiEvalSimulator::render_fixed_area(self : TuiEvalSimulator) -> Unit {
  let status_row = self.status_row()
  if status_row < 1 {
    return
  }
  // Todo rows directly above the status bar
  if self.state.val.todo_area.visible() {
    let mut trow = status_row - self.todo_row_count()
    for line in self.state.val.todo_area.render_lines() {
      if trow < 1 {
        break
      }
      self.screen.move_cursor(trow, 1)
      self.screen.clear_to_eol()
      self.screen.write_string(line)
      trow = trow + 1
    }
  }
  // Status bar
  self.status_bar.format_from_state(self.state.val)
  self.screen.move_cursor(status_row, 1)
  self.screen.clear_to_eol()
  self.screen.write_string(self.status_bar.plain_text())
  // Separator
  self.screen.move_cursor(status_row + 1, 1)
  self.screen.clear_to_eol()
  self.screen.write_string("─".repeat(self.screen.width))
  // Attachment rows: one dim row per stored paste placeholder
  let mut row = status_row + 2
  for pair in self.state.val.paste_placeholders {
    let (num, text) = pair
    if row > self.screen.height {
      break
    }
    self.screen.move_cursor(row, 1)
    self.screen.clear_to_eol()
    self.screen.write_string(
      "  [#\{num} Paste Text] \{@libtui.paste_line_count(text)} lines",
    )
    row = row + 1
  }
  // Input lines (auto-wrapped at 90% width, borderless)
  let content_width = @libtui.effective_content_width(self.screen.width)
  for line in self.input.render_wrapped_lines(content_width) {
    if row > self.screen.height {
      break
    }
    self.screen.move_cursor(row, 1)
    self.screen.clear_to_eol()
    self.screen.write_string(line)
    row = row + 1
  }
  // Bottom separator
  if row <= self.screen.height {
    self.screen.move_cursor(row, 1)
    self.screen.clear_to_eol()
    self.screen.write_string("─".repeat(self.screen.width))
  }
}

///|
/// Render output/message area above the bottom fixed area.
fn TuiEvalSimulator::render_output(self : TuiEvalSimulator) -> Unit {
  let msg_height = self.first_fixed_row() - 1
  if msg_height < 1 {
    return
  }
  let tail = self.output.tail_lines(msg_height)
  self.screen.render_output_lines(tail, 1, msg_height)
}

///|
/// Render pending confirmation dialog above the fixed area.
fn TuiEvalSimulator::render_confirmation(self : TuiEvalSimulator) -> Unit {
  if @libtui.has_pending_confirmation(self.state.val) {
    let line = @libtui.render_confirmation_line(self.state.val)
    let row = self.first_fixed_row() - 1
    if row >= 1 {
      self.screen.move_cursor(row, 1)
      self.screen.clear_to_eol()
      self.screen.write_string(line)
    }
  }
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
  // Input height can grow/shrink with wrapping, so redraw the whole screen.
  self.full_redraw()
}

///|
/// Simulate pressing a special key.
pub fn TuiEvalSimulator::press_key(
  self : TuiEvalSimulator,
  key : String,
) -> Unit {
  // If a config/model dialog is active, route dialog keys first
  match self.state.val.dialog {
    @libtui.DialogState::ModelDrawer(level~, dialog~, card_id~, ..) =>
      match key {
        "j" | "Down" => {
          dialog.move_down()
          self.full_redraw()
          return
        }
        "k" | "Up" => {
          dialog.move_up()
          self.full_redraw()
          return
        }
        "Right" | "l" =>
          if level is Cards {
            self.try_open_submodel_drawer(dialog)
            self.full_redraw()
            return
          }
        "Enter" => {
          match level {
            @libtui.ModelDrawerLevel::Cards =>
              match dialog.get_selected() {
                // Enter always selects the card with its default model
                // (clears overlay); only → opens the drawer (mirrors the
                // controller).
                Some(item) => self.apply_model_card_switch(item.value, None)
                None => ()
              }
            @libtui.ModelDrawerLevel::SubModels =>
              match dialog.get_selected() {
                Some(item) => {
                  let sub_model = if item.value.length() == 0 {
                    None
                  } else {
                    Some(item.value)
                  }
                  self.apply_model_card_switch(card_id, sub_model)
                }
                None => ()
              }
          }
          self.full_redraw()
          return
        }
        "Left" | "Escape" => {
          if level is SubModels {
            @libtui.open_model_selector(self.state.val, self.agent)
          } else {
            @libtui.close_config_dialog(self.state.val)
          }
          self.full_redraw()
          return
        }
        _ => ()
      }
    @libtui.DialogState::TimeMachineMenu(dialog) =>
      match key {
        "Escape" => {
          @libtui.close_config_dialog(self.state.val)
          self.full_redraw()
          return
        }
        "j" | "Down" => {
          dialog.move_down()
          self.full_redraw()
          return
        }
        "k" | "Up" => {
          dialog.move_up()
          self.full_redraw()
          return
        }
        "Enter" => {
          // Mirror the controller's time machine switch (no disk apply,
          // no session save in eval).
          match dialog.get_selected() {
            Some(item) => {
              let target_num = @agent.task_num_of(item.value)
              let cur_num = match self.state.val.time_machine.current_task_id {
                Some(id) => @agent.task_num_of(id)
                None => 0
              }
              let direction = if target_num < cur_num {
                "Undoing"
              } else {
                "Redoing"
              }
              ignore(
                self.output.append_text(
                  "[system] \{direction} to Task \{target_num}...",
                  @libtui.OutputKind::Text,
                ),
              )
              match self.state.val.time_machine.switch_to_task(item.value) {
                Ok(entries) =>
                  ignore(
                    self.output.append_text(
                      "[system] ✓ Switched to \{item.value}: restored \{entries.length()} file(s)",
                      @libtui.OutputKind::Text,
                    ),
                  )
                Err(msg) =>
                  ignore(
                    self.output.append_text(
                      "[error] \{msg}",
                      @libtui.OutputKind::Text,
                    ),
                  )
              }
            }
            None => ()
          }
          @libtui.close_config_dialog(self.state.val)
          self.full_redraw()
          return
        }
        _ => ()
      }
    @libtui.DialogState::ConfigMenu(dialog) =>
      match key {
        "Escape" => {
          @libtui.close_config_dialog(self.state.val)
          self.full_redraw()
          return
        }
        "j" | "Down" => {
          dialog.move_down()
          self.full_redraw()
          self.render_config_dialog()
          return
        }
        "k" | "Up" => {
          dialog.move_up()
          self.full_redraw()
          self.render_config_dialog()
          return
        }
        "Enter" => {
          // Mirror the real controller: switch to the selected model and
          // report it (disk persistence is skipped in eval).
          match dialog.get_selected() {
            Some(item) => {
              match self.agent.config.switch_model_by_id(item.value) {
                Ok(_) => {
                  self.state.val.model_name = match
                    self.agent.config.current_model() {
                    Some(m) => m.model
                    None => self.state.val.model_name
                  }
                  ignore(
                    self.output.append_text(
                      "[system] Model switched to: \{item.label}",
                      @libtui.OutputKind::Text,
                    ),
                  )
                }
                Err(msg) =>
                  ignore(
                    self.output.append_text(
                      "[error] \{msg}",
                      @libtui.OutputKind::Text,
                    ),
                  )
              }
              @libtui.close_config_dialog(self.state.val)
            }
            None => ()
          }
          self.full_redraw()
          return
        }
        "a" => {
          let mode : @libtui.ConfigMode = if dialog.title == "Select Model" {
            ModelSelector
          } else {
            ConfigMenu
          }
          @libtui.open_add_form(self.state.val, mode)
          self.full_redraw()
          return
        }
        "e" => {
          let idx = dialog.selected_idx
          if idx >= 0 && idx < self.agent.config.models.length() {
            let model = self.agent.config.models[idx]
            let mode : @libtui.ConfigMode = if dialog.title == "Select Model" {
              ModelSelector
            } else {
              ConfigMenu
            }
            @libtui.open_edit_form(self.state.val, mode, model, idx)
          }
          self.full_redraw()
          return
        }
        "d" => {
          let idx = dialog.selected_idx
          if idx >= 0 && idx < self.agent.config.models.length() {
            let model = self.agent.config.models[idx]
            @libtui.request_confirmation(
              self.state.val,
              "delete_model",
              model.model,
              "Delete model '\{model.model}'? This cannot be undone.",
            )
          }
          self.full_redraw()
          return
        }
        _ => ()
      }
    @libtui.DialogState::Form(_) =>
      if key == "Escape" {
        @libtui.close_config_dialog(self.state.val)
        self.full_redraw()
        return
      }
    @libtui.DialogState::ConfigForm(mode~, form~, action~, target_idx~) =>
      match key {
        "Escape" => {
          @libtui.return_to_config_menu(self.state.val, self.agent, mode)
          self.full_redraw()
          return
        }
        "Tab" => {
          form.next_field()
          self.full_redraw()
          return
        }
        "Backspace" => {
          form.backspace()
          self.full_redraw()
          return
        }
        "Enter" => {
          // Mirror the controller: merge form values (Edit falls back to
          // existing values), then apply directly — the connection test is
          // mocked as successful in eval (no network).
          let existing = match action {
            @libtui.ConfigAction::Edit =>
              if target_idx >= 0 &&
                target_idx < self.agent.config.models.length() {
                Some(self.agent.config.models[target_idx])
              } else {
                None
              }
            @libtui.ConfigAction::Add => None
          }
          match
            @libtui.merge_config_form_values(
              action,
              form.collect_values(),
              existing,
            ) {
            Err(err) =>
              ignore(
                self.output.append_text(
                  "[error] \{err}",
                  @libtui.OutputKind::Text,
                ),
              )
            Ok(pending) => {
              match action {
                @libtui.ConfigAction::Add => {
                  let new_model = @config.ModelConfig::new(
                    pending.name,
                    pending.api_key,
                    pending.base_url,
                    pending.model,
                  )
                  new_model.anthropic_format = pending.anthropic_format
                  self.agent.config.add_model(new_model)
                  ignore(
                    self.output.append_text(
                      "[system] Model '\{pending.name}' added",
                      @libtui.OutputKind::Text,
                    ),
                  )
                }
                @libtui.ConfigAction::Edit =>
                  if target_idx >= 0 &&
                    target_idx < self.agent.config.models.length() {
                    let existing = self.agent.config.models[target_idx]
                    let updated : @config.ModelConfig = {
                      id: existing.id,
                      type_: existing.type_,
                      api_key: pending.api_key,
                      base_url: pending.base_url,
                      model: pending.model,
                      anthropic_format: existing.anthropic_format,
                      runtime_id: existing.runtime_id,
                      media_type: existing.media_type,
                    }
                    self.agent.config.models[target_idx] = updated
                    match self.agent.config.current_model_id {
                      Some(id) if id == updated.id =>
                        self.state.val.model_name = updated.model
                      _ => ()
                    }
                    ignore(
                      self.output.append_text(
                        "[system] Model '\{updated.id}' updated",
                        @libtui.OutputKind::Text,
                      ),
                    )
                  }
              }
              // Configuration summary (mirrors print_config_summary)
              match self.agent.config.current_model() {
                Some(m) => {
                  let format = if m.anthropic_format {
                    "Anthropic"
                  } else {
                    "OpenAI"
                  }
                  ignore(
                    self.output.append_text(
                      "[system] Configuration updated!\n  Current Model: \{m.model}\n  API Key: \{@libtui.mask_api_key_summary(m.api_key)}\n  Base URL: \{m.base_url}\n  Format: \{format}",
                      @libtui.OutputKind::Text,
                    ),
                  )
                }
                None => ()
              }
              @libtui.return_to_config_menu(self.state.val, self.agent, mode)
            }
          }
          self.full_redraw()
          return
        }
        _ =>
          // Single printable characters go to the focused form field
          if key.length() == 1 {
            for c in key {
              form.input_char(c)
            }
            self.full_redraw()
            return
          }
      }
    _ => ()
  }
  // If a confirmation dialog is pending, route keys to it first.
  if @libtui.has_pending_confirmation(self.state.val) {
    let is_delete = match self.state.val.pending_confirmation {
      Some(p) => p.tool_name == "delete_model"
      None => false
    }
    let delete_idx = if is_delete {
      match self.state.val.dialog {
        @libtui.DialogState::ConfigMenu(d) => d.selected_idx
        _ => -1
      }
    } else {
      -1
    }
    if key == "Shift+Tab" {
      // Mirror the real controller: approve all tools for this session
      // (no permission-mode cycling while a confirmation is pending).
      self.state.val.approved_all_tools = true
      self.confirmation_result = Some(true)
      @libtui.consume_confirmation(self.state.val)
      ignore(
        self.output.append_text(
          "[system] All tools auto-approved for this session",
          @libtui.OutputKind::Text,
        ),
      )
      self.full_redraw()
      return
    }
    let result = match key {
      "y" | "Y" => Some(true)
      "n" | "N" => Some(false)
      "Enter" => Some(@libtui.confirmation_default_yes(self.state.val))
      "Escape" => Some(false)
      _ => None
    }
    match result {
      Some(r) => {
        self.confirmation_result = Some(r)
        @libtui.consume_confirmation(self.state.val)
        if is_delete {
          // Local UI confirmation (delete_model): never touches the
          // agent confirmation queue — same rule as the real controller.
          if r && delete_idx >= 0 {
            self.perform_model_delete(delete_idx)
          } else if !r {
            @libtui.open_config_menu(self.state.val, self.agent)
          }
        }
        self.full_redraw()
      }
      None => ()
    }
    return
  }
  match key {
    "Enter" => self.handle_enter()
    "Ctrl+J" => self.input.handle_enter()
    "Ctrl+C" => self.quit = true
    "Ctrl+D" if self.input.is_empty() => self.quit = true
    "Ctrl+K" => self.input.kill_to_end()
    "Ctrl+U" => self.input.kill_to_start()
    "Ctrl+W" => self.input.kill_word()
    "Ctrl+L" => self.full_redraw()
    "Tab" => if self.input.is_empty() { self.input.insert_char('/') }
    "Shift+Tab" => {
      // Shift+Tab (no dialog pending): toggle permission mode between
      // confirm_safes and auto_approve (spec tui-parity-05, task 2).
      let cur = @config.PermissionMode::from_string(
        self.state.val.permission_mode,
      )
      let next = @libtui.cycle_permission_mode(
        match cur {
          Some(m) => m
          None => @config.ConfirmSafes
        },
      )
      self.state.val.permission_mode = next.to_string_value()
      self.agent.config.permission_mode = next
      ignore(
        self.output.append_text(
          "[system] Permission mode: \{next.to_string_value()}",
          @libtui.OutputKind::Text,
        ),
      )
      self.full_redraw()
    }
    "Backspace" => self.input.backspace()
    "Delete" => self.input.delete_forward()
    "Left" => self.input.cursor_left()
    "Right" => self.input.cursor_right()
    "Up" => self.input.cursor_up()
    "Down" => self.input.cursor_down()
    "Home" => self.input.cursor_home()
    "End" => self.input.cursor_end()
    "Escape" =>
      // ESC with nothing to dismiss: open the Time Machine menu
      // (mirrors the controller; Ruby ui2 input_area.rb:255-262).
      if @libtui.open_time_machine_menu(self.state.val) {
        self.full_redraw()
        return
      }
    _ => ()
  }
  if key != "Enter" {
    self.full_redraw()
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
    // Bare text exit/quit: exact match (trimmed) triggers quit
    let trimmed = text.trim().to_owned()
    if trimmed == "exit" || trimmed == "quit" {
      self.on_exit_save()
      self.quit = true
      return
    }
    // "?" is an alias for /help (mirrors the controller; Ruby
    // input_area.rb:824-827).
    if trimmed == "?" {
      match @libtui.execute(@libtui.SlashCommand::Help, self.agent) {
        Ok(msg) =>
          ignore(self.output.append_text(msg, @libtui.OutputKind::Text))
        Err(err) =>
          ignore(
            self.output.append_text("[error] \{err}", @libtui.OutputKind::Text),
          )
      }
      self.full_redraw()
      return
    }
    // Route slash commands through the shared parser, mirroring the real
    // controller's behavior (TuiController::handle_enter_key).
    if text[0:1] == "/" {
      match @libtui.parse_slash_command(text) {
        Ok(cmd) => {
          self.handle_slash_command(cmd)
          return
        }
        // Not a static command — try the skill registry (priority:
        // static command > skill > regular input).
        Err(_) =>
          match self.agent.skill_registry.find_skill_command(text) {
            Some((skill, args)) => {
              // Mirror the controller's skill invocation display (no real
              // agent run in eval): show the command, then a mock reply.
              ignore(
                self.output.append_text(
                  "[user] \{text}",
                  @libtui.OutputKind::Text,
                ),
              )
              ignore(self.state.val.time_machine.start_new_task(Some(text)))
              let arg_note = if args.length() > 0 {
                " with arguments: \{args}"
              } else {
                ""
              }
              ignore(
                self.output.append_text(
                  "[system] Invoked skill: /\{skill.name}\{arg_note}",
                  @libtui.OutputKind::Text,
                ),
              )
              match self.output.last_entry_id() {
                Some(id) => self.output.commit_through(id)
                None => ()
              }
              self.full_redraw()
              return
            }
            None => ()
          }
      }
    }
    // Add user message to output
    ignore(self.output.append_text("[user] \{text}", @libtui.OutputKind::Text))
    // Time machine: open a new task (mirrors the real controller)
    ignore(self.state.val.time_machine.start_new_task(Some(text)))
    // Commit it
    match self.output.last_entry_id() {
      Some(id) => self.output.commit_through(id)
      None => ()
    }
    // Update state
    self.state.val.mode = @libtui.TuiMode::Running
    // Auto-show the todo area while the agent works (mirrors the controller)
    self.state.val.todo_area.show()
    // Simulate agent response (append mock response)
    let response_text = if self.mock_response.length() > 0 {
      self.mock_response
    } else {
      "(eval mock response)"
    }
    ignore(
      self.output.append_text(
        "[assistant] \{response_text}",
        @libtui.OutputKind::Text,
      ),
    )
    match self.output.last_entry_id() {
      Some(id) => self.output.commit_through(id)
      None => ()
    }
    // Reset state
    self.state.val.mode = @libtui.TuiMode::Idle
    // Auto-hide the todo area on idle (mirrors the controller)
    self.state.val.todo_area.hide()
    self.state.val.agent_status.set("idle")
    // Full redraw
    self.full_redraw()
  }
}

///|
/// Open the sub-model drawer for the selected card when expandable (eval
/// mirror of the controller's try_open_submodel_drawer).
fn TuiEvalSimulator::try_open_submodel_drawer(
  self : TuiEvalSimulator,
  dialog : @libtui.ConfigMenuDialog,
) -> Unit {
  match dialog.get_selected() {
    Some(item) =>
      for m in self.agent.config.models {
        if m.id == item.value && @libtui.provider_submodels(m).length() >= 2 {
          @libtui.open_submodel_drawer(self.state.val, self.agent, m)
        }
      }
    None => ()
  }
}

///|
/// Apply a card switch (+ optional sub-model overlay) in eval: no disk
/// persistence, everything else mirrors the controller.
fn TuiEvalSimulator::apply_model_card_switch(
  self : TuiEvalSimulator,
  card_id : String,
  sub_model : String?,
) -> Unit {
  match self.agent.config.switch_model_by_id(card_id) {
    Ok(_) => {
      self.agent.rebuild_client_from_config()
      self.agent.set_session_sub_model(sub_model)
      self.state.val.model_name = self.agent.client.model
      let sub_note = match sub_model {
        Some(s) => " (sub-model: \{s})"
        None => ""
      }
      ignore(
        self.output.append_text(
          "[system] Model switched to: \{self.agent.client.model}\{sub_note}",
          @libtui.OutputKind::Text,
        ),
      )
      @libtui.close_config_dialog(self.state.val)
    }
    Err(msg) =>
      ignore(
        self.output.append_text("[error] \{msg}", @libtui.OutputKind::Text),
      )
  }
}

///|
/// Execute a parsed slash command against the mock agent, mirroring
/// TuiController::handle_enter_key's routing and output format.
fn TuiEvalSimulator::handle_slash_command(
  self : TuiEvalSimulator,
  cmd : @libtui.SlashCommand,
) -> Unit {
  match cmd {
    @libtui.SlashCommand::Exit | @libtui.SlashCommand::Quit => {
      self.on_exit_save()
      self.quit = true
    }
    @libtui.SlashCommand::Theme(name~) => {
      ignore(
        self.output.append_text(
          "[system] Theme switched to: \{name}",
          @libtui.OutputKind::Text,
        ),
      )
      match self.output.last_entry_id() {
        Some(id) => self.output.commit_through(id)
        None => ()
      }
      self.full_redraw()
    }
    @libtui.SlashCommand::Undo =>
      // Open the interactive Time Machine menu (mirrors the controller);
      // info line when there is no history.
      if @libtui.open_time_machine_menu(self.state.val) {
        self.full_redraw()
      } else {
        ignore(
          self.output.append_text(
            "[system] No tasks in history to undo",
            @libtui.OutputKind::Text,
          ),
        )
        self.full_redraw()
      }
    Clear => {
      // New-session semantics (mirrors the controller): agent resets in
      // place via execute, TUI-side session state resets alongside, and
      // the output buffer shows only the fresh-start notice.
      ignore(@libtui.execute(cmd, self.agent))
      @libtui.reset_tui_session_state(self.state.val, self.agent)
      self.output.clear()
      ignore(
        self.output.append_text(
          "[system] Session cleared. Starting fresh.",
          @libtui.OutputKind::Text,
        ),
      )
      self.full_redraw()
    }
    @libtui.SlashCommand::Config => {
      // No-arg /config: open config menu dialog
      if self.agent.config.models.length() == 0 {
        ignore(
          self.output.append_text(
            "[system] No models configured. Use /config to open the configuration menu.",
            @libtui.OutputKind::Text,
          ),
        )
        self.full_redraw()
        return
      }
      @libtui.open_config_menu(self.state.val, self.agent)
      self.render_config_dialog()
    }
    @libtui.SlashCommand::Model(name~) if name == "" => {
      // No-arg /model: open model selector dialog
      if self.agent.config.models.length() <= 1 {
        ignore(
          self.output.append_text(
            "[system] Only one model configured. Use /model <name> to switch.",
            @libtui.OutputKind::Text,
          ),
        )
        self.full_redraw()
        return
      }
      @libtui.open_model_selector(self.state.val, self.agent)
      self.render_config_dialog()
    }
    @libtui.SlashCommand::Model(_) => {
      // With-arg /model: execute the shared switch path, then mirror the
      // controller's status-bar sync (disk persistence is skipped in eval).
      let result = @libtui.execute(cmd, self.agent)
      match result {
        Ok(msg) => {
          self.state.val.model_name = self.agent.client.model
          ignore(
            self.output.append_text("[system] \{msg}", @libtui.OutputKind::Text),
          )
        }
        Err(err) =>
          ignore(
            self.output.append_text("[error] \{err}", @libtui.OutputKind::Text),
          )
      }
      self.full_redraw()
    }
    _ => {
      let result = @libtui.execute(cmd, self.agent)
      match result {
        Ok(msg) =>
          ignore(
            self.output.append_text("[system] \{msg}", @libtui.OutputKind::Text),
          )
        Err(err) =>
          ignore(
            self.output.append_text("[error] \{err}", @libtui.OutputKind::Text),
          )
      }
      match self.output.last_entry_id() {
        Some(id) => self.output.commit_through(id)
        None => ()
      }
      self.full_redraw()
    }
  }
}

// ── Assertions ────────────────────────────────────────────────────────

///|
/// Mirror the real controller's on_exit_save: when the session had
/// content, the production code persists it via `agent.to_session_data()`
/// + `save_session` and prints a saved notice. The eval adapter mirrors
/// the observable output only (no disk I/O in tests).
fn TuiEvalSimulator::on_exit_save(self : TuiEvalSimulator) -> Unit {
  // entry_count > 1 means something beyond the startup banner was written
  if self.output.entry_count() > 1 || self.agent.history.size() > 0 {
    ignore(
      self.output.append_text(
        "[system] Session saved to disk: clacky --attach \{self.state.val.session_id}",
        @libtui.OutputKind::Text,
      ),
    )
  }
}

///|
/// Perform model deletion after confirmation (mirrors the real
/// controller, without disk persistence).
fn TuiEvalSimulator::perform_model_delete(
  self : TuiEvalSimulator,
  idx : Int,
) -> Unit {
  if idx >= 0 && idx < self.agent.config.models.length() {
    let removed = self.agent.config.models[idx]
    ignore(self.agent.config.models.remove(idx))
    match self.agent.config.current_model_id {
      Some(id) if id == removed.id =>
        if self.agent.config.models.length() > 0 {
          self.agent.config.current_model_id = Some(
            self.agent.config.models[0].id,
          )
          self.state.val.model_name = self.agent.config.models[0].model
        } else {
          self.agent.config.current_model_id = None
          ignore(
            self.output.append_text(
              "[warning] No models configured after delete",
              @libtui.OutputKind::Text,
            ),
          )
        }
      _ => ()
    }
    ignore(
      self.output.append_text(
        "[system] Model '\{removed.model}' deleted",
        @libtui.OutputKind::Text,
      ),
    )
    @libtui.open_config_menu(self.state.val, self.agent)
  }
}

///|
/// Emit a real agent hook event through the agent's hook manager,
/// driving the production hook → state/output pipeline.
fn TuiEvalSimulator::emit_hook(
  self : TuiEvalSimulator,
  event : String,
  args : Map[String, Json],
) -> Unit {
  let get_s = fn(k : String) -> String {
    match args.get(k) {
      Some(String(sv)) => sv
      _ => ""
    }
  }
  let get_i = fn(k : String) -> Int {
    match args.get(k) {
      Some(Number(n, ..)) => n.to_int()
      _ => 0
    }
  }
  let get_f = fn(k : String) -> Double {
    match args.get(k) {
      Some(Number(n, ..)) => n
      _ => 0.0
    }
  }
  let get_b = fn(k : String) -> Bool {
    match args.get(k) {
      Some(True) => true
      _ => false
    }
  }
  match event {
    "tool_executing" =>
      self.agent.hook_manager.emit(
        @agent.HookEvent::ToolExecuting(get_s("tool_name"), get_s("tool_args")),
      )
    "tool_executed" =>
      self.agent.hook_manager.emit(
        @agent.HookEvent::ToolExecuted(get_s("tool_name"), {
          id: "eval_call",
          content: get_s("content"),
          is_error: get_b("is_error"),
          image_inject: None,
        }),
      )
    "tool_denied" =>
      self.agent.hook_manager.emit(
        @agent.HookEvent::ToolDenied(get_s("tool_name")),
      )
    "usage_updated" => {
      let input_tokens = get_i("input_tokens")
      let output_tokens = get_i("output_tokens")
      self.agent.hook_manager.emit(
        @agent.HookEvent::UsageUpdated({
          delta_tokens: get_i("delta"),
          prompt_tokens: input_tokens,
          completion_tokens: output_tokens,
          total_tokens: input_tokens + output_tokens,
          cache_write: 0,
          cache_read: get_i("cached"),
          cost: get_f("cost"),
          cost_source: @agent.CostSource::Price,
        }),
      )
    }
    "stream_chunk" =>
      self.agent.hook_manager.emit(@agent.HookEvent::StreamChunk(get_s("text")))
    _ => ()
  }
  self.full_redraw()
}

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
        "Status: '\{self.screen.get_row_trimmed(self.status_row())}'"
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
    DialogContains(text~) => {
      let passed = self.check_dialog_region(text)
      let desc = "dialog contains '\{text}'"
      let detail = if passed { "" } else { "NOT FOUND in dialog region" }
      { description: desc, passed, detail }
    }
  }
}

///|
/// Check if the status bar row (first row of the bottom fixed area)
/// contains text.
fn TuiEvalSimulator::check_status_region(
  self : TuiEvalSimulator,
  text : String,
) -> Bool {
  self.screen.row_contains(self.status_row(), text)
}

///|
/// Check if the input region (the wrapped input lines) contains text.
fn TuiEvalSimulator::check_input_region(
  self : TuiEvalSimulator,
  text : String,
) -> Bool {
  let content_width = @libtui.effective_content_width(self.screen.width)
  let input_rows = self.input.render_wrapped_lines(content_width).length()
  let top = self.input_top_row()
  for row = top; row < top + input_rows; row = row + 1 {
    if self.screen.row_contains(row, text) {
      return true
    }
  }
  false
}

///|
/// Check if the output region (above the bottom fixed area) contains text.
fn TuiEvalSimulator::check_output_region(
  self : TuiEvalSimulator,
  text : String,
) -> Bool {
  let bottom = self.first_fixed_row() - 1
  for row = 1; row <= bottom; row = row + 1 {
    if self.screen.row_contains(row, text) {
      return true
    }
  }
  false
}

///|
/// Render active config/model dialog as text lines on the VirtualScreen.
fn TuiEvalSimulator::render_config_dialog(self : TuiEvalSimulator) -> Unit {
  match self.state.val.dialog {
    @libtui.DialogState::ConfigMenu(dialog)
    | @libtui.DialogState::TimeMachineMenu(dialog)
    | @libtui.DialogState::ModelDrawer(dialog~, ..) => {
      let lines : Array[String] = []
      lines.push("┌── \{dialog.title} ──┐")
      for i in 0..<dialog.items.length() {
        let item = dialog.items[i]
        let marker = if i == dialog.selected_idx { "▶" } else { " " }
        lines.push("│ \{marker} \{item.label} │")
      }
      lines.push("│ ↑↓/jk Navigate  Enter Select  Esc Close │")
      lines.push(
        "└───────────────────────────────────┘",
      )
      self.write_dialog_lines(lines)
    }
    @libtui.DialogState::Form(form) => self.write_dialog_lines(form_lines(form))
    @libtui.DialogState::ConfigForm(form~, ..) =>
      self.write_dialog_lines(form_lines(form))
    _ => ()
  }
}

///|
/// Build the display lines for a form dialog.
fn form_lines(form : @libtui.FormDialog) -> Array[String] {
  let lines : Array[String] = []
  lines.push("┌── \{form.title} ──┐")
  for field in form.fields {
    lines.push("│ \{field.label}: \{field.value} │")
  }
  lines.push("│ Tab Next  Enter Submit  Esc Cancel │")
  lines.push(
    "└───────────────────────────────────┘",
  )
  lines
}

///|
/// Write dialog lines above the bottom fixed area (rows are clamped to the
/// drawable area, protecting against a negative base row).
fn TuiEvalSimulator::write_dialog_lines(
  self : TuiEvalSimulator,
  lines : Array[String],
) -> Unit {
  let bottom = self.first_fixed_row() - 1
  let base_row = bottom - lines.length() + 1
  for i in 0..<lines.length() {
    let row = base_row + i
    if row >= 1 && row <= bottom {
      self.screen.move_cursor(row, 1)
      self.screen.clear_to_eol()
      self.screen.write_string(lines[i])
    }
  }
}

///|
/// Check if the dialog region (rows above the bottom fixed area) contains text.
fn TuiEvalSimulator::check_dialog_region(
  self : TuiEvalSimulator,
  text : String,
) -> Bool {
  let bottom = self.first_fixed_row() - 1
  for row = 1; row <= bottom; row = row + 1 {
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
  sim.mock_response = scenario.setup.mock_response

  // Initial full redraw
  sim.full_redraw()

  // Track assertion results from both inline Assert actions and final assertions.
  let results : Array[@eval.EvalAssertionResult] = []
  let mut all_passed = true
  fn record_result(result : @eval.EvalAssertionResult) -> Unit {
    if !result.passed {
      all_passed = false
    }
    results.push(result)
  }

  // Execute actions
  for action in scenario.actions {
    match action {
      Type(text~) => sim.type_text(text)
      Press(key~) => sim.press_key(key)
      Screenshot => ignore(sim.screenshot())
      Wait(_) => ()
      SetConfirmation(tool_name~, tool_args~, prompt_text~, default_yes~) => {
        @libtui.request_confirmation(
          sim.state.val,
          tool_name,
          tool_args,
          prompt_text,
          default_yes~,
        )
        sim.confirmation_result = None
        sim.full_redraw()
      }
      InjectOutput(text~, kind~) => {
        let output_kind = if kind == "system" {
          @libtui.OutputKind::System
        } else {
          @libtui.OutputKind::Text
        }
        ignore(sim.output.append_text(text, output_kind))
        match sim.output.last_entry_id() {
          Some(id) => sim.output.commit_through(id)
          None => ()
        }
        sim.full_redraw()
      }
      EmitHook(event~, args~) => sim.emit_hook(event, args)
      Assert(assertion~) => record_result(sim.check_assertion(assertion))
    }
    if sim.quit {
      break
    }
  }

  // Final render
  sim.full_redraw()

  // Check final assertions
  for assertion in scenario.assertions {
    record_result(sim.check_assertion(assertion))
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
