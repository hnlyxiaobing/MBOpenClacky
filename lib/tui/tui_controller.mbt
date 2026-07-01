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
/// Spinner tick interval (ms).
let spinner_tick_ms : Int = 200

///|
/// Controller for the inline TUI application.
pub(all) struct TuiController {
  /// Underlying terminal handle.
  tty : @tty.Tty
  /// Screen buffer for low-level rendering.
  screen : ScreenBuffer
  /// Logical output buffer.
  output : OutputBuffer
  /// Layout manager.
  layout : LayoutManager
  /// Status bar formatter.
  status_bar : StatusBar
  /// Input area (wraps LineEditor).
  input : InputArea
  /// Shared TUI state.
  state : Ref[TuiState]
  /// Agent reference.
  agent : @agent.Agent
  /// Hook handler for agent events.
  hooks : AgentHookHandler
  /// Whether the TUI should quit.
  mut quit : Bool
  /// Whether a redraw is needed on next loop iteration.
  mut dirty : Bool
  /// Whether the agent is currently running.
  mut agent_running : Bool
  /// Version of output buffer at last render.
  mut last_output_version : Int
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
  let state = Ref::new(TuiState::from_agent(agent))
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
  }
}

// ── Rendering ─────────────────────────────────────────────────────

///|
/// Full screen redraw: status bar, output area, input area.
pub async fn TuiController::full_redraw(self : TuiController) -> Unit {
  self.layout.compute_layout()
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
}

///|
/// Redraw the input area.
async fn TuiController::redraw_input(self : TuiController) -> Unit {
  let input_lines = self.input.render_lines()
  let (w, h) = self.layout.screen_size()
  let input_top = h - self.layout.status_h
  // input_h from layout — recompute
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
  let (w, h) = self.layout.screen_size()
  let input_h = 4
  let top = h - input_h
  let (cursor_line, cursor_col) = self.input.cursor_display_pos()
  let row = top + 1 + cursor_line
  let col = 3 + cursor_col  // +3 for "│ " prefix
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
/// Main run loop: enter raw mode, render, process events.
pub async fn TuiController::run(self : TuiController) -> Unit {
  // Register hooks
  self.hooks.register_all(self.agent.hook_manager)
  // Enter raw mode
  self.tty.with_raw_mode(() => self.event_loop())
}

///|
/// Inner event loop (called inside raw mode).
async fn TuiController::event_loop(self : TuiController) -> Unit {
  // Initial full redraw
  self.full_redraw()
  while not(self.quit) {
    let event = self.tty.read_event(esc_timeout_ms~) catch {
      @async/io.ReaderClosed => {
        self.quit = true
        return
      }
      _ => return
    }
    match event {
      Input(input) => self.handle_input(input)
      Resize(_) => {
        self.layout.compute_layout()
        self.full_redraw()
      }
    }
    // Redraw if needed
    if self.dirty {
      self.redraw()
      self.dirty = false
    }
  }
  self.restore_terminal()
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
  match key.code {
    // Ctrl-C: quit
    Char('c') if key.modifiers.ctrl() => {
      self.quit = true
    }
    // Ctrl-D: quit if input empty
    Char('d') if key.modifiers.ctrl() && self.input.is_empty() => {
      self.quit = true
    }
    // Ctrl-J or Enter: submit or newline
    Enter => self.handle_enter_key()
    Char('j') if key.modifiers.ctrl() => {
      // Insert newline in multi-line mode
      self.input.handle_enter()
      self.dirty = true
    }
    // Ctrl-L: full redraw
    Char('l') if key.modifiers.ctrl() => {
      self.full_redraw()
    }
    // Ctrl-K: kill to end of line
    Char('k') if key.modifiers.ctrl() => {
      self.input.kill_to_end()
      self.dirty = true
    }
    // Ctrl-U: kill to start of line
    Char('u') if key.modifiers.ctrl() => {
      self.input.kill_to_start()
      self.dirty = true
    }
    // Ctrl-W: kill word
    Char('w') if key.modifiers.ctrl() => {
      self.input.kill_word()
      self.dirty = true
    }
    // Arrow keys
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
    // Regular character input
    Char(ch) if not(key.modifiers.ctrl()) && not(key.modifiers.alt()) => {
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
    // Run agent (synchronous — blocks event loop during ReAct)
    let _ = self.agent.run(text) catch {
      _ =>
        @agent.RunResult::{
          status: @agent.RunStatus::Error,
          session_id: "",
          iterations: 0,
          total_cost_usd: 0.0,
          cost_source: @agent.CostSource::Default,
          cache_stats: @agent.CacheStats::new(),
          error: Some("Agent error"),
        }
    }
    self.agent_running = false
    self.state.val.mode = TuiMode::Idle
    // Add agent response indicator
    self.layout.commit_all()
    self.dirty = true
  }
}
