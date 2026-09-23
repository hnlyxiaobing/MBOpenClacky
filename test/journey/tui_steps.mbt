///|
/// TUI journey step actions: in-process simulator driven by a REAL agent
/// pointed at the mock upstream (new_with_agent), so a `tui_send` runs the
/// full ReAct loop and the production AgentHookHandler pipeline renders
/// real events into the virtual screen.
///
/// Env note: HOME/USERPROFILE are set process-globally before agent
/// construction (scenario_runner pattern) so in-process sessions land in
/// the sandbox home. Journeys are strictly sequential, so the mutation is
/// re-seeded by each tui_new step and never observed concurrently.

///|
/// Create the simulator with a real agent against the mock upstream.
/// Two models are registered (both pointing at the mock) so /config and
/// /model journeys can exercise model switching; the first is current.
fn tui_new_step(
  group : @async.TaskGroup[Unit],
  state : JourneyState,
  cols : Int,
  rows : Int,
  phase_name : String,
) -> Unit {
  ignore(group)
  let ctx = state.ctx
  @env.set_env_var("HOME", ctx.home)
  @env.set_env_var("USERPROFILE", ctx.home)
  let mock_url = "http://127.0.0.1:\{ctx.mock_port}"
  let client = @client.Client::new(
    "mock-key",
    mock_url,
    "mock-model-a",
    @config.OpenAICompletions,
  )
  let config = @config.AgentConfig::default()
  let mode = match @config.PermissionMode::from_string(state.permission_mode) {
    Some(m) => m
    None => @config.ConfirmSafes
  }
  config.permission_mode = mode
  config.memory_update_enabled = false
  config.models = [
    @config.ModelConfig::new("mock-a", "mock-key", mock_url, "mock-model-a"),
    @config.ModelConfig::new("mock-b", "mock-key", mock_url, "mock-model-b"),
  ]
  config.current_model_id = Some("mock-a")
  let agent = @agent.Agent::new(
    "journey-\{ctx.scenario_id}",
    "Journey",
    ctx.workspace,
    client,
    config,
  )
  let sim = @test_tui.TuiEvalSimulator::new_with_agent(cols, rows, agent)
  state.tui = Some(sim)
  state.trace.push(
    "[\{phase_name}] tui simulator \{cols}x\{rows} (real agent → mock, mode=\{mode.to_string_value()})",
  )
}

///|
fn tui_type_step(
  state : JourneyState,
  text : String,
  phase_name : String,
) -> Unit {
  match state.tui {
    Some(sim) => {
      let expanded = expand_journey_placeholders(text, state.ctx)
      sim.type_text(expanded)
      state.trace.push("[\{phase_name}] tui type (\{expanded.length()} chars)")
    }
    None => state.error = "[\{phase_name}] tui_type: no TUI simulator"
  }
}

///|
fn tui_press_step(
  state : JourneyState,
  key : String,
  phase_name : String,
) -> Unit {
  match state.tui {
    Some(sim) => {
      sim.press_key(key)
      state.trace.push("[\{phase_name}] tui press '\{key}'")
    }
    None => state.error = "[\{phase_name}] tui_press: no TUI simulator"
  }
}

///|
/// Submit a message through the REAL ReAct loop. If the input area holds
/// typed text it is submitted (mirrors pressing Enter); otherwise the
/// step's text is used. The run is watchdog-bounded.
async fn tui_send_step(
  group : @async.TaskGroup[Unit],
  state : JourneyState,
  text : String,
  timeout_ms : Int,
  phase_name : String,
) -> Unit {
  ignore(group)
  match state.tui {
    Some(sim) => {
      let typed = sim.input.submit()
      let message = if typed.length() > 0 {
        typed
      } else {
        expand_journey_placeholders(text, state.ctx)
      }
      if message.length() == 0 {
        state.error = "[\{phase_name}] tui_send: empty message"
        return
      }
      state.trace.push(
        "[\{phase_name}] tui send (real ReAct, \{timeout_ms}ms watchdog)",
      )
      // Mirror the simulator's handle_enter flow up to the agent call.
      ignore(
        sim.output.append_text("[user] \{message}", @libtui.OutputKind::Text),
      )
      ignore(sim.state.val.time_machine.start_new_task(Some(message)))
      match sim.output.last_entry_id() {
        Some(id) => sim.output.commit_through(id)
        None => ()
      }
      sim.state.val.mode = @libtui.TuiMode::Running
      sim.state.val.todo_area.show()
      sim.full_redraw()
      // Real run: hooks (production AgentHookHandler, wired at construction)
      // render events into the output buffer as they arrive.
      let run_result = @async.with_timeout_opt(timeout_ms, () => {
        sim.agent.run(message)
      })
      match run_result {
        Some(_) => ()
        None => {
          state.error = "[\{phase_name}] tui_send: agent run timed out after \{timeout_ms}ms"
          return
        }
      }
      sim.state.val.mode = @libtui.TuiMode::Idle
      sim.state.val.todo_area.hide()
      sim.state.val.agent_status.set("idle")
      // Mirror finalized replies (TuiState.messages) into the output
      // buffer — the controller's AgentOutputSync job, done once post-run
      // for the headless journey. Tracked so repeated sends never re-show.
      for i = state.tui_messages_synced
          i < sim.state.val.messages.length()
          i = i + 1 {
        ignore(
          sim.output.append_text(
            sim.state.val.messages[i],
            @libtui.OutputKind::Text,
          ),
        )
        match sim.output.last_entry_id() {
          Some(id) => sim.output.commit_through(id)
          None => ()
        }
      }
      state.tui_messages_synced = sim.state.val.messages.length()
      sim.full_redraw()
    }
    None => state.error = "[\{phase_name}] tui_send: no TUI simulator"
  }
}

///|
fn tui_screenshot_step(
  state : JourneyState,
  name : String,
  phase_name : String,
) -> Unit {
  match state.tui {
    Some(sim) => {
      let content = sim.screenshot()
      state.screenshot_count = state.screenshot_count + 1
      let label = if name.length() > 0 {
        name
      } else {
        "\{state.screenshot_count}"
      }
      state.trace.push(
        "[\{phase_name}] tui screenshot '\{label}' (\{content.length()} chars)",
      )
    }
    None => state.error = "[\{phase_name}] tui_screenshot: no TUI simulator"
  }
}
