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
///   update the shared TuiState. After agent.run() returns, the event loop
///   resumes and renders the updated state on the next frame.
///
/// Phase 7 note: Inline rendering during agent.run() (live screen updates)
/// is deferred to a future enhancement. The screen updates after each
/// agent run completes.

///|
/// Entry point: launch the TUI with an initialized agent.
///
/// Falls back to a console message if terminal initialization fails.
pub fn run_tui_interactive(agent : @agent.Agent) -> Unit {
  let state = Ref(TuiState::from_agent(agent))
  let input_ref = Ref("")
  let should_quit = Ref(false)

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
        handle_global_event(state, input_ref, should_quit, agent, event)
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
/// Handle a hook event by updating TUI state.
fn handle_hook_event(state : Ref[TuiState], event : @agent.HookEvent) -> Unit {
  match event {
    StatusChanged(_old, new) => state.val.agent_status = new.to_string_value()
    BeforeIteration(n) => state.val.iterations = n
    AfterLlmCall =>
      // Cost data is available via hook, but we let the next event loop
      // cycle pick up the latest agent state
      ()
    MessageAdded =>
      // Messages are read from agent on next render
      ()
    ToolExecuting(name, args) =>
      state.val.tool_output = "Running: \{name}(\{args})"
    ToolExecuted(name, _result) => state.val.tool_output = "Completed: \{name}"
    ErrorOccurred(msg) => {
      state.val.last_error = Some(msg)
      state.val.agent_status = "error"
    }
    RunCompleted(result) => {
      state.val.agent_status = "completed"
      state.val.total_cost = result.total_cost_usd
    }
    _ => ()
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
