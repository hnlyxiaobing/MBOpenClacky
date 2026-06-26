///|
/// Main TUI application: entry point, event loop wiring, and layout assembly.
///
/// The TUI operates in two modes (Idle / Running) using a synchronous
/// hook-driven architecture:
///
/// - **Idle mode**: User types messages in the input bar, the event loop
///   polls for keyboard input and renders the full view tree.
///
/// - **Running mode**: agent.run() is on the call stack. Hook callbacks
///   update the shared TuiState immediately. The onebit-tui render loop
///   picks up state changes on the next frame (~60 FPS), providing
///   real-time visual feedback during agent execution.

///|
/// Entry point: launch the TUI with an initialized agent.
///
/// Falls back to a console message if terminal initialization fails.
pub fn run_tui_interactive(agent : @agent.Agent) -> Unit {
  let state = Ref(TuiState::from_agent(agent))
  let input_ref = Ref("")
  let should_quit = Ref(false)
  let modal_lifecycle = Ref(ModalLifecycle::new())

  match @tui_core.App::init() {
    None => {
      println("Failed to initialize TUI. Falling back to CLI mode.")
      println(
        "Use --message to send a single message, or check terminal compatibility.",
      )
    }
    Some(app) => {
      // ── Wire hooks to update shared state ────────────────────────
      agent.hook_manager.register(fn(event : @agent.HookEvent) {
        handle_hook_event(state, event)
      })

      // ── Build the full view tree from current state ──────────────
      fn build_ui() -> @view.View {
        build_main_layout(state, input_ref, agent, should_quit)
      }

      // ── Handle global input events ───────────────────────────────
      fn on_global_event(event : @ffi.InputEvent) -> Bool {
        handle_global_event(
          state, input_ref, should_quit, modal_lifecycle, agent, event,
        )
      }

      // ── Run event loop (blocks until quit) ───────────────────────
      @runtime.run_event_loop(app, build_ui, on_global_event~)
    }
  }
}

///|
/// Build the main layout from current TUI state.
fn build_main_layout(
  state : Ref[TuiState],
  input_ref : Ref[String],
  agent : @agent.Agent,
  should_quit : Ref[Bool],
) -> @view.View {
  let s = state.val

  // Status bar
  let status = status_bar_render(state)

  // Main content area: split into message history + tool output
  let messages = message_view_render(state).flex(2.0)
  let tool_out = tool_view_render(state).flex(1.0)
  let content = @view.View::container_views([messages, tool_out]).direction(Row)

  // Stats bar
  let stats = stats_bar_render(state)

  // Input bar or running indicator
  let footer = match s.mode {
    Running =>
      @view.View::container_views([
        @view.View::text(
          " Agent is running... (Ctrl+C to interrupt)",
          color=@tui_core.Yellow,
        ),
      ])
      .padding(1.0)
      .background(@tui_core.RGB(0.12, 0.12, 0.17))
    Idle =>
      input_bar_render(
        input_ref,
        fn() {
          // Submit callback
          submit_input(state, input_ref, agent)
        },
        fn() {
          // Quit callback
          should_quit.val = true
        },
      )
  }

  // Assemble full layout
  @view.View::container_views([status, content.flex(1.0), stats, footer]).direction(
    Column,
  )
}

///|
/// Handle a hook event by updating TUI state immediately.
///
/// Every hook event updates the shared Ref[TuiState] so the next render
/// frame reflects the latest agent activity. This provides real-time
/// visual feedback during agent execution.
fn handle_hook_event(state : Ref[TuiState], event : @agent.HookEvent) -> Unit {
  let s = state.val
  match event {
    StatusChanged(_old, new) => s.agent_status = new.to_string_value()
    BeforeIteration(n) => {
      s.iterations = n
      s.agent_status = "iterating"
      // Push iteration phase
      s.phase_stack.push("iteration_\{n}")
      // Clear previous tool state for new iteration
      s.current_tool_name = ""
      s.current_tool_args = ""
    }
    AfterIteration(n) => {
      s.iterations = n
      s.agent_status = "iteration_done"
      // Pop iteration phase
      if s.phase_stack.length() > 0 {
        ignore(s.phase_stack.pop())
      }
    }
    BeforeLlmCall => {
      s.llm_call_count = s.llm_call_count + 1
      s.llm_calling = true
      s.agent_status = "thinking"
      s.phase_stack.push("llm_call")
    }
    AfterLlmCall => {
      s.llm_calling = false
      s.agent_status = "llm_done"
      // Pop llm_call phase
      if s.phase_stack.length() > 0 {
        ignore(s.phase_stack.pop())
      }
    }
    MessageAdded =>
      // Mark that a new message was added; the message content
      // is pulled from agent.history in sync_state_from_agent
      s.agent_status = "message_added"
    ToolExecuting(name, args) => {
      s.current_tool_name = name
      s.current_tool_args = args
      s.tool_output = "Running: \{name}(\{args})"
      s.agent_status = "tool_call"
      s.phase_stack.push("tool_\{name}")
      // Add to tool history as in-progress
      s.tool_history.push(ToolExecution::{
        name,
        args,
        completed: false,
        result_summary: "",
      })
    }
    ToolExecuted(name, _result) => {
      s.tool_output = "Completed: \{name}"
      s.current_tool_name = ""
      s.current_tool_args = ""
      s.agent_status = "tool_done"
      // Pop tool phase
      if s.phase_stack.length() > 0 {
        ignore(s.phase_stack.pop())
      }
      // Mark the last matching tool in history as completed
      let mut i = s.tool_history.length() - 1
      while i >= 0 {
        if s.tool_history[i].name == name && !s.tool_history[i].completed {
          s.tool_history[i].completed = true
          s.tool_history[i].result_summary = "ok"
          break
        }
        i = i - 1
      }
    }
    ErrorOccurred(msg) => {
      s.last_error = Some(msg)
      s.agent_status = "error"
      // Clear phase stack on error
      while s.phase_stack.length() > 0 {
        ignore(s.phase_stack.pop())
      }
    }
    RunCompleted(result) => {
      s.agent_status = "completed"
      s.total_cost = result.total_cost_usd
      s.iterations = result.iterations
      // Clear all running state
      s.llm_calling = false
      s.current_tool_name = ""
      s.current_tool_args = ""
      while s.phase_stack.length() > 0 {
        ignore(s.phase_stack.pop())
      }
    }
  }
}

///|
/// Handle a global input event from the event loop.
///
/// Returns true if the event was consumed, false to let it propagate.
fn handle_global_event(
  _state : Ref[TuiState],
  _input_ref : Ref[String],
  should_quit : Ref[Bool],
  modal_lifecycle : Ref[ModalLifecycle],
  _agent : @agent.Agent,
  event : @ffi.InputEvent,
) -> Bool {
  if should_quit.val {
    return true
  }

  match event {
    // Ctrl+C (Char(3)) to quit
    KeyMod(Char(3), _) => {
      should_quit.val = true
      true
    }
    // Escape key — close topmost modal if any
    KeyMod(Char(27), _) =>
      if modal_lifecycle.val.is_active() {
        modal_lifecycle.val.close_top()
        true
      } else {
        false
      }
    _ => false // Let other events propagate to focused views
  }
}

///|
/// Submit the current input text to the agent for execution.
fn submit_input(
  state : Ref[TuiState],
  input_ref : Ref[String],
  agent : @agent.Agent,
) -> Unit {
  let input_text = input_ref.val.trim().to_owned()
  if input_text.length() == 0 {
    return
  }

  // Switch to Running mode
  state.val.mode = Running
  state.val.agent_status = "running"
  input_ref.val = ""

  // Run the agent (blocking — hooks update state during execution)
  try {
    let _ = agent.run(input_text)
    ()
  } catch {
    _ => {
      state.val.agent_status = "error"
      state.val.last_error = Some("Agent execution failed")
    }
  }

  // Sync state from agent after run completes
  sync_state_from_agent(state, agent)

  // Switch back to Idle
  state.val.mode = Idle
  state.val.agent_status = "idle"
}

///|
/// Sync TUI state from the agent's current state after a run.
fn sync_state_from_agent(state : Ref[TuiState], agent : @agent.Agent) -> Unit {
  let s = state.val
  s.total_cost = agent.total_cost
  s.cost_source = agent.cost_source.to_string_value()
  s.iterations = agent.iterations

  // Pull messages from agent history
  let display_messages : Array[String] = []
  for msg in agent.history {
    let role_str = match msg.role {
      System => "system"
      User => "user"
      Assistant => "assistant"
      Tool => "tool"
    }
    let content = match msg.content {
      Text(c) => c
      Blocks(blocks) => {
        let parts : Array[String] = []
        for block in blocks {
          match block {
            Text(tb) => parts.push(tb.text)
            Image(ib) => parts.push("[Image: \{ib.url}]")
          }
        }
        parts.join("\n")
      }
    }
    let line = "[\{role_str}] \{content}"
    display_messages.push(line)
  }
  s.messages = display_messages
}

// ── TuiController ────────────────────────────────────────────────────

///|
/// UI interaction mode for the TuiController.
pub(all) enum UiMode {
  /// Normal browsing mode.
  Normal
  /// A modal dialog is active.
  Dialog
  /// Sidebar panel is visible.
  Sidebar
} derive(Eq, Debug, Show)

///|
/// High-level UI controller that coordinates layout, output, screen,
/// dialogs, and sidebar. Built on top of the lower-level components.
pub(all) struct TuiController {
  /// Layout manager for screen regions.
  layout_manager : LayoutManager
  /// Output buffer for conversation history.
  output_buffer : OutputBuffer
  /// Screen buffer for cell-level rendering.
  screen_buffer : ScreenBuffer
  /// Currently active modal dialog.
  mut active_dialog : Dialog?
  /// Sidebar panel.
  mut sidebar : SidebarPanel?
  /// Current UI interaction mode.
  mut mode : UiMode
} derive(Debug)

///|
/// Create a new TuiController with the given screen dimensions.
pub fn TuiController::new(width : Int, height : Int) -> TuiController {
  {
    layout_manager: LayoutManager::new(width, height),
    output_buffer: OutputBuffer::new(1000, height - 4),
    screen_buffer: ScreenBuffer::new(width, height),
    active_dialog: None,
    sidebar: None,
    mode: Normal,
  }
}

///|
/// Enter dialog mode with the given dialog.
pub fn TuiController::enter_dialog_mode(
  self : TuiController,
  dialog : Dialog,
) -> Unit {
  dialog.open()
  self.active_dialog = Some(dialog)
  self.mode = Dialog
}

///|
/// Exit dialog mode, submitting the dialog and returning the result.
pub fn TuiController::exit_dialog_mode(self : TuiController) -> String? {
  match self.active_dialog {
    Some(dialog) => {
      let result = dialog.submit()
      dialog.close()
      self.active_dialog = None
      self.mode = Normal
      result
    }
    None => {
      self.mode = Normal
      None
    }
  }
}

///|
/// Toggle the sidebar panel visibility.
pub fn TuiController::toggle_sidebar(self : TuiController) -> Unit {
  match self.sidebar {
    Some(sb) => {
      sb.toggle_visibility()
      if sb.visible {
        self.mode = Sidebar
      } else {
        self.mode = Normal
      }
    }
    None => {
      // Create a default sidebar
      let sb = SidebarPanel::new("Sessions", 25)
      sb.toggle_visibility()
      self.sidebar = Some(sb)
      self.mode = Sidebar
    }
  }
}

///|
/// Handle a window resize event.
pub fn TuiController::handle_resize(
  self : TuiController,
  width : Int,
  height : Int,
) -> Unit {
  self.layout_manager.resize(width, height)
  self.output_buffer.set_viewport_height(height - 4)
  self.screen_buffer.resize(width, height)
}

///|
/// Render a complete frame as an array of text lines.
///
/// Combines output buffer, sidebar, and dialog into a single frame.
pub fn TuiController::render_frame(self : TuiController) -> Array[String] {
  let lines : Array[String] = []

  // Render visible output lines
  let visible = self.output_buffer.get_visible_lines()
  for line in visible {
    lines.push(line.content)
  }

  // Render sidebar if visible
  match self.sidebar {
    Some(sb) =>
      if sb.visible {
        let sb_lines = sb.render()
        for sl in sb_lines {
          lines.push(sl)
        }
      }
    None => ()
  }

  // Render dialog overlay if active
  match self.active_dialog {
    Some(dialog) =>
      if dialog.is_open {
        let dialog_lines = dialog.render()
        for dl in dialog_lines {
          lines.push(dl)
        }
      }
    None => ()
  }

  lines
}
