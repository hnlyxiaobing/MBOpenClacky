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
  screen : ScreenBuffer
  output : OutputBuffer
  layout : LayoutManager
  status_bar : StatusBar
  input : InputArea
  state : Ref[TuiState]
  agent : @agent.Agent
  hooks : AgentHookHandler
  mut quit : Bool
  mut dirty : Bool
  mut agent_running : Bool
  mut last_output_version : Int
  events : @aqueue.Queue[TuiEvent]
  mut confirmation_response : @aqueue.Queue[Bool]?
  mut agent_task : @async.Task[@agent.RunResult]?
  thinking_animator : ThinkingVerbAnimator
  mut last_thinking_len : Int
  file_browser : FileBrowser
  agent_output_sync : AgentOutputSync
  mut theme : Theme
  suggestions : CommandSuggestions
  mut suggestions_active : Bool
  /// Terminal rows currently occupied by the suggestion dropdown.
  mut suggestions_rows_drawn : Array[Int]
  /// Terminal rows currently occupied by progress indicator lines.
  mut progress_rows_drawn : Array[Int]
}

///|
/// Create a new TuiController from a Tty handle and Agent.
pub fn TuiController::new(
  tty : @tty.Tty,
  agent : @agent.Agent,
) -> TuiController {
  let screen = ScreenBuffer::new(tty)
  let output = OutputBuffer::new()
  let layout = LayoutManager::new(screen, output, status_h=1, input_h=4)
  let state = Ref(TuiState::from_agent(agent))
  let hooks = AgentHookHandler::new(state, agent=Some(agent))
  hooks.set_output(output)
  {
    tty,
    screen,
    output,
    layout,
    status_bar: StatusBar::new(),
    input: InputArea::multiline_new(),
    state,
    agent,
    hooks,
    quit: false,
    dirty: true,
    agent_running: false,
    last_output_version: -1,
    events: @aqueue.Queue::Queue(kind=Unbounded),
    confirmation_response: None,
    agent_task: None,
    thinking_animator: ThinkingVerbAnimator::new(),
    last_thinking_len: 0,
    file_browser: FileBrowser::new(state.val.working_dir),
    agent_output_sync: AgentOutputSync::new(),
    theme: Theme::default_(),
    suggestions: build_command_suggestions(),
    suggestions_active: false,
    suggestions_rows_drawn: [],
    progress_rows_drawn: [],
  }
}

// ── Command suggestions / progress helpers ───────────────────────

///|
/// What the Up/Down arrow keys do, given the current UI state.
enum ArrowKeyAction {
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
fn band_rows(
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
/// Full screen redraw: status bar, output area, input area.
pub async fn TuiController::full_redraw(self : TuiController) -> Unit {
  self.layout.compute_layout()
  // The display is fully cleared below — forget overlay row tracking.
  self.suggestions_rows_drawn = []
  self.progress_rows_drawn = []
  if self.state.val.shell_mode is ShellMode::FileBrowser {
    self.screen.clear_display()
    self.redraw_status()
    self.redraw_file_browser()
    self.redraw_input()
    self.place_cursor()
    return
  }
  // Build status text from state
  self.status_bar.format_from_state(self.state.val)
  let status_text = self.status_bar.colored_text()
  // Get input render lines
  let input_lines = self.input.render_lines()
  // Render
  self.layout.full_redraw(status_text, input_lines)
  // Re-draw the input box with the active theme color (the layout
  // renderer uses a hardcoded border color).
  self.redraw_input()
  // Re-draw the overlay bands cleared by the full redraw
  self.redraw_progress()
  self.redraw_suggestions()
  // Place cursor
  self.place_cursor()
}

///|
/// Incremental redraw: only update what changed.
pub async fn TuiController::redraw(self : TuiController) -> Unit {
  if self.state.val.shell_mode is ShellMode::FileBrowser {
    self.redraw_status()
    self.redraw_file_browser()
    self.redraw_input()
    self.place_cursor()
    return
  }
  // Check if output buffer changed
  let ov = self.output.version
  if ov != self.last_output_version {
    self.last_output_version = ov
    self.redraw_output()
    self.redraw_status()
  }
  // The input box is cheap — always redraw it, then the overlay bands
  // (progress indicators animate on every Tick; the suggestion dropdown
  // tracks input content).
  self.redraw_input()
  self.redraw_progress()
  self.redraw_suggestions()
  self.place_cursor()
}

///|
/// Redraw just the status bar with per-segment ANSI colors.
async fn TuiController::redraw_status(self : TuiController) -> Unit {
  self.status_bar.format_from_state(self.state.val)
  let colored = self.status_bar.colored_text()
  self.screen.move_cursor(1, 1)
  self.screen.clear_to_eol()
  self.screen.write_string(colored)
  self.screen.reset_style()
}

///|
/// Redraw the output/message area.
async fn TuiController::redraw_output(self : TuiController) -> Unit {
  self.layout.redraw_live()
  // Render todo area below output if visible
  self.redraw_todo()
  // Render active dialog if present
  self.redraw_dialog()
}

///|
/// Render the active dialog (if any) using the Node system.
async fn TuiController::redraw_dialog(self : TuiController) -> Unit {
  match self.state.val.dialog {
    NoDialog => ()
    Approval(dialog) => {
      let (w, h) = self.layout.screen_size()
      let input_h = 4
      let node = render_approval_dialog(dialog)
      let _ = render_node(self.screen, node, h - input_h - 8, 2, w - 4)
    }
    ConfigMenu(dialog) => {
      let (w, h) = self.layout.screen_size()
      let input_h = 4
      let node = render_config_menu(dialog)
      let _ = render_node(self.screen, node, h - input_h - 12, 4, w - 8)
    }
    Form(dialog) => {
      let (w, h) = self.layout.screen_size()
      let input_h = 4
      let node = render_form_dialog(dialog)
      let _ = render_node(self.screen, node, h - input_h - 12, 4, w - 8)
    }
    ConfigForm(form~, ..) => {
      let (w, h) = self.layout.screen_size()
      let input_h = 4
      let node = render_form_dialog(form)
      let _ = render_node(self.screen, node, h - input_h - 12, 4, w - 8)
    }
  }
  self.redraw_thinking_view()
}

///|
/// Render the thinking live view above the input area.
async fn TuiController::redraw_thinking_view(self : TuiController) -> Unit {
  let node = render_thinking_live_view(self.state.val, self.thinking_animator)
  if node is Node::Empty {
    return
  }
  let (w, h) = self.layout.screen_size()
  let input_h = 4
  let _ = render_node(self.screen, node, h - input_h - 10, 2, w - 4)
}

///|
/// Render the file browser panel when in FileBrowser mode.
async fn TuiController::redraw_file_browser(self : TuiController) -> Unit {
  let (w, h) = self.layout.screen_size()
  let node = render_file_browser(self.file_browser)
  let input_h = 4
  let available_h = h - input_h - 2
  for i = 0; i < available_h; i = i + 1 {
    self.screen.move_cursor(2 + i, 1)
    self.screen.clear_to_eol()
  }
  let _ = render_node(self.screen, node, 2, 1, w - 2)
}

///|
/// Redraw the todo area above the input box.
///
/// Renders the todo_area lines between the output area and the input box.
/// Only renders when todo_area is visible.
async fn TuiController::redraw_todo(self : TuiController) -> Unit {
  let todo_lines = self.state.val.todo_area.render_lines()
  if todo_lines.length() == 0 {
    return
  }
  let (_, h) = self.layout.screen_size()
  let input_h = 4
  // Render todo lines just above the input area
  let todo_bottom = h - input_h
  for i = 0; i < todo_lines.length(); i = i + 1 {
    let row = todo_bottom - todo_lines.length() + i
    if row > 1 {
      self.screen.move_cursor(row, 1)
      self.screen.clear_to_eol()
      self.screen.set_foreground(@color.Color::Basic(@color.BasicColor::Cyan))
      self.screen.write_string(todo_lines[i])
      self.screen.reset_style()
    }
  }
}

///|
/// Redraw the progress indicator band above the todo area.
///
/// Progress lines are written to fixed rows (directly above the todo block)
/// via ScreenBuffer and never scroll with the OutputBuffer. Previously
/// drawn rows are erased first, so the band disappears once the agent
/// closes its progress entries.
async fn TuiController::redraw_progress(self : TuiController) -> Unit {
  let (_, h) = self.layout.screen_size()
  let input_h = 4
  // Erase previously drawn progress lines
  for row in self.progress_rows_drawn {
    if row > 1 {
      self.screen.move_cursor(row, 1)
      self.screen.clear_to_eol()
    }
  }
  let progress_lines = self.state.val.progress_stack.render()
  let todo_len = self.state.val.todo_area.render_lines().length()
  let rows = band_rows(h, input_h, 1 + todo_len, progress_lines.length())
  for i = 0; i < progress_lines.length(); i = i + 1 {
    let row = rows[i]
    if row > 1 {
      self.screen.move_cursor(row, 1)
      self.screen.clear_to_eol()
      self.screen.set_foreground(@color.Color::Basic(@color.BasicColor::Yellow))
      self.screen.write_string(progress_lines[i])
      self.screen.reset_style()
    }
  }
  self.progress_rows_drawn = rows
}

///|
/// Redraw the command suggestion dropdown above the input box.
///
/// The dropdown overlays the bottom of the output area. When it closes,
/// its rows are erased and the todo/progress bands underneath are
/// restored.
async fn TuiController::redraw_suggestions(self : TuiController) -> Unit {
  let (_, h) = self.layout.screen_size()
  let input_h = 4
  // Erase the previously drawn dropdown and restore what was underneath
  if self.suggestions_rows_drawn.length() > 0 {
    for row in self.suggestions_rows_drawn {
      if row > 1 {
        self.screen.move_cursor(row, 1)
        self.screen.clear_to_eol()
      }
    }
    self.suggestions_rows_drawn = []
    self.redraw_todo()
    self.redraw_progress()
  }
  if !self.suggestions_active {
    return
  }
  let lines = self.suggestions.render()
  let rows = band_rows(h, input_h, 0, lines.length())
  for i = 0; i < lines.length(); i = i + 1 {
    let row = rows[i]
    if row > 1 {
      self.screen.move_cursor(row, 1)
      self.screen.clear_to_eol()
      self.screen.write_string(lines[i])
    }
  }
  self.suggestions_rows_drawn = rows
}

///|
/// Refresh the suggestion dropdown filter from the current input content.
///
/// Shows the dropdown when the single-line input starts with "/", hides it
/// otherwise (including when the filter yields no matches).
fn TuiController::update_suggestions(self : TuiController) -> Unit {
  let text = self.input.text()
  if should_show_suggestions(text, self.input.line_count()) {
    self.suggestions.update_filter(text)
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
/// Redraw the input area.
///
/// The border uses the active theme's primary color (an ANSI escape
/// string written directly) instead of a hardcoded color.
async fn TuiController::redraw_input(self : TuiController) -> Unit {
  let input_lines = self.input.render_lines()
  let (w, h) = self.layout.screen_size()
  let input_h = 4
  let top = h - input_h
  let border_color = self.theme.primary_color
  for i = 0; i < input_h; i = i + 1 {
    self.screen.move_cursor(top + i + 1, 1)
    self.screen.clear_to_eol()
    if i == 0 {
      self.screen.write_string(border_color)
      self.screen.write_string("┌─ Input ")
      let border_w = w - 10
      for j = 0; j < border_w; j = j + 1 {
        self.screen.write_string("─")
      }
      self.screen.reset_style()
    } else if i == input_h - 1 {
      self.screen.write_string(border_color)
      self.screen.write_string("└")
      let border_w = w - 2
      for j = 0; j < border_w; j = j + 1 {
        self.screen.write_string("─")
      }
      self.screen.write_string("┘")
      self.screen.reset_style()
    } else if i - 1 < input_lines.length() {
      self.screen.write_string(border_color)
      self.screen.write_string("│ ")
      self.screen.reset_style()
      self.screen.write_string(input_lines[i - 1])
    } else {
      self.screen.write_string(border_color)
      self.screen.write_string("│")
      self.screen.reset_style()
    }
  }
}

///|
/// Place the terminal cursor at the input editor position.
async fn TuiController::place_cursor(self : TuiController) -> Unit {
  let (_, h) = self.layout.screen_size()
  let input_h = 4
  let top = h - input_h
  let (cursor_line, cursor_col) = self.input.cursor_display_pos()
  let row = top + 1 + cursor_line
  let col = 3 + cursor_col // +3 for "│ " prefix
  self.screen.move_cursor(row, col)
  self.screen.show_cursor()
}

///|
/// Restore terminal to normal state on exit.
async fn TuiController::restore_terminal(self : TuiController) -> Unit {
  self.screen.reset_style()
  self.screen.show_cursor()
  self.screen.move_cursor(self.layout.height, 1)
  self.screen.write_string("\r\n")
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
  self.hooks.register_all(self.agent.hook_manager)
  // Wrap output lines at the real terminal width and show the startup
  // banner as the first output entry (it scrolls away naturally).
  self.output.width = self.layout.width
  let banner_width = Banner::adaptive_width(self.layout.width)
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
    terminal_width=self.layout.width,
  )
  ignore(self.output.append_text(startup_banner, OutputKind::Text))
  self.tty.with_raw_mode(() => self.async_event_loop(req_q, resp_q))
}

///|
/// Async event loop using task groups and Queue event dispatch.
async fn TuiController::async_event_loop(
  self : TuiController,
  req_q : @aqueue.Queue[(String, String)],
  _resp_q : @aqueue.Queue[Bool],
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
  self : TuiController,
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
  self : TuiController,
  req_q : @aqueue.Queue[(String, String)],
  events : @aqueue.Queue[TuiEvent],
) -> Unit {
  while true {
    let (tool, args) = req_q.get()
    events.put(ConfirmationRequest(tool, args))
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
            self.layout.compute_layout()
            self.output.width = self.layout.width
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
      AgentDone(result) => {
        self.agent_running = false
        self.agent_task = None
        self.state.val.mode = TuiMode::Idle
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
        self.layout.commit_all()
        self.dirty = true
      }
      AgentError(msg) => {
        self.agent_running = false
        self.agent_task = None
        self.state.val.mode = TuiMode::Idle
        ignore(
          self.agent_output_sync.sync_messages(
            self.state.val.messages,
            self.output,
          ),
        )
        ignore(self.output.append_text("[error] \{msg}", OutputKind::Text))
        self.redraw()
        self.layout.commit_all()
        self.dirty = true
      }
      SubmitInput(text) => self.start_agent(group, text)
      Tick => {
        // Increment tick counter for spinner animation
        self.state.val.tick_count = self.state.val.tick_count + 1
        // Poll the streaming buffer — hooks update it via Ref, bypassing
        // the event queue, so the Tick timer drives live reply rendering.
        if self.agent_output_sync.sync_streaming(
            self.state.val.streaming_buffer,
            self.state.val.messages,
            self.output,
          ) {
          self.dirty = true
        }
        if self.agent_running ||
          self.state.val.streaming_active ||
          self.state.val.progress_stack.has_open() {
          // Keep redrawing while the agent runs so the progress band's
          // spinner animates on every Tick.
          self.dirty = true
        }
        if self.state.val.thinking_buffer.length() != self.last_thinking_len {
          self.last_thinking_len = self.state.val.thinking_buffer.length()
          truncate_thinking_buffer(self.state.val)
          self.dirty = true
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
  // File browser mode: intercept navigation keys
  if self.state.val.shell_mode is FileBrowser {
    match key.code {
      Char('c') if key.modifiers.ctrl() =>
        match self.agent_task {
          Some(t) => {
            t.cancel()
            self.agent_task = None
            self.agent_running = false
            self.state.val.mode = TuiMode::Idle
            self.dirty = true
          }
          None => self.quit = true
        }
      Up => {
        self.file_browser.move_up()
        self.dirty = true
      }
      Down => {
        self.file_browser.move_down()
        self.dirty = true
      }
      Enter => {
        self.file_browser.enter_selected()
        self.dirty = true
      }
      Backspace => {
        self.file_browser.go_parent()
        self.dirty = true
      }
      Escape => {
        self.state.val.shell_mode = ShellMode::Chat
        self.full_redraw()
      }
      Tab => {
        let new_mode = cycle_shell_mode(self.state.val.shell_mode)
        self.state.val.shell_mode = new_mode
        if new_mode is ShellMode::FileBrowser {
          self.file_browser.current_path = self.state.val.working_dir
          self.file_browser.load_dir()
        }
        self.full_redraw()
      }
      _ => ()
    }
    return
  }
  // Config menu dialog: intercept all keys
  match self.state.val.dialog {
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
          // Switch to selected model
          match dialog.get_selected() {
            Some(item) => {
              let result = self.agent.config.switch_model_by_id(item.value)
              match result {
                Ok(_) => {
                  // Hot-swap the client
                  self.apply_model_switch()
                  // Persist
                  self.save_config()
                  // Update state model name
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
                }
                Err(msg) =>
                  ignore(
                    self.output.append_text("[error] \{msg}", OutputKind::Text),
                  )
              }
              close_config_dialog(self.state.val)
              self.dirty = true
            }
            None => ()
          }
        Char('a') => {
          let mode : ConfigMode = if dialog.title == "Select Model" {
            ModelSelector
          } else {
            ConfigMenu
          }
          open_add_form(self.state.val, mode)
          self.dirty = true
        }
        Char('e') => {
          let idx = dialog.selected_idx
          if idx >= 0 && idx < self.agent.config.models.length() {
            let model = self.agent.config.models[idx]
            let mode : ConfigMode = if dialog.title == "Select Model" {
              ModelSelector
            } else {
              ConfigMenu
            }
            open_edit_form(self.state.val, mode, model, idx)
            self.dirty = true
          }
        }
        Char('d') => {
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
      match key.code {
        Tab => {
          form.next_field()
          self.dirty = true
        }
        Enter =>
          match form.validate() {
            Some(err) => {
              ignore(
                self.output.append_text("[error] \{err}", OutputKind::Text),
              )
              self.dirty = true
            }
            None => {
              let values = form.collect_values()
              match action {
                Add => {
                  let name = values[0].1
                  let model_name = values[1].1
                  let api_key = values[2].1
                  let base_url = values[3].1
                  let new_model = @config.ModelConfig::new(
                    name, api_key, base_url, model_name,
                  )
                  self.agent.config.add_model(new_model)
                  ignore(
                    self.output.append_text(
                      "[system] Model '\{name}' added",
                      OutputKind::Text,
                    ),
                  )
                }
                Edit =>
                  // The edit form has no "name" field (id is immutable);
                  // values are [model, api_key, base_url].
                  if target_idx >= 0 &&
                    target_idx < self.agent.config.models.length() {
                    let existing = self.agent.config.models[target_idx]
                    let updated : @config.ModelConfig = {
                      id: existing.id,
                      type_: existing.type_,
                      api_key: values[1].1,
                      base_url: values[2].1,
                      model: values[0].1,
                      anthropic_format: existing.anthropic_format,
                      runtime_id: existing.runtime_id,
                      media_type: existing.media_type,
                    }
                    self.agent.config.models[target_idx] = updated
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
              return_to_config_menu(self.state.val, self.agent, mode)
              self.dirty = true
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
          self.dirty = true
        }
        None => self.quit = true
      }
    Char('d') if key.modifiers.ctrl() && self.input.is_empty() =>
      self.quit = true
    Enter =>
      if self.suggestions_active {
        // Accept the highlighted suggestion — complete the input, don't submit
        match self.suggestions.accept() {
          Some(cmd) => self.input.set_text(cmd)
          None => ()
        }
        self.close_suggestions()
        self.dirty = true
      } else {
        self.handle_enter_key()
      }
    Char('j') if key.modifiers.ctrl() => {
      self.input.handle_enter()
      self.update_suggestions()
      self.dirty = true
    }
    Char('l') if key.modifiers.ctrl() => self.full_redraw()
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
      } else {
        let new_mode = cycle_shell_mode(self.state.val.shell_mode)
        self.state.val.shell_mode = new_mode
        if new_mode is ShellMode::FileBrowser {
          self.file_browser.current_path = self.state.val.working_dir
          self.file_browser.load_dir()
        }
        self.full_redraw()
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
    // Check for slash commands
    if expanded_text[0:1] == "/" {
      match parse_slash_command(expanded_text) {
        Ok(cmd) => {
          match cmd {
            Exit | Quit => {
              self.quit = true
              return
            }
            Config(key~, value~) if key == "" => {
              // No-arg /config: open config menu
              if self.agent.config.models.length() == 0 {
                ignore(
                  self.output.append_text(
                    "[system] No models configured. Use /config <key> <value> to set options.",
                    OutputKind::Text,
                  ),
                )
                self.redraw()
                self.layout.commit_all()
                self.dirty = true
                return
              }
              open_config_menu(self.state.val, self.agent)
              self.dirty = true
              self.redraw()
              return
            }
            Model(name~) if name == "" => {
              // No-arg /model: open model selector
              if self.agent.config.models.length() <= 1 {
                ignore(
                  self.output.append_text(
                    "[system] Only one model configured. Use /model <name> to switch.",
                    OutputKind::Text,
                  ),
                )
                self.redraw()
                self.layout.commit_all()
                self.dirty = true
                return
              }
              open_model_selector(self.state.val, self.agent)
              self.dirty = true
              self.redraw()
              return
            }
            Clear => {
              // Clear agent history + output buffer + reset cost, then redraw
              ignore(execute(cmd, self.agent))
              self.state.val.total_cost = 0.0
              self.output.clear()
              ignore(
                self.output.append_text(
                  "[system] Session cleared",
                  OutputKind::Text,
                ),
              )
              self.full_redraw()
              self.layout.commit_all()
              self.dirty = false
              return
            }
            Todo => {
              // Toggle todo area visibility
              if self.state.val.todo_area.hidden {
                self.state.val.todo_area.show()
              } else {
                self.state.val.todo_area.hide()
              }
              self.dirty = true
              self.redraw()
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
              self.layout.commit_all()
              self.dirty = false
              return
            }
            Undo => {
              // Show task history from the time machine
              let tasks = self.state.val.time_machine.get_task_history()
              if tasks.length() == 0 {
                ignore(
                  self.output.append_text(
                    "[system] No tasks in history to undo",
                    OutputKind::Text,
                  ),
                )
              } else {
                let lines : Array[String] = [
                  "[system] Task history (time machine):",
                ]
                for t in tasks {
                  let desc = match t.description {
                    Some(d) => d
                    None => "(no description)"
                  }
                  let active = match
                    self.state.val.time_machine.current_task_id {
                    Some(id) if id == t.task_id => " \u{25c0} current"
                    _ => ""
                  }
                  lines.push("  \{t.task_id}: \{desc}\{active}")
                }
                // Perform undo of the last task
                match self.state.val.time_machine.undo_last_task() {
                  Ok(entries) =>
                    lines.push(
                      "[system] Undo complete: restored \{entries.length()} file(s)",
                    )
                  Err(msg) => lines.push("[system] Undo failed: \{msg}")
                }
                ignore(
                  self.output.append_text(lines.join("\n"), OutputKind::Text),
                )
              }
              self.redraw()
              self.layout.commit_all()
              self.dirty = true
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
              self.layout.commit_all()
              self.dirty = true
            }
            Err(err) => {
              ignore(
                self.output.append_text("[error] \{err}", OutputKind::Text),
              )
              self.redraw()
              self.layout.commit_all()
              self.dirty = true
            }
          }
          return
        }
        Err(_) =>
          // Not a valid slash command — send as regular input
          ()
      }
    }
    // Add user message to output buffer
    ignore(self.output.append_text("[user] \{expanded_text}", OutputKind::Text))
    // Time machine: open a new task so file writes in this run can be undone
    ignore(self.state.val.time_machine.start_new_task(Some(expanded_text)))
    // Run agent
    self.state.val.mode = TuiMode::Running
    self.state.val.run_start_ts = @env.now().reinterpret_as_int64()
    self.state.val.total_iterations = 0
    self.agent_running = true
    self.hooks.reset_for_run()
    self.dirty = true
    // Draw the user message while still live, then commit it
    self.redraw()
    self.layout.commit_all()
    self.events.put(SubmitInput(expanded_text))
  }
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
        events.put(AgentError(@errors.error_message(err)))
        raise err
      }
    }
    events.put(AgentDone(result))
    result
  }
  self.agent_task = Some(task)
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
  match self.agent.config.current_model() {
    Some(m) => {
      let old_client = self.agent.client
      let new_client = @client.Client::new(
        m.api_key,
        m.base_url,
        m.model,
        old_client.api_type,
        provider_id=old_client.provider_id,
        vision_supported=old_client.vision_supported,
      )
      self.agent.client = new_client
    }
    None => ()
  }
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
  if self.state.val.messages.length() > 0 || self.agent.history.length() > 0 {
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
