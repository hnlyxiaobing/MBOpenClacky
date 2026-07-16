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
  }
}

// ── Rendering ─────────────────────────────────────────────────────

///|
/// Full screen redraw: status bar, output area, input area.
pub async fn TuiController::full_redraw(self : TuiController) -> Unit {
  self.layout.compute_layout()
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
  let status_text = self.status_bar.plain_text()
  // Get input render lines
  let input_lines = self.input.render_lines()
  // Render
  self.layout.full_redraw(status_text, input_lines)
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
    self.redraw_input()
    self.place_cursor()
    return
  }
  // Check if input changed (always redraw input — cheap)
  self.redraw_input()
  self.place_cursor()
}

///|
/// Redraw just the status bar.
async fn TuiController::redraw_status(self : TuiController) -> Unit {
  self.status_bar.format_from_state(self.state.val)
  let text = self.status_bar.plain_text()
  self.screen.move_cursor(1, 1)
  self.screen.clear_to_eol()
  self.screen.bold()
  self.screen.write_string(text)
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
/// Redraw the input area.
async fn TuiController::redraw_input(self : TuiController) -> Unit {
  let input_lines = self.input.render_lines()
  let (w, h) = self.layout.screen_size()
  let input_h = 4
  let top = h - input_h
  for i = 0; i < input_h; i = i + 1 {
    self.screen.move_cursor(top + i + 1, 1)
    self.screen.clear_to_eol()
    if i == 0 {
      self.screen.set_foreground(@color.Color::Basic(@color.BasicColor::Blue))
      self.screen.write_string("┌─ Input ")
      let border_w = w - 10
      for j = 0; j < border_w; j = j + 1 {
        self.screen.write_string("─")
      }
      self.screen.reset_style()
    } else if i == input_h - 1 {
      self.screen.set_foreground(@color.Color::Basic(@color.BasicColor::Blue))
      self.screen.write_string("└")
      let border_w = w - 2
      for j = 0; j < border_w; j = j + 1 {
        self.screen.write_string("─")
      }
      self.screen.write_string("┘")
      self.screen.reset_style()
    } else if i - 1 < input_lines.length() {
      self.screen.set_foreground(@color.Color::Basic(@color.BasicColor::Blue))
      self.screen.write_string("│ ")
      self.screen.reset_style()
      self.screen.write_string(input_lines[i - 1])
    } else {
      self.screen.set_foreground(@color.Color::Basic(@color.BasicColor::Blue))
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
            self.full_redraw()
          }
        }
      ConfirmationRequest(tool, args) => {
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
        self.layout.commit_all()
        self.dirty = true
        self.redraw()
      }
      AgentError(msg) => {
        self.agent_running = false
        self.agent_task = None
        self.state.val.mode = TuiMode::Idle
        ignore(self.output.append_text("[error] \{msg}", OutputKind::Text))
        self.layout.commit_all()
        self.dirty = true
        self.redraw()
      }
      SubmitInput(text) => self.start_agent(group, text)
      Tick => {
        if self.agent_running || self.state.val.streaming_active {
          self.dirty = true
        }
        if self.state.val.thinking_buffer.length() != self.last_thinking_len {
          self.last_thinking_len = self.state.val.thinking_buffer.length()
          truncate_thinking_buffer(self.state.val)
          self.dirty = true
        }
      }
      TerminalClosed => self.quit = true
      HookEvent(_) => self.dirty = true
    }
    if self.dirty {
      self.redraw()
      self.dirty = false
    }
  }
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
      self.input.insert_text(text)
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
        consume_confirmation(self.state.val)
        self.state.val.dialog = DialogState::NoDialog
        match self.confirmation_response {
          Some(q) => ignore(q.try_put(true))
          None => ()
        }
        self.dirty = true
      }
      Char('n') | Char('N') | Escape => {
        consume_confirmation(self.state.val)
        self.state.val.dialog = DialogState::NoDialog
        match self.confirmation_response {
          Some(q) => ignore(q.try_put(false))
          None => ()
        }
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
        consume_confirmation(self.state.val)
        self.state.val.dialog = DialogState::NoDialog
        match self.confirmation_response {
          Some(q) => ignore(q.try_put(false))
          None => ()
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
    Enter => self.handle_enter_key()
    Char('j') if key.modifiers.ctrl() => {
      self.input.handle_enter()
      self.dirty = true
    }
    Char('l') if key.modifiers.ctrl() => self.full_redraw()
    Char('k') if key.modifiers.ctrl() => {
      self.input.kill_to_end()
      self.dirty = true
    }
    Char('u') if key.modifiers.ctrl() => {
      self.input.kill_to_start()
      self.dirty = true
    }
    Char('w') if key.modifiers.ctrl() => {
      self.input.kill_word()
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
      self.input.cursor_up()
      self.dirty = true
    }
    Down => {
      self.input.cursor_down()
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
      self.dirty = true
    }
    Delete => {
      self.input.delete_forward()
      self.dirty = true
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
    Char(ch) if !key.modifiers.ctrl() && !key.modifiers.alt() => {
      self.input.insert_char(ch)
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
  if text.length() > 0 {
    // Check for slash commands
    if text[0:1] == "/" {
      let parser = SlashCommandParser::new()
      match parser.parse(text) {
        Ok(cmd) => {
          match cmd {
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
            _ => ()
          }
          // Execute other slash commands
          let result = execute(cmd, self.agent)
          match result {
            Ok(msg) => {
              ignore(
                self.output.append_text("[system] \{msg}", OutputKind::Text),
              )
              self.layout.commit_all()
              self.dirty = true
              self.redraw()
            }
            Err(err) => {
              ignore(
                self.output.append_text("[error] \{err}", OutputKind::Text),
              )
              self.layout.commit_all()
              self.dirty = true
              self.redraw()
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
    ignore(self.output.append_text("[user] \{text}", OutputKind::Text))
    // Commit it immediately
    self.layout.commit_all()
    // Run agent
    self.state.val.mode = TuiMode::Running
    self.agent_running = true
    self.hooks.reset_for_run()
    self.dirty = true
    self.redraw()
    self.events.put(SubmitInput(text))
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
        events.put(AgentError("\{err}"))
        raise err
      }
    }
    events.put(AgentDone(result))
    result
  }
  self.agent_task = Some(task)
}
