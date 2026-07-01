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
      // Setup terminal: hide cursor, enter alternate screen, query capabilities.
      app.get_renderer().setup_terminal(true)
      AgentHookHandler::new(state, agent=Some(agent)).register_all(
        agent.hook_manager,
      )

      // Build the full view tree from current state
      fn build_ui() -> @view.View {
        build_main_layout(state, input_ref, agent, should_quit)
      }

      // Handle global input events
      fn on_global_event(event : @ffi.InputEvent) -> Bool {
        handle_global_event(
          state, input_ref, should_quit, modal_lifecycle, agent, event,
        )
      }

      // Run event loop (blocks until quit)
      @runtime.run_event_loop(app, build_ui, on_global_event~)

      // Clean up: restore terminal, exit alternate screen
      app.cleanup()
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

  // Get current terminal dimensions for adaptive component sizing
  let (term_w, term_h) = @ffi.get_terminal_size()
  let terminal_width = term_w.reinterpret_as_int()
  let terminal_height = term_h.reinterpret_as_int()

  // Status bar
  let status = status_bar_render(state)

  // Main content area: split into message history + tool output
  // Show welcome banner when no messages yet
  let main_panel = if s.messages.length() == 0 {
    let banner_width = Banner::adaptive_width(terminal_width)
    let banner = Banner::with_width(banner_width)
    let banner_text = banner.render("OpenClacky", Some("AI Agent TUI"))
    let banner_views : Array[@view.View] = []
    for line in banner_text.split("\n") {
      banner_views.push(@view.View::text(line.to_owned(), color=@tui_core.Cyan))
    }
    @view.View::container_views(banner_views).padding(1.0).flex(2.0)
  } else {
    message_view_render(state)
  }
  let content_center = main_panel

  // Sidebar: render alongside main content when visible
  let content = if s.sidebar_panel.visible {
    let sidebar_lines = s.sidebar_panel.render()
    let sidebar_views : Array[@view.View] = []
    for line in sidebar_lines {
      sidebar_views.push(@view.View::text(line, color=@tui_core.White))
    }
    let sidebar_view = @view.View::container_views(sidebar_views)
    @view.View::container_views([content_center.flex(1.0), sidebar_view]).direction(
      Row,
    )
  } else {
    content_center
  }

  // Input bar or running indicator
  let footer = match s.mode {
    Running => {
      // Build progress spinner lines from the ProgressStack
      let progress_lines = s.progress_stack.render()
      let children : Array[@view.View] = [
        @view.View::text(
          " Agent is running... (Ctrl+C to interrupt)",
          color=@tui_core.Yellow,
        ),
      ]
      for line in progress_lines {
        children.push(@view.View::text("  \{line}", color=@tui_core.Cyan))
      }
      @view.View::container_views(children)
      .padding(1.0)
      .background(@tui_core.RGB(0.12, 0.12, 0.17))
    }
    Idle =>
      input_bar_render(
        input_ref,
        fn() {
          // Submit callback
          submit_input(state, input_ref, agent, should_quit)
        },
        fn() {
          // Quit callback
          should_quit.val = true
        },
        terminal_width~,
      )
  }

  // Assemble full layout
  @view.View::container_views([
    content.flex(1.0),
    status,
    footer,
  ]).direction(Column)
  .width(terminal_width.to_double())
  .height(terminal_height.to_double())
}

///|
/// Handle a global input event from the event loop.
///
/// Returns true if the event was consumed, false to let it propagate.
fn handle_global_event(
  state : Ref[TuiState],
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
    // Escape key 鈥?close topmost modal if any
    KeyMod(Char(27), _) =>
      if modal_lifecycle.val.is_active() {
        modal_lifecycle.val.close_top()
        true
      } else {
        false
      }
    // Ctrl-B (Char(2)): toggle sidebar visibility
    KeyMod(Char(2), _) => {
      state.val.sidebar_panel.toggle_visibility()
      true
    }
    // Ctrl-K (Char(11)): kill to end of line 鈥?let TextInput handle
    Key(Char(11)) => false
    // Ctrl-U (Char(21)): kill to start of line 鈥?let TextInput handle
    Key(Char(21)) => false
    // Ctrl-W (Char(23)): kill previous word 鈥?let TextInput handle
    Key(Char(23)) => false
    _ => false // Let other events propagate to focused views
  }
}

///|
/// Submit the current input text to the agent for execution.
///
/// Slash commands (input starting with "/") are intercepted and handled
/// locally; only plain text is forwarded to agent.run().
fn submit_input(
  state : Ref[TuiState],
  input_ref : Ref[String],
  agent : @agent.Agent,
  should_quit : Ref[Bool],
) -> Unit {
  let input_text = input_ref.val.trim().to_owned()
  if input_text.length() == 0 {
    return
  }

  // Check for slash commands
  let input_chars = input_text.to_array()
  if input_chars.length() > 0 && input_chars[0] == '/' {
    let parser = SlashCommandParser::new()
    match parser.parse(input_text) {
      Ok(cmd) =>
        match cmd {
          Exit => {
            should_quit.val = true
            input_ref.val = ""
            return
          }
          Clear => {
            state.val.messages = []
            // Also clear agent conversation history
            try {
              agent.history.clear()
              agent.iterations = 0
              ()
            } catch {
              _ => ()
            }
            state.val.messages.push("[system] Message history cleared")
            input_ref.val = ""
            return
          }
          _ => {
            match execute(cmd, agent) {
              Ok(result) => state.val.messages.push("[system] \{result}")
              Err(err) => state.val.messages.push("[system] Error: \{err}")
            }
            input_ref.val = ""
            return
          }
        }
      Err(err) => {
        state.val.messages.push("[system] \{err}")
        input_ref.val = ""
        return
      }
    }
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

  // Update session bar from agent
  s.session_bar.update_from_state(s)
  s.session_bar.working_dir = agent.working_dir
  s.session_bar.task_count = agent.todo_manager.size()

  // Update todo area from agent's TodoManager
  let todo_items = agent.todo_manager.list_all()
  let display_items : Array[TodoDisplayItem] = []
  let mut completed = 0
  let mut idx = 0
  for item in todo_items {
    let status_str = item.status.to_string_value()
    if status_str == "completed" {
      completed = completed + 1
    }
    display_items.push(TodoDisplayItem::{
      id: idx + 1,
      title: item.title,
      status: status_str,
      description: item.description,
    })
    idx = idx + 1
  }
  s.todo_area.update(display_items, completed, todo_items.length())

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
