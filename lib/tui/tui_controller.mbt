///|
/// TuiController: main event loop and orchestration for the inline TUI.
///
/// Phase 5 implementation: ties together ScreenBuffer, OutputBuffer,
/// LayoutManager, StatusBar, InputArea, and AgentHookHandler into a
/// functional terminal UI with raw-mode event processing.
///
/// Architecture:
/// - Terminal events (key/resize) arrive via `tty.read_event`
/// - Agent runs synchronously in a background task; hooks update TuiState
/// - Main loop redraws on every event + periodic spinner tick
/// - User input → LineEditor → Enter submits to agent

///|
/// Escape sequence timeout for event reading (ms).
let esc_timeout_ms : Int = 50

///|
/// Application version shown in the startup banner.
/// Mirrors `VERSION` in cmd/main.mbt (not importable from lib).
let app_version : String = "0.1.0"

///|

///|
/// Controller for the inline TUI application.
pub(all) struct TuiController {
  tty : @tty.Tty
  mut term_width : Int
  output : OutputBuffer
  mut term_height : Int
  status_bar : StatusBar
  input : InputArea
  state : Ref[TuiState]
  agent : @agent.Agent
  hooks : AgentHookHandler
  mut quit : Bool
  mut dirty : Bool
  mut agent_running : Bool
  /// Body lines currently on screen (incremental renderer state).
  /// Row i = painted_body[i]. Entries stay live until they physically
  /// scroll into the terminal's native scrollback.
  mut painted_body : Array[String]
  /// Fixed-area height at the last paint (0 = unpainted).
  mut last_fixed_height : Int
  /// Whether the screen has been cleared and initialized.
  mut screen_inited : Bool
  events : @aqueue.Queue[TuiEvent]
  mut confirmation_response : @aqueue.Queue[Bool]?
  /// Reply queue for request_user_feedback (user answer delivered while
  /// the agent task is still running).
  mut feedback_response : @aqueue.Queue[String]?
  /// True while the agent awaits a feedback reply (Enter submits the
  /// answer instead of starting a new agent run).
  mut feedback_pending : Bool
  mut agent_task : @async.Task[@agent.RunResult]?
  thinking_animator : ThinkingVerbAnimator
  mut last_thinking_len : Int
  agent_output_sync : AgentOutputSync
  mut theme : Theme
  suggestions : CommandSuggestions
  mut suggestions_active : Bool
  /// Terminal rows currently occupied by the suggestion dropdown.
  mut suggestions_rows_drawn : Array[Int]
  /// Terminal rows currently occupied by progress indicator lines.
  mut progress_rows_drawn : Array[Int]
  /// System tips row state (2s auto-clear via Tick).
  tips : TipsState
  /// Config form submit awaiting its connection test result.
  mut pending_config_test : PendingConfigTest?
}

///|
/// Create a new TuiController from a Tty handle and Agent.
pub fn TuiController::new(
  tty : @tty.Tty,
  agent : @agent.Agent,
) -> TuiController {
  let output = OutputBuffer::new()
  let state = Ref(TuiState::from_agent(agent))
  let hooks = AgentHookHandler::new(state, agent=Some(agent))
  hooks.set_output(output)
  let (tw, th) = query_size_safe(tty)
  let controller = {
    tty,
    output,
    term_width: tw,
    term_height: th,
    status_bar: StatusBar::new(),
    input: InputArea::multiline_new(),
    state,
    agent,
    hooks,
    quit: false,
    dirty: true,
    agent_running: false,
    painted_body: [],
    last_fixed_height: 0,
    screen_inited: false,
    events: @aqueue.Queue::Queue(kind=Unbounded),
    confirmation_response: None,
    feedback_response: None,
    feedback_pending: false,
    agent_task: None,
    thinking_animator: ThinkingVerbAnimator::new(),
    last_thinking_len: 0,
    agent_output_sync: AgentOutputSync::new(),
    theme: Theme::default_(),
    suggestions: build_command_suggestions(),
    suggestions_active: false,
    suggestions_rows_drawn: [],
    progress_rows_drawn: [],
    tips: TipsState::new(),
    pending_config_test: None,
  }
  // Merge user-invocable skills into the Tab-completion view (Ruby
  // skills_by_command): they appear alongside the static slash commands
  // with their description and argument hint.
  for skill in agent.skill_registry.list_user_invocable() {
    controller.suggestions.add_command(SuggestionItem::{
      name: "/\{skill.name}",
      description: match skill.description {
        Some(d) => d
        None => "Skill"
      },
      usage: match skill.argument_hint {
        Some(h) => h
        None => ""
      },
    })
  }
  // Register render_effect to auto-set dirty when Signal fields change
  let _ = @mizchi/signals.render_effect(fn() {
    let _ = controller.state.val.streaming_buffer.get()
    let _ = controller.state.val.tool_output.get()
    let _ = controller.state.val.thinking_buffer.get()
    let _ = controller.state.val.agent_status.get()
    let _ = controller.state.val.streaming_active.get()
    controller.dirty = true
  })
  controller
}

// ── Command suggestions / progress helpers ───────────────────────

///|
/// What the Up/Down arrow keys do, given the current UI state.
priv enum ArrowKeyAction {
  /// Navigate the command suggestion dropdown.
  NavigateSuggestions
  /// Browse input history (single-line input only).
  BrowseHistory
  /// Move the cursor between lines (multi-line input).
  MoveCursor
}

///|
/// Arrow keys navigate the suggestion dropdown when it is active, browse
/// input history in single-line mode, and move the cursor otherwise.
fn arrow_key_action(
  suggestions_active : Bool,
  line_count : Int,
) -> ArrowKeyAction {
  if suggestions_active {
    NavigateSuggestions
  } else if line_count <= 1 {
    BrowseHistory
  } else {
    MoveCursor
  }
}

///|
/// Whether the suggestion dropdown should track the current input content.
fn should_show_suggestions(text : String, line_count : Int) -> Bool {
  line_count <= 1 && text.has_prefix("/")
}

///|
/// Whether accepting a suggestion should immediately submit it (single Enter).
///
/// A completed slash command (starts with "/") is executable as-is, so it is
/// submitted in the same keystroke to match the reference TUI (SPEC-03).
/// Future non-command completions (argument values, paths) would not start
/// with "/" and remain complete-only, leaving the user to keep editing.
fn should_submit_accepted_suggestion(cmd : String) -> Bool {
  cmd.has_prefix("/")
}

///|
/// Build the suggestion dropdown from the registered slash commands so the
/// two never drift apart (includes /theme, /todo, /meeting, ...).
fn build_command_suggestions() -> CommandSuggestions {
  let parser = SlashCommandParser::new()
  let items : Array[SuggestionItem] = []
  for cmd in parser.commands {
    items.push(SuggestionItem::{
      name: "/\{cmd.name}",
      description: cmd.description,
      usage: cmd.usage,
    })
  }
  let suggestions = CommandSuggestions::new()
  suggestions.set_commands(items)
  suggestions
}

///|
/// Compute the 1-based terminal rows for a band of `count` lines stacked
/// `gap` rows above the input box top border.
///
/// gap = 0 places the band's bottom row directly above the input box
/// (suggestion dropdown); gap = 1 + todo_lines places it above the todo
/// area (progress indicators). Rows may fall outside the drawable area on
/// tiny terminals — callers must skip rows <= 1 (the status bar).
fn _band_rows(
  screen_h : Int,
  input_h : Int,
  gap : Int,
  count : Int,
) -> Array[Int] {
  let rows : Array[Int] = []
  for i = 0; i < count; i = i + 1 {
    rows.push(screen_h - input_h - gap - count + 1 + i)
  }
  rows
}

// ── Rendering ─────────────────────────────────────────────────────

///|
/// Full screen redraw: clear screen, reset painted state, repaint
/// everything from scratch. Used on resize, Ctrl+L, /clear, theme switch.
pub async fn TuiController::full_redraw(self : TuiController) -> Unit {
  self.full_redraw_screen()
}

///|
/// Incremental redraw: paint only the changed rows (body diff + fixed
/// area repaint). Called on every dirty tick and key press.
///
/// Entries stay live while they're on screen and commit only when they
/// physically scroll into the terminal's native scrollback — this is
/// what prevents the "reply flashes then disappears" bug.
pub async fn TuiController::redraw(self : TuiController) -> Unit {
  self.frame_incremental()
}

///|
/// Note: `commit_output()` was removed in the incremental renderer.
/// Entries now commit only when they physically scroll into the
/// terminal's native scrollback via `scroll_phys()`. This is the
/// key fix for the "reply flashes then disappears" bug: in the old
/// full-redraw model, commit_output after AgentDone marked entries
/// committed, then the next redraw painted an empty body.

///|
/// Update the suggestion dropdown based on current input.
fn TuiController::update_suggestions(self : TuiController) -> Unit {
  let text = self.input.text()
  if should_show_suggestions(text, self.input.line_count()) {
    if text == "/" {
      // Bare "/": promote context-relevant commands to the top of the
      // dropdown (all commands stay visible); prefix filtering kicks in
      // as soon as the user types more.
      self.suggestions.update_context_filter(self.state.val)
    } else {
      self.suggestions.update_filter(text)
    }
    self.suggestions_active = self.suggestions.is_visible()
  } else {
    self.close_suggestions()
  }
}

///|
/// Hide the suggestion dropdown and reset its state.
fn TuiController::close_suggestions(self : TuiController) -> Unit {
  self.suggestions.hide()
  self.suggestions_active = false
}

///|
/// Restore terminal to normal state on exit.
async fn TuiController::restore_terminal(self : TuiController) -> Unit {
  // Reset styles, show cursor, move to bottom of screen
  self.tty.write_string(
    "\u{1b}[0m\u{1b}[?25h\u{1b}[" + self.term_height.to_string() + ";1H\r\n",
  )
}

// ── Event Loop ───────────────────────────────────────────────────

///|
/// Main run loop: set up async event loop with Queue-based event dispatch.
pub async fn TuiController::run(self : TuiController) -> Unit {
  let req_q : @aqueue.Queue[(String, String)] = @aqueue.Queue::Queue(
    kind=Unbounded,
  )
  let resp_q : @aqueue.Queue[Bool] = @aqueue.Queue::Queue(kind=Unbounded)
  self.agent.confirmation_request = Some(req_q)
  self.agent.confirmation_response = Some(resp_q)
  self.confirmation_response = Some(resp_q)
  // Feedback bridge for request_user_feedback: agent pushes the question
  // onto fb_req_q, the bridge forwards it to the event loop, and the user's
  // answer is delivered back on fb_resp_q (mirrors the confirmation queue
  // mechanism; Web server side: handlers_ws.mbt setup_feedback_bridge).
  let fb_req_q : @aqueue.Queue[(String, String?, Array[String]?)] = @aqueue.Queue::Queue(
    kind=Unbounded,
  )
  let fb_resp_q : @aqueue.Queue[String] = @aqueue.Queue::Queue(kind=Unbounded)
  self.agent.feedback_request = Some(fb_req_q)
  self.agent.feedback_response = Some(fb_resp_q)
  self.feedback_response = Some(fb_resp_q)
  self.hooks.register_all(self.agent.hook_manager)
  // Wrap output lines at the real terminal width and show the startup
  // banner as the first output entry (it scrolls away naturally).
  self.output.width = self.term_width
  let banner_width = Banner::adaptive_width(self.term_width)
  let banner = {
    style: BannerStyle::Block,
    width: banner_width,
    use_color: true,
  }
  // Check if API key is missing
  let api_key_missing = self.agent.client.api_key.length() == 0
  // Check if workspace has rules
  let rules = @utils.WorkspaceRules::find_main(self.state.val.working_dir)
  let has_rules = rules.has_rules()
  let startup_banner = banner.render_startup(
    app_version,
    self.state.val.working_dir,
    self.state.val.permission_mode,
    has_rules,
    api_key_missing,
    terminal_width=self.term_width,
  )
  ignore(self.output.append_text(startup_banner, OutputKind::Text))
  self.tty.with_raw_mode(() => self.async_event_loop(req_q, resp_q, fb_req_q))
}

///|
/// Async event loop using task groups and Queue event dispatch.
async fn TuiController::async_event_loop(
  self : TuiController,
  req_q : @aqueue.Queue[(String, String)],
  _resp_q : @aqueue.Queue[Bool],
  fb_req_q : @aqueue.Queue[(String, String?, Array[String]?)],
) -> Unit {
  @async.with_task_group() <| group => {
    let events = self.events
    group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
      self.read_terminal_loop(events)
    }
    group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
      self.run_ticker(events)
    }
    group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
      self.run_confirmation_bridge(req_q, events)
    }
    group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
      self.run_feedback_bridge(fb_req_q, events)
    }
    self.main_loop(group)
  }
  self.restore_terminal()
}

///|
/// Terminal reader: pushes tty events to the Queue.
async fn TuiController::read_terminal_loop(
  self : TuiController,
  events : @aqueue.Queue[TuiEvent],
) -> Unit {
  while true {
    let event = self.tty.read_event(esc_timeout_ms~) catch {
      @async/io.ReaderClosed => {
        events.put(TerminalClosed)
        return
      }
      _ => return
    }
    events.put(Terminal(event))
  }
}

///|
/// Ticker: pushes Tick events every 200ms for spinner/animation.
async fn TuiController::run_ticker(
  _self : TuiController,
  events : @aqueue.Queue[TuiEvent],
) -> Unit {
  while true {
    @async.sleep(200)
    events.put(Tick)
  }
}

///|
/// Confirmation bridge: forwards agent confirmation requests to main Queue.
async fn TuiController::run_confirmation_bridge(
  _self : TuiController,
  req_q : @aqueue.Queue[(String, String)],
  events : @aqueue.Queue[TuiEvent],
) -> Unit {
  while true {
    let (tool, args) = req_q.get()
    events.put(ConfirmationRequest(tool, args))
  }
}

///|
/// Feedback bridge: forwards agent request_user_feedback requests to the
/// main event queue. The user's answer is delivered back on
/// self.feedback_response (see handle_enter_key). No timeout — CLI
/// semantics: the user decides when to answer.
async fn TuiController::run_feedback_bridge(
  _self : TuiController,
  req_q : @aqueue.Queue[(String, String?, Array[String]?)],
  events : @aqueue.Queue[TuiEvent],
) -> Unit {
  while true {
    let (question, context, options) = req_q.get()
    events.put(FeedbackRequest(question, context, options))
  }
}

///|
/// Main event processing loop.
async fn TuiController::main_loop(
  self : TuiController,
  group : @async.TaskGroup[Unit],
) -> Unit {
  self.full_redraw()
  while !self.quit {
    let event = self.events.get()
    match event {
      Terminal(ev) =>
        match ev {
          Input(input) => self.handle_input(input)
          Resize(_) => {
            let (tw, th) = query_size_safe(self.tty)
            self.term_width = tw
            self.term_height = th
            self.output.width = self.term_width
            self.full_redraw()
          }
        }
      ConfirmationRequest(tool, args) =>
        if self.state.val.approved_all_tools {
          // Shift+Tab "approve all for this session": auto-approve without
          // showing a dialog.
          match self.confirmation_response {
            Some(q) => ignore(q.try_put(true))
            None => ()
          }
        } else {
          let prompt = build_tool_prompt(tool, args)
          request_confirmation(self.state.val, tool, args, prompt)
          let dialog = ApprovalDialog::new(tool, args)
          self.state.val.dialog = DialogState::Approval(dialog)
          self.dirty = true
          self.redraw()
        }
      FeedbackRequest(question, _context, _options) => {
        // The FeedbackRequested hook already rendered the question; switch
        // the input area into feedback-answer mode so Enter delivers the
        // reply to the blocked agent task instead of starting a new run.
        self.feedback_pending = true
        ignore(question)
        self.dirty = true
        self.redraw()
      }
      AgentDone(result) => {
        self.agent_running = false
        self.agent_task = None
        self.feedback_pending = false
        self.state.val.mode = TuiMode::Idle
        // Auto-hide the todo area on idle (data preserved; Ruby ui2
        // set_idle_status → hide_todos).
        self.state.val.todo_area.hide()
        self.state.val.total_cost = result.total_cost_usd
        self.state.val.iterations = result.iterations
        // Mirror finalized "[assistant]" replies into the output buffer
        ignore(
          self.agent_output_sync.sync_messages(
            self.state.val.messages,
            self.output,
          ),
        )
        // Draw the new entries while still live, then mark them committed —
        // committed lines are never re-rendered by redraw_live.
        self.redraw()
        self.dirty = true
      }
      AgentError(msg) => {
        self.agent_running = false
        self.agent_task = None
        self.feedback_pending = false
        self.state.val.mode = TuiMode::Idle
        // Auto-hide the todo area on idle (same as AgentDone).
        self.state.val.todo_area.hide()
        ignore(
          self.agent_output_sync.sync_messages(
            self.state.val.messages,
            self.output,
          ),
        )
        ignore(self.output.append_text("[error] \{msg}", OutputKind::Text))
        self.redraw()
        self.dirty = true
      }
      SubmitInput(text) => self.start_agent(group, text)
      StartConnectionTest(pending) => self.start_connection_test(group, pending)
      ConnectionTestDone(success, message) =>
        self.finish_connection_test(success, message)
      Tick => {
        // Increment tick counter for spinner animation
        self.state.val.tick_count = self.state.val.tick_count + 1
        // System tips auto-clear 2s (10 ticks) after being set
        if self.tips.is_expired(self.state.val.tick_count) {
          self.tips.clear()
          self.dirty = true
        }
        // Poll the streaming buffer — hooks update it via Ref, bypassing
        // the event queue, so the Tick timer drives live reply rendering.
        // Note: dirty flag is auto-set by render_effect when Signal fields change
        ignore(
          self.agent_output_sync.sync_streaming(
            self.state.val.streaming_buffer.get(),
            self.state.val.messages,
            self.output,
          ),
        )
        if self.agent_running || self.state.val.progress_stack.has_open() {
          // Keep redrawing while the agent runs so the progress band's
          // spinner animates on every Tick.
          self.dirty = true
        }
        if self.state.val.thinking_buffer.get().length() !=
          self.last_thinking_len {
          self.last_thinking_len = self.state.val.thinking_buffer.get().length()
          truncate_thinking_buffer(self.state.val)
        }
      }
      TerminalClosed => self.quit = true
    }
    if self.dirty {
      self.redraw()
      self.dirty = false
    }
  }
  // Exit save prompt: output session-saved message before leaving the loop
  self.on_exit_save()
}

// ── Input Handling ───────────────────────────────────────────────

///|
/// Dispatch an input event.
async fn TuiController::handle_input(
  self : TuiController,
  input : @tty/input.InputEvent,
) -> Unit {
  match input {
    Key(key) => self.handle_key(key)
    Paste(text) => {
      // Paste placeholder: collapse >5-line pastes into [#N Paste Text]
      let n_lines = paste_line_count(text)
      if n_lines > 5 {
        self.state.val.paste_placeholder_count = self.state.val.paste_placeholder_count +
          1
        let num = self.state.val.paste_placeholder_count
        self.state.val.paste_placeholders.push((num, text))
        let tag = paste_placeholder_tag(num)
        // Insert the placeholder text instead of the full paste
        self.input.insert_text(tag)
      } else {
        self.input.insert_text(text)
      }
      self.update_suggestions()
      self.dirty = true
    }
    Mouse(_) => ()
    FocusIn => ()
    FocusOut => ()
    Unknown(_) => ()
  }
}

///|
/// Handle a key event.
async fn TuiController::handle_key(
  self : TuiController,
  key : @tty/input.KeyEvent,
) -> Unit {
  // If confirmation is pending, handle confirmation keys first
  if has_pending_confirmation(self.state.val) {
    match key.code {
      Char('c') if key.modifiers.ctrl() => {
        consume_confirmation(self.state.val)
        self.state.val.dialog = DialogState::NoDialog
        match self.confirmation_response {
          Some(q) => ignore(q.try_put(false))
          None => ()
        }
        match self.agent_task {
          Some(t) => t.cancel()
          None => ()
        }
        self.agent_task = None
        self.agent_running = false
        self.state.val.mode = TuiMode::Idle
        self.state.val.todo_area.hide()
        self.dirty = true
      }
      Char('y') | Char('Y') => {
        let is_delete = match self.state.val.pending_confirmation {
          Some(p) => p.tool_name == "delete_model"
          None => false
        }
        let delete_idx = if is_delete {
          match self.state.val.dialog {
            ConfigMenu(d) => d.selected_idx
            _ => -1
          }
        } else {
          -1
        }
        consume_confirmation(self.state.val)
        self.state.val.dialog = DialogState::NoDialog
        // Local UI confirmations (delete_model) must never touch the
        // agent's shared confirmation queue: a leftover value would be
        // consumed by the next real tool confirmation and silently
        // auto-approve it.
        if is_delete {
          if delete_idx >= 0 {
            self.perform_model_delete(delete_idx)
          }
        } else {
          match self.confirmation_response {
            Some(q) => ignore(q.try_put(true))
            None => ()
          }
        }
        self.dirty = true
      }
      Char('n') | Char('N') | Escape => {
        let is_delete = match self.state.val.pending_confirmation {
          Some(p) => p.tool_name == "delete_model"
          None => false
        }
        consume_confirmation(self.state.val)
        self.state.val.dialog = DialogState::NoDialog
        if is_delete {
          // Return to config menu when cancelling a delete (no queue write)
          open_config_menu(self.state.val, self.agent)
        } else {
          match self.confirmation_response {
            Some(q) => ignore(q.try_put(false))
            None => ()
          }
        }
        self.dirty = true
      }
      Tab if key.modifiers.shift() => {
        // Shift+Tab: approve all tools for this session
        self.state.val.approved_all_tools = true
        consume_confirmation(self.state.val)
        self.state.val.dialog = DialogState::NoDialog
        match self.confirmation_response {
          Some(q) => ignore(q.try_put(true))
          None => ()
        }
        ignore(
          self.output.append_text(
            "[system] All tools auto-approved for this session",
            OutputKind::Text,
          ),
        )
        self.dirty = true
      }
      Char('d') | Char('D') | Tab =>
        match self.state.val.dialog {
          Approval(d) => {
            d.toggle_details()
            self.dirty = true
          }
          _ => ()
        }
      Enter => {
        let is_delete = match self.state.val.pending_confirmation {
          Some(p) => p.tool_name == "delete_model"
          None => false
        }
        // Enter follows the displayed default ([Y/n] vs [y/N])
        let default_yes = confirmation_default_yes(self.state.val)
        consume_confirmation(self.state.val)
        self.state.val.dialog = DialogState::NoDialog
        if is_delete {
          open_config_menu(self.state.val, self.agent)
        } else {
          match self.confirmation_response {
            Some(q) => ignore(q.try_put(default_yes))
            None => ()
          }
        }
        self.dirty = true
      }
      _ => ()
    }
    return
  }
  // Config menu dialog: intercept all keys
  match self.state.val.dialog {
    ModelDrawer(level~, dialog~, card_id~, ..) => {
      match key.code {
        Char('j') | Down => {
          dialog.move_down()
          self.dirty = true
        }
        Char('k') | Up => {
          dialog.move_up()
          self.dirty = true
        }
        Right | Char('l') =>
          // → opens the sub-model drawer for expandable cards only.
          if level is Cards {
            match dialog.get_selected() {
              Some(item) => self.try_open_submodel_drawer(item.value)
              None => ()
            }
          }
        Enter =>
          match level {
            Cards =>
              match dialog.get_selected() {
                // Enter always selects the card with its default model
                // (clearing any overlay, Ruby ui_controller.rb:1641-1674);
                // only → opens the sub-model drawer.
                Some(item) => self.apply_model_card_switch(item.value, None)
                None => ()
              }
            SubModels =>
              match dialog.get_selected() {
                Some(item) => {
                  // "Default (<card model>)" has an empty value: clear the
                  // overlay; a named entry pins it as the session overlay.
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
        Left | Escape =>
          if level is SubModels {
            // ← / Esc in the drawer: back to the card list.
            open_model_selector(self.state.val, self.agent)
            self.dirty = true
          } else {
            close_config_dialog(self.state.val)
            self.dirty = true
          }
        _ => ()
      }
      return
    }
    TimeMachineMenu(dialog) => {
      match key.code {
        Char('j') | Down => {
          dialog.move_down()
          self.dirty = true
        }
        Char('k') | Up => {
          dialog.move_up()
          self.dirty = true
        }
        Enter => {
          self.perform_time_machine_switch(dialog)
          self.dirty = true
          self.redraw()
        }
        Escape => {
          close_config_dialog(self.state.val)
          self.dirty = true
        }
        _ => ()
      }
      return
    }
    ConfigMenu(dialog) => {
      match key.code {
        Char('j') | Down => {
          dialog.move_down()
          self.dirty = true
        }
        Char('k') | Up => {
          dialog.move_up()
          self.dirty = true
        }
        Enter =>
          // Check if selected item is an action item
          match dialog.get_selected() {
            Some(item) =>
              if item.value == ACTION_ADD {
                let mode : ConfigMode = ConfigMenu
                open_add_form(self.state.val, mode)
                self.dirty = true
              } else if item.value == ACTION_EDIT {
                let idx = dialog.selected_idx
                if idx >= 0 && idx < self.agent.config.models.length() {
                  let model = self.agent.config.models[idx]
                  let mode : ConfigMode = ConfigMenu
                  open_edit_form(self.state.val, mode, model, idx)
                  self.dirty = true
                }
              } else if item.value == ACTION_DELETE {
                let idx = dialog.selected_idx
                if idx >= 0 && idx < self.agent.config.models.length() {
                  let model = self.agent.config.models[idx]
                  request_confirmation(
                    self.state.val,
                    "delete_model",
                    model.model,
                    "Delete model '\{model.model}'? This cannot be undone.",
                  )
                  self.dirty = true
                }
              } else if item.value == ACTION_CLOSE {
                close_config_dialog(self.state.val)
                self.dirty = true
              } else {
                // Model entry: switch to selected model
                let result = self.agent.config.switch_model_by_id(item.value)
                match result {
                  Ok(_) => {
                    self.apply_model_switch()
                    self.save_config()
                    self.state.val.model_name = match
                      self.agent.config.current_model() {
                      Some(m) => m.model
                      None => self.state.val.model_name
                    }
                    ignore(
                      self.output.append_text(
                        "[system] Model switched to: \{item.label}",
                        OutputKind::Text,
                      ),
                    )
                    self.print_config_summary()
                  }
                  Err(msg) =>
                    ignore(
                      self.output.append_text(
                        "[error] \{msg}",
                        OutputKind::Text,
                      ),
                    )
                }
                close_config_dialog(self.state.val)
                self.dirty = true
              }
            None => ()
          }
        Char('a') => {
          let mode : ConfigMode = ConfigMenu
          open_add_form(self.state.val, mode)
          self.dirty = true
        }
        Char('e') => {
          let idx = dialog.selected_idx
          if idx >= 0 &&
            idx < self.agent.config.models.length() &&
            is_separator(dialog.items[idx]) == false {
            let model = self.agent.config.models[idx]
            let mode : ConfigMode = ConfigMenu
            open_edit_form(self.state.val, mode, model, idx)
            self.dirty = true
          }
        }
        Char('d') | Char('D') => {
          // Only delete when cursor is on a model entry
          let idx = dialog.selected_idx
          if idx >= 0 &&
            idx < self.agent.config.models.length() &&
            is_separator(dialog.items[idx]) == false {
            let model = self.agent.config.models[idx]
            request_confirmation(
              self.state.val,
              "delete_model",
              model.model,
              "Delete model '\{model.model}'? This cannot be undone.",
            )
            self.dirty = true
          }
        }
        Escape => {
          close_config_dialog(self.state.val)
          self.dirty = true
        }
        _ => ()
      }
      return
    }
    ConfigForm(mode~, form~, action~, target_idx~) => {
      // While a connection test is in flight the form is read-only.
      if self.pending_config_test is Some(_) {
        return
      }
      match key.code {
        Tab => {
          form.next_field()
          self.dirty = true
        }
        Enter => {
          // Merge values per the Ruby validator rules (Edit falls back to
          // existing values for empty fields; Add requires all fields),
          // then validate the credentials with a live connection test
          // before saving anything.
          let existing = match action {
            Edit =>
              if target_idx >= 0 &&
                target_idx < self.agent.config.models.length() {
                Some(self.agent.config.models[target_idx])
              } else {
                None
              }
            Add => None
          }
          match
            merge_config_form_values(action, form.collect_values(), existing) {
            Err(err) => {
              ignore(
                self.output.append_text("[error] \{err}", OutputKind::Text),
              )
              self.dirty = true
            }
            Ok(merged) => {
              let pending : PendingConfigTest = { ..merged, mode, target_idx }
              self.pending_config_test = Some(pending)
              ignore(
                self.output.append_text(
                  "[system] ⏳ Testing connection to \{pending.base_url}...",
                  OutputKind::Text,
                ),
              )
              self.events.put(StartConnectionTest(pending))
              self.dirty = true
            }
          }
        }
        Escape => {
          return_to_config_menu(self.state.val, self.agent, mode)
          self.dirty = true
        }
        Backspace => {
          form.backspace()
          self.dirty = true
        }
        Char(ch) if !key.modifiers.ctrl() && !key.modifiers.alt() => {
          form.input_char(ch)
          self.dirty = true
        }
        _ => ()
      }
      return
    }
    _ => ()
  }
  match key.code {
    Char('c') if key.modifiers.ctrl() =>
      match self.agent_task {
        Some(t) => {
          t.cancel()
          self.agent_task = None
          self.agent_running = false
          self.state.val.mode = TuiMode::Idle
          self.state.val.todo_area.hide()
          self.dirty = true
        }
        None => self.quit = true
      }
    Char('d') if key.modifiers.ctrl() && self.input.is_empty() =>
      self.quit = true
    Enter =>
      if self.suggestions_active {
        // Accept the highlighted suggestion.
        match self.suggestions.accept_item() {
          Some(item) => {
            let cmd = item.name
            self.input.set_text(cmd)
            self.close_suggestions()
            self.dirty = true
            // Show the command's usage hint as a system tip (Ruby ui2
            // input_area.rb:210); it auto-clears after 2 seconds.
            if item.usage.length() > 0 {
              self.tips.set(
                "Usage: \{item.name} \{item.usage}",
                TipsType::Info,
                self.state.val.tick_count,
              )
            }
            // A completed slash command is immediately executable — submit it
            // in the same keystroke to match the reference TUI's single-Enter
            // flow (BUG-003 / SPEC-03).
            if should_submit_accepted_suggestion(cmd) {
              self.handle_enter_key()
            }
          }
          None => {
            self.close_suggestions()
            self.dirty = true
          }
        }
      } else {
        self.handle_enter_key()
      }
    Char('j') if key.modifiers.ctrl() => {
      self.input.handle_enter()
      self.update_suggestions()
      self.dirty = true
    }
    Char('l') if key.modifiers.ctrl() => self.full_redraw()
    Char('y') if key.modifiers.ctrl() => {
      // Copy visible output to clipboard via OSC 52
      let msg_height = self.term_height - 5
      let lines = self.output.tail_lines(msg_height)
      let text = lines.join("\n")
      copy_to_clipboard(self.tty, text)
      self.dirty = true
    }
    Char('k') if key.modifiers.ctrl() => {
      self.input.kill_to_end()
      self.update_suggestions()
      self.dirty = true
    }
    Char('u') if key.modifiers.ctrl() => {
      self.input.kill_to_start()
      self.update_suggestions()
      self.dirty = true
    }
    Char('w') if key.modifiers.ctrl() => {
      self.input.kill_word()
      self.update_suggestions()
      self.dirty = true
    }
    Left => {
      self.input.cursor_left()
      self.dirty = true
    }
    Right => {
      self.input.cursor_right()
      self.dirty = true
    }
    Up => {
      match arrow_key_action(self.suggestions_active, self.input.line_count()) {
        NavigateSuggestions => self.suggestions.select_prev()
        BrowseHistory => self.input.prev_history()
        MoveCursor => self.input.cursor_up()
      }
      self.dirty = true
    }
    Down => {
      match arrow_key_action(self.suggestions_active, self.input.line_count()) {
        NavigateSuggestions => self.suggestions.select_next()
        BrowseHistory => self.input.next_history()
        MoveCursor => self.input.cursor_down()
      }
      self.dirty = true
    }
    Home => {
      self.input.cursor_home()
      self.dirty = true
    }
    End => {
      self.input.cursor_end()
      self.dirty = true
    }
    Backspace => {
      self.input.backspace()
      self.update_suggestions()
      self.dirty = true
    }
    Delete => {
      self.input.delete_forward()
      self.update_suggestions()
      self.dirty = true
    }
    Escape =>
      if self.suggestions_active {
        self.close_suggestions()
        self.dirty = true
        // ESC with no suggestions open: open the Time Machine menu
        // (Ruby ui2 input_area.rb:255-262).
      } else if open_time_machine_menu(self.state.val) {
        self.dirty = true
        self.redraw()
      }
    Tab if key.modifiers.shift() => {
      // Shift+Tab (non-dialog): cycle permission mode
      let cur = @config.PermissionMode::from_string(
        self.state.val.permission_mode,
      )
      let next = cycle_permission_mode(
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
          OutputKind::Text,
        ),
      )
      self.dirty = true
    }
    Tab =>
      if self.input.is_empty() {
        // Empty input: insert "/" and show all completions
        self.input.insert_char('/')
        self.suggestions.update_filter("/")
        self.suggestions_active = self.suggestions.is_visible()
        self.dirty = true
      } else if self.suggestions_active {
        // Suggestions open: Tab cycles to the next candidate
        // (Ruby ui2 command_suggestions: Tab/↓ move the highlight).
        self.suggestions.select_next()
        self.dirty = true
      }
    Char(ch) if !key.modifiers.ctrl() && !key.modifiers.alt() => {
      self.input.insert_char(ch)
      self.update_suggestions()
      self.dirty = true
    }
    _ => ()
  }
}

///|
/// Handle Enter key: submit input to agent if non-empty, else newline.
async fn TuiController::handle_enter_key(self : TuiController) -> Unit {
  if self.input.is_empty() {
    return
  }
  // While the agent awaits user feedback (request_user_feedback), Enter
  // delivers the typed answer to the blocked agent task instead of
  // starting a new run.
  if self.feedback_pending {
    let text = self.input.submit()
    self.close_suggestions()
    self.feedback_pending = false
    match self.feedback_response {
      Some(q) => ignore(q.try_put(text))
      None => ()
    }
    self.redraw()
    self.dirty = true
    return
  }
  if self.agent_running {
    // Don't submit while agent is running
    return
  }
  let text = self.input.submit()
  self.close_suggestions()
  // Expand any paste placeholders before submission
  let expanded_text = self.state.val.expand_paste_placeholders(text)
  self.state.val.clear_paste_placeholders()
  if expanded_text.length() > 0 {
    // Bare text exit/quit: exact match (trimmed) triggers quit
    let trimmed = expanded_text.trim().to_owned()
    if trimmed == "exit" || trimmed == "quit" {
      self.quit = true
      return
    }
    // "?" is an alias for /help (Ruby ui2 input_area.rb:824-827); it is
    // intercepted here at the dispatch layer, never reaching the parser.
    if trimmed == "?" {
      match execute(SlashCommand::Help, self.agent) {
        Ok(msg) => ignore(self.output.append_text(msg, OutputKind::Text))
        Err(err) =>
          ignore(self.output.append_text("[error] \{err}", OutputKind::Text))
      }
      self.redraw()
      self.dirty = true
      return
    }
    // Check for slash commands
    if expanded_text[0:1] == "/" {
      match parse_slash_command(expanded_text) {
        Ok(cmd) => {
          match cmd {
            Exit | Quit => {
              self.quit = true
              return
            }
            Config => {
              // No-arg /config: open config menu (with-arg form removed).
              if self.agent.config.models.length() == 0 {
                ignore(
                  self.output.append_text(
                    "[system] No models configured. Use /config to open the configuration menu.",
                    OutputKind::Text,
                  ),
                )
                self.redraw()
                self.dirty = true
                return
              }
              open_config_menu(self.state.val, self.agent)
              self.dirty = true
              self.redraw()
              return
            }
            Model(name~) if name == "" => {
              // No-arg /model: open the two-level drawer. The original only
              // blocks when NO model is configured (cli.rb:302-304) — a
              // single-card user can still open the sub-model drawer.
              if self.agent.config.models.length() == 0 {
                ignore(
                  self.output.append_text(
                    "[system] No models configured. Run /config to add one.",
                    OutputKind::Text,
                  ),
                )
                self.redraw()
                self.dirty = true
                return
              }
              open_model_selector(self.state.val, self.agent)
              self.dirty = true
              self.redraw()
              return
            }
            Model(_) => {
              // With-arg /model: same semantics as the menu selector —
              // match a configured card by id or model name, switch
              // (current + default badge), rebuild the client, persist.
              // execute() clears the session sub-model overlay (the card
              // changed), so the session file must be saved right away —
              // otherwise a restart would restore the stale overlay on top
              // of the new card (mismatched model name for the new base_url).
              let result = execute(cmd, self.agent)
              match result {
                Ok(msg) => {
                  self.save_config()
                  let session_data = self.agent.to_session_data()
                  @agent.save_session(session_data) catch {
                    _ => ()
                  }
                  self.state.val.model_name = self.agent.client.model
                  ignore(
                    self.output.append_text("[system] \{msg}", OutputKind::Text),
                  )
                }
                Err(err) =>
                  ignore(
                    self.output.append_text("[error] \{err}", OutputKind::Text),
                  )
              }
              self.redraw()
              self.dirty = true
              return
            }
            Clear => {
              // New-session semantics (Ruby cli.rb:998-1026): agent resets
              // in place (idle timer cancelled + rebound, new session_id,
              // client rebuilt from current config); TUI-side state resets
              // alongside; output area cleared with the fresh-start notice.
              ignore(execute(cmd, self.agent))
              reset_tui_session_state(self.state.val, self.agent)
              self.agent_output_sync.reset()
              self.output.clear()
              ignore(
                self.output.append_text(
                  "[system] Session cleared. Starting fresh.",
                  OutputKind::Text,
                ),
              )
              self.full_redraw()
              self.dirty = false
              return
            }
            Theme(name~) => {
              // Switch the active theme and rebuild dependent renderers
              self.apply_theme(name)
              ignore(
                self.output.append_text(
                  "[system] Theme switched to: \{name}",
                  OutputKind::Text,
                ),
              )
              self.full_redraw()
              self.dirty = false
              return
            }
            Undo => {
              // Open the interactive Time Machine menu (Ruby ui2
              // show_time_machine_menu); falls back to an info line when
              // there is no task history yet.
              if open_time_machine_menu(self.state.val) {
                self.dirty = true
                self.redraw()
              } else {
                ignore(
                  self.output.append_text(
                    "[system] No tasks in history to undo",
                    OutputKind::Text,
                  ),
                )
                self.redraw()
                self.dirty = true
              }
              return
            }
            _ => ()
          }
          // Execute other slash commands
          let result = execute(cmd, self.agent)
          match result {
            Ok(msg) => {
              ignore(
                self.output.append_text("[system] \{msg}", OutputKind::Text),
              )
              self.redraw()
              self.dirty = true
            }
            Err(err) => {
              ignore(
                self.output.append_text("[error] \{err}", OutputKind::Text),
              )
              self.redraw()
              self.dirty = true
            }
          }
          return
        }
        Err(_) =>
          // Not a static slash command — try the skill registry (Ruby
          // skills_by_command; priority: static command > skill > input).
          match self.agent.skill_registry.find_skill_command(expanded_text) {
            Some((skill, args)) => {
              // Inject the skill instructions, then run a normal task
              // asking the model to proceed with them.
              self.agent.inject_skill_command(skill, args)
              let arg_note = if args.length() > 0 {
                " with arguments: \{args}"
              } else {
                ""
              }
              self.begin_agent_run(
                expanded_text,
                "[SYSTEM] The user invoked the /\{skill.name} skill\{arg_note}. Follow the skill instructions in the previous message.",
              )
              return
            }
            // No skill either — send as regular input
            None => ()
          }
      }
    }
    // Add user message to output buffer
    self.begin_agent_run(expanded_text, expanded_text)
  }
}

///|
/// Shared submit tail: show the user message, open a time-machine task,
/// switch to Running, and queue the agent run (used by both regular input
/// and skill-command submissions).
async fn TuiController::begin_agent_run(
  self : TuiController,
  display : String,
  run_input : String,
) -> Unit {
  ignore(self.output.append_text("[user] \{display}", OutputKind::Text))
  // Time machine: open a new task so file writes in this run can be undone
  ignore(self.state.val.time_machine.start_new_task(Some(display)))
  // Run agent
  self.state.val.mode = TuiMode::Running
  // Auto-show the todo area while the agent works (Ruby ui2
  // set_working_status → show_todos); empty lists render nothing.
  self.state.val.todo_area.show()
  self.state.val.run_start_ts = @env.now().reinterpret_as_int64()
  self.state.val.total_iterations = 0
  self.agent_running = true
  self.hooks.reset_for_run()
  self.dirty = true
  // Draw the user message while still live, then commit it
  self.redraw()
  self.events.put(SubmitInput(run_input))
}

///|
/// Start agent run in a background task.
fn TuiController::start_agent(
  self : TuiController,
  group : @async.TaskGroup[Unit],
  text : String,
) -> Unit {
  let events = self.events
  let agent = self.agent
  let task = group.spawn(allow_failure=true) <| () => {
    let result = agent.run_async(text) catch {
      err => {
        let msg = @errors.error_message(err)
        events.put(AgentError(msg))
        raise @errors.AgentError(msg)
      }
    }
    events.put(AgentDone(result))
    result
  }
  self.agent_task = Some(task)
}

///|
/// Run the connection test for a pending config form submit in a
/// background task (throwaway client built from the merged, not-yet-saved
/// values — Ruby cli.rb:223-233).
fn TuiController::start_connection_test(
  self : TuiController,
  group : @async.TaskGroup[Unit],
  pending : PendingConfigTest,
) -> Unit {
  let events = self.events
  let api_type = if pending.anthropic_format {
    @config.AnthropicMessages
  } else {
    @config.Providers::api_type_for_model(pending.base_url, pending.model)
  }
  let test_client = @client.Client::new(
    pending.api_key,
    pending.base_url,
    pending.model,
    api_type,
  )
  group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
    let result = test_client.test_connection()
    events.put(
      ConnectionTestDone(
        result.success,
        match result.error {
          Some(e) => e
          None => ""
        },
      ),
    )
  }
}

///|
/// Apply the result of a config form connection test: on success apply the
/// pending add/edit, persist, and print the configuration summary; on
/// failure show the error and keep the form open (Ruby ui_controller.rb
/// validator interaction).
async fn TuiController::finish_connection_test(
  self : TuiController,
  success : Bool,
  message : String,
) -> Unit {
  let pending = match self.pending_config_test {
    Some(p) => p
    None => return
  }
  self.pending_config_test = None
  if !success {
    // Stay in the form; the user can fix the values and retry.
    ignore(
      self.output.append_text(
        "[error] ⚠ Connection test failed: \{message}",
        OutputKind::Text,
      ),
    )
    self.dirty = true
    self.redraw()
    return
  }
  match pending.action {
    Add => {
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
          OutputKind::Text,
        ),
      )
    }
    Edit =>
      if pending.target_idx >= 0 &&
        pending.target_idx < self.agent.config.models.length() {
        let existing = self.agent.config.models[pending.target_idx]
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
        self.agent.config.models[pending.target_idx] = updated
        // Hot-swap when the edited model is the active one
        match self.agent.config.current_model_id {
          Some(id) if id == updated.id => {
            self.apply_model_switch()
            self.state.val.model_name = updated.model
          }
          _ => ()
        }
        ignore(
          self.output.append_text(
            "[system] Model '\{updated.id}' updated",
            OutputKind::Text,
          ),
        )
      }
  }
  self.save_config()
  self.print_config_summary()
  return_to_config_menu(self.state.val, self.agent, pending.mode)
  self.dirty = true
  self.redraw()
}

///|
/// Print the 4-line configuration summary after a successful config
/// change (Ruby cli.rb:280-292): current model, masked API key, base URL,
/// protocol format.
fn TuiController::print_config_summary(self : TuiController) -> Unit {
  match self.agent.config.current_model() {
    Some(m) => {
      let format = if m.anthropic_format { "Anthropic" } else { "OpenAI" }
      ignore(
        self.output.append_text(
          "[system] Configuration updated!\n  Current Model: \{m.model}\n  API Key: \{mask_api_key_summary(m.api_key)}\n  Base URL: \{m.base_url}\n  Format: \{format}",
          OutputKind::Text,
        ),
      )
    }
    None => ()
  }
}

///|
/// Open the sub-model drawer for a card (no-op when it has fewer than 2
/// provider sub-models — same threshold as the "›" marker).
fn TuiController::try_open_submodel_drawer(
  self : TuiController,
  card_id : String,
) -> Unit {
  for m in self.agent.config.models {
    if m.id == card_id {
      if provider_submodels(m).length() >= 2 {
        open_submodel_drawer(self.state.val, self.agent, m)
        self.dirty = true
      }
      return
    }
  }
}

///|
/// Switch to a model card and optionally pin a session sub-model overlay
/// (Ruby cli.rb handle_model_command): switch + persist as the global
/// default, then write/clear the overlay and save the session immediately
/// so it survives a quit before the next task.
fn TuiController::apply_model_card_switch(
  self : TuiController,
  card_id : String,
  sub_model : String?,
) -> Unit {
  match self.agent.config.switch_model_by_id(card_id) {
    Ok(_) => {
      self.apply_model_switch()
      self.save_config()
      self.agent.set_session_sub_model(sub_model)
      let session_data = self.agent.to_session_data()
      @agent.save_session(session_data) catch {
        _ => ()
      }
      self.state.val.model_name = self.agent.client.model
      let sub_note = match sub_model {
        Some(s) => " (sub-model: \{s})"
        None => ""
      }
      ignore(
        self.output.append_text(
          "[system] Model switched to: \{self.agent.client.model}\{sub_note}",
          OutputKind::Text,
        ),
      )
      // No 4-line summary here: /model prints a single line (cli.rb:340);
      // the summary belongs to /config changes only (C4).
      close_config_dialog(self.state.val)
      self.dirty = true
    }
    Err(msg) =>
      ignore(self.output.append_text("[error] \{msg}", OutputKind::Text))
  }
}

///|
/// Switch the active theme by name and rebuild dependent renderers.
///
/// Falls back to the default theme for unrecognized names (the slash
/// command parser already validates, so this is defensive only).
fn TuiController::apply_theme(self : TuiController, name : String) -> Unit {
  let theme_name : ThemeName = match name {
    "hacker" => Hacker
    "minimal" => Minimal
    "light" => Light
    _ => Default
  }
  self.theme = Theme::from_name(theme_name)
  self.agent_output_sync.set_theme(self.theme)
}

///|
/// Apply a model switch to the agent's client (hot-swap).
fn TuiController::apply_model_switch(self : TuiController) -> Unit {
  self.agent.rebuild_client_from_config()
}

///|
/// Persist the agent config to disk.
fn TuiController::save_config(self : TuiController) -> Unit {
  match @utils.config_file() {
    Some(path) =>
      self.agent.config.save(path) catch {
        _ =>
          ignore(
            self.output.append_text(
              "[warning] Failed to save configuration",
              OutputKind::Text,
            ),
          )
      }
    None =>
      ignore(
        self.output.append_text(
          "[warning] No config file path available",
          OutputKind::Text,
        ),
      )
  }
}

///|
/// Execute the Time Machine switch selected in the menu (Ruby cli.rb
/// handle_time_machine_command): target before the current task is an
/// undo, after it a redo; the workspace is restored from the computed
/// snapshot entries and the session is saved afterwards.
fn TuiController::perform_time_machine_switch(
  self : TuiController,
  dialog : ConfigMenuDialog,
) -> Unit {
  match dialog.get_selected() {
    Some(item) => {
      let target_num = @agent.task_num_of(item.value)
      let cur_num = match self.state.val.time_machine.current_task_id {
        Some(id) => @agent.task_num_of(id)
        None => 0
      }
      let direction = if target_num < cur_num { "Undoing" } else { "Redoing" }
      ignore(
        self.output.append_text(
          "[system] \{direction} to Task \{target_num}...",
          OutputKind::Text,
        ),
      )
      match self.state.val.time_machine.switch_to_task(item.value) {
        Ok(entries) => {
          match @agent.apply_snapshot_entries(entries) {
            Ok(n) =>
              ignore(
                self.output.append_text(
                  "[system] ✓ Switched to \{item.value}: restored \{n} file(s)",
                  OutputKind::Text,
                ),
              )
            Err(msg) =>
              ignore(
                self.output.append_text("[error] \{msg}", OutputKind::Text),
              )
          }
          // Save the session after the switch (Ruby: session_manager.save)
          let session_data = self.agent.to_session_data()
          @agent.save_session(session_data) catch {
            _ => ()
          }
        }
        Err(msg) =>
          ignore(self.output.append_text("[error] \{msg}", OutputKind::Text))
      }
    }
    None => ()
  }
  close_config_dialog(self.state.val)
}

///|
/// Perform model deletion after confirmation.
fn TuiController::perform_model_delete(self : TuiController, idx : Int) -> Unit {
  if idx >= 0 && idx < self.agent.config.models.length() {
    let removed = self.agent.config.models[idx]
    ignore(self.agent.config.models.remove(idx))
    // If we deleted the current model, switch to first available
    match self.agent.config.current_model_id {
      Some(id) if id == removed.id =>
        if self.agent.config.models.length() > 0 {
          self.agent.config.current_model_id = Some(
            self.agent.config.models[0].id,
          )
          self.apply_model_switch()
          // Keep the status bar model name in sync (same as Enter switch)
          self.state.val.model_name = self.agent.config.models[0].model
        } else {
          self.agent.config.current_model_id = None
          ignore(
            self.output.append_text(
              "[warning] No models configured after delete",
              OutputKind::Text,
            ),
          )
        }
      _ => ()
    }
    self.save_config()
    ignore(
      self.output.append_text(
        "[system] Model '\{removed.model}' deleted",
        OutputKind::Text,
      ),
    )
    self.print_config_summary()
    // Reopen config menu
    open_config_menu(self.state.val, self.agent)
  }
}

///|
/// Called after the main loop exits. If the session had any content,
/// persist it to disk (same path as the non-interactive mode in
/// cmd/main.mbt) and tell the user how to re-attach.
async fn TuiController::on_exit_save(self : TuiController) -> Unit {
  // Only save when the session had meaningful content
  if self.state.val.messages.length() > 0 || self.agent.history.size() > 0 {
    let session_data = self.agent.to_session_data()
    @agent.save_session(session_data) catch {
      _ => ()
    }
    ignore(
      self.output.append_text(
        "[system] Session saved to disk: clacky --attach \{self.state.val.session_id}",
        OutputKind::Text,
      ),
    )
    // Final redraw so the message is visible
    self.redraw()
  }
}
