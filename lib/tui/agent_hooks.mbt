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
  /// Optional agent reference for updating TodoArea during iteration.
  agent : @agent.Agent?
}

///|
/// Create a new AgentHookHandler.
pub fn AgentHookHandler::new(
  state : Ref[TuiState],
  config? : HookHandlerConfig = default_hook_config(),
  agent? : @agent.Agent? = None,
) -> AgentHookHandler {
  { state, config, agent }
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
    dispatch_hook_event(state, config, self.agent, event)
  })
}

///|
/// Reset the handler state for a new agent run.
/// Clears tool history, LLM call count, phase stack, progress, and errors.
pub fn AgentHookHandler::reset_for_run(self : AgentHookHandler) -> Unit {
  let s = self.state.val
  s.tool_history = []
  s.llm_call_count = 0
  s.llm_calling = false
  s.phase_stack = []
  s.current_tool_name = ""
  s.current_tool_args = ""
  s.last_error = None
  s.progress_stack.close_all()
}

///|
/// Internal event dispatch with configuration-gated tracking.
fn is_thinking_active(s : TuiState) -> Bool {
  for phase in s.phase_stack {
    if phase == "thinking" {
      return true
    }
  }
  false
}

///|
fn dispatch_hook_event(
  state : Ref[TuiState],
  config : HookHandlerConfig,
  agent : @agent.Agent?,
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
      // Update TodoArea from agent's TodoManager if available
      match agent {
        Some(a) => {
          let todo_items = a.todo_manager.list_all()
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
          s.active_tasks = a.todo_manager.size()
          s.working_dir = a.working_dir
          s.permission_mode = a.config.permission_mode.to_string_value()
        }
        None => ()
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
      // Push progress spinner for LLM call
      ignore(s.progress_stack.push("Thinking..."))
    }
    AfterLlmCall => {
      s.llm_calling = false
      s.agent_status = "llm_done"
      if config.track_phases && s.phase_stack.length() > 0 {
        ignore(s.phase_stack.pop())
      }
      // Close the LLM spinner
      s.progress_stack.close_last()
      // Finalize streaming buffer
      if s.streaming_buffer.length() > 0 {
        s.messages.push("[assistant] \{s.streaming_buffer}")
        s.streaming_buffer = ""
      }
      s.streaming_active = false
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
      // Push progress spinner for tool execution
      ignore(s.progress_stack.push("Running: \{name}"))
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
      // Close the tool spinner
      s.progress_stack.close_last()
    }
    ErrorOccurred(msg) => {
      s.last_error = Some(msg)
      s.agent_status = "error"
      if config.track_phases {
        while s.phase_stack.length() > 0 {
          ignore(s.phase_stack.pop())
        }
      }
      // Close all spinners on error
      s.progress_stack.close_all()
      s.streaming_buffer = ""
      s.streaming_active = false
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
      // Close all spinners on completion
      s.progress_stack.close_all()
      s.streaming_buffer = ""
      s.streaming_active = false
    }
    StreamChunk(chunk) => {
      s.streaming_buffer = s.streaming_buffer + chunk
      s.streaming_active = true
      s.agent_status = "streaming"
      if is_thinking_active(s) {
        s.thinking_buffer = s.thinking_buffer + chunk
      }
    }
    SessionStarted(id) => {
      s.session_id = id
      s.agent_status = "session_started"
    }
    SessionEnded(_id) => s.agent_status = "session_ended"
    CostUpdated(cost) => s.total_cost = cost
    WarningOccurred(msg) => {
      match s.last_error {
        None => s.last_error = Some(msg)
        _ => ()
      }
      s.agent_status = "warning"
    }
    FileAccessed(path, op) => s.tool_output = "File: \{op} \{path}"
    ThinkingStarted => {
      s.thinking_buffer = ""
      if config.track_phases {
        s.phase_stack.push("thinking")
      }
      ignore(s.progress_stack.push("Thinking..."))
    }
    ThinkingEnded => {
      if config.track_phases && s.phase_stack.length() > 0 {
        ignore(s.phase_stack.pop())
      }
      s.progress_stack.close_last()
    }
    SubagentStarted(name) => {
      if config.track_phases {
        s.phase_stack.push("subagent_\{name}")
      }
      ignore(s.progress_stack.push("Sub-agent: \{name}"))
    }
    SubagentEnded(_name) => {
      if config.track_phases && s.phase_stack.length() > 0 {
        ignore(s.phase_stack.pop())
      }
      s.progress_stack.close_last()
    }
    RetryAttempt(n, reason) => {
      s.agent_status = "retry_\{n}"
      // Close previous retry spinner if any
      if n > 1 {
        s.progress_stack.close_last()
      }
      ignore(s.progress_stack.push("Retry #\{n}: \{reason}"))
    }
  }
}
