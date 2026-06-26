///|
/// Agent Hook Handler: comprehensive hook registration and event routing.
///
/// Provides a structured way to register callbacks for all agent hook events
/// with the TUI state. This separates the hook wiring from the main TUI
/// event loop, making it easier to add new hook-driven behaviors.

///|
/// Configuration options for the agent hook handler.
pub(all) struct HookHandlerConfig {
  /// Whether to track tool execution history.
  track_tool_history : Bool
  /// Whether to track LLM call counts.
  track_llm_calls : Bool
  /// Whether to maintain a phase stack.
  track_phases : Bool
} derive(Debug)

///|
/// Default configuration: all tracking enabled.
pub fn default_hook_config() -> HookHandlerConfig {
  { track_tool_history: true, track_llm_calls: true, track_phases: true }
}

///|
/// Agent hook handler that manages hook event routing to TuiState.
///
/// Wraps the shared TuiState reference and provides configurable
/// event handling for all HookEvent variants.
pub(all) struct AgentHookHandler {
  state : Ref[TuiState]
  config : HookHandlerConfig
} derive(Debug)

///|
/// Create a new AgentHookHandler.
pub fn AgentHookHandler::new(
  state : Ref[TuiState],
  config? : HookHandlerConfig = default_hook_config(),
) -> AgentHookHandler {
  { state, config }
}

///|
/// Register this handler's callback on the given HookManager.
///
/// This registers a single callback that routes all HookEvent variants
/// through the handler's dispatch logic.
pub fn AgentHookHandler::register_all(
  self : AgentHookHandler,
  hook_manager : @agent.HookManager,
) -> Unit {
  let state = self.state
  let config = self.config
  hook_manager.register(fn(event : @agent.HookEvent) {
    dispatch_hook_event(state, config, event)
  })
}

///|
/// Reset the handler state for a new agent run.
/// Clears tool history, LLM call count, phase stack, and errors.
pub fn AgentHookHandler::reset_for_run(self : AgentHookHandler) -> Unit {
  let s = self.state.val
  s.tool_history = []
  s.llm_call_count = 0
  s.llm_calling = false
  s.phase_stack = []
  s.current_tool_name = ""
  s.current_tool_args = ""
  s.last_error = None
}

///|
/// Internal event dispatch with configuration-gated tracking.
fn dispatch_hook_event(
  state : Ref[TuiState],
  config : HookHandlerConfig,
  event : @agent.HookEvent,
) -> Unit {
  let s = state.val
  match event {
    StatusChanged(_old, new) => s.agent_status = new.to_string_value()
    BeforeIteration(n) => {
      s.iterations = n
      s.agent_status = "iterating"
      if config.track_phases {
        s.phase_stack.push("iteration_\{n}")
      }
      s.current_tool_name = ""
      s.current_tool_args = ""
    }
    AfterIteration(n) => {
      s.iterations = n
      s.agent_status = "iteration_done"
      if config.track_phases && s.phase_stack.length() > 0 {
        ignore(s.phase_stack.pop())
      }
    }
    BeforeLlmCall => {
      if config.track_llm_calls {
        s.llm_call_count = s.llm_call_count + 1
      }
      s.llm_calling = true
      s.agent_status = "thinking"
      if config.track_phases {
        s.phase_stack.push("llm_call")
      }
    }
    AfterLlmCall => {
      s.llm_calling = false
      s.agent_status = "llm_done"
      if config.track_phases && s.phase_stack.length() > 0 {
        ignore(s.phase_stack.pop())
      }
    }
    MessageAdded => s.agent_status = "message_added"
    ToolExecuting(name, args) => {
      s.current_tool_name = name
      s.current_tool_args = args
      s.tool_output = "Running: \{name}(\{args})"
      s.agent_status = "tool_call"
      if config.track_phases {
        s.phase_stack.push("tool_\{name}")
      }
      if config.track_tool_history {
        s.tool_history.push(ToolExecution::{
          name,
          args,
          completed: false,
          result_summary: "",
        })
      }
    }
    ToolExecuted(name, _result) => {
      s.tool_output = "Completed: \{name}"
      s.current_tool_name = ""
      s.current_tool_args = ""
      s.agent_status = "tool_done"
      if config.track_phases && s.phase_stack.length() > 0 {
        ignore(s.phase_stack.pop())
      }
      if config.track_tool_history {
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
    }
    ErrorOccurred(msg) => {
      s.last_error = Some(msg)
      s.agent_status = "error"
      if config.track_phases {
        while s.phase_stack.length() > 0 {
          ignore(s.phase_stack.pop())
        }
      }
    }
    RunCompleted(result) => {
      s.agent_status = "completed"
      s.total_cost = result.total_cost_usd
      s.iterations = result.iterations
      s.llm_calling = false
      s.current_tool_name = ""
      s.current_tool_args = ""
      if config.track_phases {
        while s.phase_stack.length() > 0 {
          ignore(s.phase_stack.pop())
        }
      }
    }
  }
}
