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
  /// Optional output buffer for writing tool/phase entries directly.
  mut output : OutputBuffer?
}

///|
/// Create a new AgentHookHandler.
pub fn AgentHookHandler::new(
  state : Ref[TuiState],
  config? : HookHandlerConfig = default_hook_config(),
  agent? : @agent.Agent? = None,
) -> AgentHookHandler {
  { state, config, agent, output: None }
}

///|
/// Set the output buffer for writing tool/phase entries.
pub fn AgentHookHandler::set_output(
  self : AgentHookHandler,
  output : OutputBuffer,
) -> Unit {
  self.output = Some(output)
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
    dispatch_hook_event(state, config, self.agent, self.output, event)
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
  s.run_start_ts = @env.now().reinterpret_as_int64()
  s.total_iterations = 0
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
  output : OutputBuffer?,
  event : @agent.HookEvent,
) -> Unit {
  let s = state.val
  let theme = s.theme
  match event {
    StatusChanged(_old, new) => s.agent_status.set(new.to_string_value())
    BeforeIteration(n) => {
      s.iterations = n
      s.total_iterations = n
      s.agent_status.set("iterating")
      if config.track_phases {
        push_phase(s, output, theme, "iteration_\{n}")
      }
      s.current_tool_name = ""
      s.current_tool_args = ""
    }
    AfterIteration(n) => {
      s.iterations = n
      s.total_iterations = n
      s.agent_status.set("iteration_done")
      if config.track_phases {
        pop_phase(s, output, theme, "iteration_\{n}")
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
      s.agent_status.set("thinking")
      if config.track_phases {
        push_phase(s, output, theme, "llm_call")
      }
      // Push progress spinner for LLM call (quiet: short calls leave no trace)
      ignore(s.progress_stack.push_quiet("Thinking..."))
    }
    AfterLlmCall => {
      s.llm_calling = false
      s.agent_status.set("llm_done")
      if config.track_phases {
        pop_phase(s, output, theme, "llm_call")
      }
      // Close the LLM spinner
      s.progress_stack.close_last()
      // Finalize streaming buffer
      if s.streaming_buffer.get().length() > 0 {
        s.messages.push("[assistant] \{s.streaming_buffer.get()}")
        s.streaming_buffer.set("")
      }
      s.streaming_active.set(false)
    }
    MessageAdded => s.agent_status.set("message_added")
    ToolExecuting(name, args) => {
      s.current_tool_name = name
      s.current_tool_args = args
      s.tool_output.set("Running: \{name}(\{args})")
      s.agent_status.set("tool_call")
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
      // Time machine: snapshot file content before a write-type tool touches it
      if is_file_write_tool(name) {
        match json_string_field(args, "path") {
          Some(path) => {
            let content : String? = if @fs.path_exists(path) {
              Some(@fs.read_file_to_string(path) catch { _ => "" })
            } else {
              None
            }
            s.time_machine.record_file_before_change(path, content)
          }
          None => ()
        }
      }
      // Push progress spinner for tool execution
      ignore(s.progress_stack.push("Running: \{name}"))
      // Append [=>] tool call entry to output buffer ([C] for shell tools)
      append_tool_call_entry(output, theme, name, args)
    }
    ToolExecuted(name, result) => {
      s.tool_output.set("Completed: \{name}")
      s.current_tool_name = ""
      s.current_tool_args = ""
      s.agent_status.set("tool_done")
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
      // Append [<=] tool result entry to output buffer
      append_tool_result_entry(
        output,
        theme,
        name,
        result.content,
        result.is_error,
      )
    }
    ErrorOccurred(msg) => {
      s.last_error = Some(msg)
      s.agent_status.set("error")
      if config.track_phases {
        while s.phase_stack.length() > 0 {
          ignore(s.phase_stack.pop())
        }
      }
      // Close all spinners on error
      s.progress_stack.close_all()
      s.streaming_buffer.set("")
      s.streaming_active.set(false)
      s.current_tool_name = ""
      s.current_tool_args = ""
    }
    ToolDenied(name) => {
      s.agent_status.set("tool_denied")
      s.current_tool_name = ""
      s.current_tool_args = ""
      // Append [!!] tool denied entry to output buffer
      append_tool_denied_entry(output, theme, name)
    }
    UsageUpdated(data) => {
      s.last_input_tokens = data.prompt_tokens
      s.last_output_tokens = data.completion_tokens
      s.latest_delta = data.delta_tokens
      // Append token stats line to output buffer (only when usage exists)
      append_token_stats(output, theme, data)
    }
    RunCompleted(result) => {
      s.agent_status.set("completed")
      s.total_cost = result.total_cost_usd
      s.iterations = result.iterations
      s.total_iterations = result.iterations
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
      s.streaming_buffer.set("")
      s.streaming_active.set(false)
      // Append completion summary if >5 iterations
      append_run_summary(output, theme, s, result)
    }
    StreamChunk(chunk) => {
      s.streaming_buffer.set(s.streaming_buffer.get() + chunk)
      s.streaming_active.set(true)
      s.agent_status.set("streaming")
      // Update the LLM progress frame with the streamed char count
      s.progress_stack.update_last_char_count(s.streaming_buffer.get().length())
      if is_thinking_active(s) {
        s.thinking_buffer.set(s.thinking_buffer.get() + chunk)
      }
    }
    SessionStarted(id) => {
      s.session_id = id
      s.agent_status.set("session_started")
    }
    SessionEnded(_id) => s.agent_status.set("session_ended")
    CostUpdated(cost) => s.total_cost = cost
    WarningOccurred(msg) => {
      match s.last_error {
        None => s.last_error = Some(msg)
        _ => ()
      }
      s.agent_status.set("warning")
    }
    FileAccessed(path, op) => {
      s.tool_output.set("File: \{op} \{path}")
      // Append [F] file preview entry to output buffer
      append_file_entry(output, theme, path, op)
    }
    ThinkingStarted => {
      s.thinking_buffer.set("")
      if config.track_phases {
        push_phase(s, output, theme, "thinking")
      }
      ignore(s.progress_stack.push("Thinking..."))
    }
    ThinkingEnded => {
      if config.track_phases {
        pop_phase(s, output, theme, "thinking")
      }
      s.progress_stack.close_last()
    }
    SubagentStarted(name) => {
      if config.track_phases {
        push_phase(s, output, theme, "subagent_\{name}")
      }
      ignore(s.progress_stack.push("Sub-agent: \{name}"))
    }
    SubagentEnded(name) => {
      if config.track_phases {
        pop_phase(s, output, theme, "subagent_\{name}")
      }
      s.progress_stack.close_last()
    }
    RetryAttempt(n, reason) => {
      s.agent_status.set("retry_\\{n}")
      // Close previous retry spinner if any
      if n > 1 {
        s.progress_stack.close_last()
      }
      ignore(s.progress_stack.push("Retry #\{n}: \{reason}"))
    }
    ToolStdout(text) =>
      // Tool stdout output - append to output buffer
      append_tool_stdout(output, theme, text)
    InfoMessage(msg) =>
      // Informational message - append to output buffer
      append_info_message(output, theme, msg)
    SuccessMessage(msg) =>
      // Success message - append to output buffer
      append_success_message(output, theme, msg)
    FeedbackRequested(question, _context, _options) =>
      // Feedback requested - append to output buffer
      append_feedback_requested(output, theme, question)
  }
}

// ── Output Buffer Helper Functions ────────────────────────────────────

///|
/// Push a phase onto the stack and emit an enter banner only for
/// top-level phases (nested phases stay silent to avoid banner spam).
fn push_phase(
  s : TuiState,
  output : OutputBuffer?,
  theme : Theme,
  name : String,
) -> Unit {
  let top_level = s.phase_stack.length() == 0
  s.phase_stack.push(name)
  if top_level {
    append_phase_banner(output, theme, true, name)
  }
}

///|
/// Pop the top phase when it matches `expected` (stack-top validation);
/// emit an exit banner only when the stack becomes empty (top-level pop).
fn pop_phase(
  s : TuiState,
  output : OutputBuffer?,
  theme : Theme,
  expected : String,
) -> Unit {
  match s.phase_stack.last() {
    Some(top) =>
      if top == expected {
        ignore(s.phase_stack.pop())
        if s.phase_stack.length() == 0 {
          append_phase_banner(output, theme, false, top)
        }
      }
    None => ()
  }
}

///|
/// Truncate text to a maximum number of characters (char-safe: never
/// splits a surrogate pair / multi-unit character).
fn truncate_preview(text : String, max_len : Int) -> String {
  let buf = StringBuilder()
  let mut count = 0
  let mut truncated = false
  for c in text {
    if count >= max_len {
      truncated = true
      break
    }
    buf.write_char(c)
    count = count + 1
  }
  if truncated {
    buf.write_string("...")
  }
  buf.to_string()
}

///|
/// Whether the tool is a shell-command execution tool.
fn is_shell_tool(name : String) -> Bool {
  name == "terminal" || name == "bash" || name == "shell"
}

///|
/// Whether the tool modifies file contents (for time-machine snapshots).
fn is_file_write_tool(name : String) -> Bool {
  name == "write" ||
  name == "edit" ||
  name == "write_file" ||
  name == "file_edit" ||
  name == "create_file" ||
  name == "patch"
}

///|
/// Extract a string field from a JSON object text; None on any mismatch.
fn json_string_field(json_text : String, key : String) -> String? {
  let parsed = @json.parse(json_text) catch { _ => return None }
  match parsed {
    Object(obj) =>
      match obj.get(key) {
        Some(String(s)) => Some(s)
        _ => None
      }
    _ => None
  }
}

///|
/// Append a tool call entry: `[=>] tool_name(args_preview)`, or a shell
/// command preview `[C] command` for shell-type tools.
fn append_tool_call_entry(
  output : OutputBuffer?,
  theme : Theme,
  name : String,
  args : String,
) -> Unit {
  match output {
    Some(buf) =>
      if is_shell_tool(name) {
        let cmd = match json_string_field(args, "command") {
          Some(c) => c
          None => args
        }
        let entry = "\{theme.shell_preview_symbol} \{truncate_preview(cmd, 80)}"
        ignore(buf.append_text(entry, OutputKind::System))
      } else {
        let preview = truncate_preview(args, 80)
        let entry = "\{theme.tool_call_symbol} \{name}(\{preview})"
        ignore(buf.append_text(entry, OutputKind::System))
      }
    None => ()
  }
}

///|
/// Append a tool result entry: `[<=] tool_name result_preview`.
fn append_tool_result_entry(
  output : OutputBuffer?,
  theme : Theme,
  name : String,
  result_content : String,
  is_error : Bool,
) -> Unit {
  match output {
    Some(buf) => {
      let preview = truncate_preview(result_content, 200)
      let status = if is_error { "error" } else { "ok" }
      let entry = "\{theme.tool_result_symbol} \{name} [\{status}] \{preview}"
      ignore(buf.append_text(entry, OutputKind::System))
    }
    None => ()
  }
}

///|
/// Append a tool denied entry: `[!!] tool_name denied`.
fn append_tool_denied_entry(
  output : OutputBuffer?,
  theme : Theme,
  name : String,
) -> Unit {
  match output {
    Some(buf) => {
      let entry = "\{theme.tool_denied_symbol} \{name} denied"
      ignore(buf.append_text(entry, OutputKind::System))
    }
    None => ()
  }
}

///|
/// Append a file access entry: `[F] op path`.
fn append_file_entry(
  output : OutputBuffer?,
  theme : Theme,
  path : String,
  op : String,
) -> Unit {
  match output {
    Some(buf) => {
      let entry = "\{theme.file_preview_symbol} \{op} \{path}"
      ignore(buf.append_text(entry, OutputKind::System))
    }
    None => ()
  }
}

///|
/// Append a token stats line after an LLM call with real usage data.
/// Format per spec tui-parity-04 decision 3:
/// `[Tokens] +delta | cached | Input: N | Output: N | Total: N | Cost: $x`
fn append_token_stats(
  output : OutputBuffer?,
  theme : Theme,
  data : @agent.IterationTokenData,
) -> Unit {
  match output {
    Some(buf) => {
      let entry = "\{theme.dim_color}[Tokens] +\{data.delta_tokens} | cached: \{data.cache_read} | Input: \{data.prompt_tokens} | Output: \{data.completion_tokens} | Total: \{data.total_tokens} | Cost: $\{format_cost(data.cost)}\u001b[0m"
      ignore(buf.append_text(entry, OutputKind::System))
    }
    None => ()
  }
}

///|
/// Append a phase banner: `▼ phase_name` or `▲ phase_name`.
fn append_phase_banner(
  output : OutputBuffer?,
  theme : Theme,
  enter : Bool,
  phase_name : String,
) -> Unit {
  match output {
    Some(buf) => {
      let symbol = if enter {
        theme.phase_enter_symbol
      } else {
        theme.phase_exit_symbol
      }
      let entry = "\{theme.dim_color}\{symbol} \{phase_name}\u001b[0m"
      ignore(buf.append_text(entry, OutputKind::System))
    }
    None => ()
  }
}

///|
/// Append a run completion summary (only when >5 iterations).
fn append_run_summary(
  output : OutputBuffer?,
  theme : Theme,
  s : TuiState,
  result : @agent.RunResult,
) -> Unit {
  if result.iterations <= 5 {
    return
  }
  match output {
    Some(buf) => {
      let cost_str = format_cost(result.total_cost_usd)
      let now_ms = @env.now().reinterpret_as_int64()
      let duration_sec = ((now_ms - s.run_start_ts) / 1000L).to_int()
      let entry = "\{theme.dim_color}[Summary] \{result.iterations} iterations | $\{cost_str} | \{duration_sec}s\u001b[0m"
      ignore(buf.append_text(entry, OutputKind::System))
    }
    None => ()
  }
}

///|
/// Append a tool stdout entry.
fn append_tool_stdout(
  output : OutputBuffer?,
  theme : Theme,
  text : String,
) -> Unit {
  match output {
    Some(buf) => {
      let entry = "\{theme.dim_color}\{text}\u001b[0m"
      ignore(buf.append_text(entry, OutputKind::System))
    }
    None => ()
  }
}

///|
/// Append an informational message.
fn append_info_message(
  output : OutputBuffer?,
  theme : Theme,
  msg : String,
) -> Unit {
  match output {
    Some(buf) => {
      let entry = "\{theme.dim_color}[Info] \{msg}\u001b[0m"
      ignore(buf.append_text(entry, OutputKind::System))
    }
    None => ()
  }
}

///|
/// Append a success message.
fn append_success_message(
  output : OutputBuffer?,
  theme : Theme,
  msg : String,
) -> Unit {
  match output {
    Some(buf) => {
      let entry = "\{theme.tool_denied_symbol} \{msg}"
      ignore(buf.append_text(entry, OutputKind::System))
    }
    None => ()
  }
}

///|
/// Append a feedback requested entry.
fn append_feedback_requested(
  output : OutputBuffer?,
  theme : Theme,
  question : String,
) -> Unit {
  match output {
    Some(buf) => {
      let entry = "\{theme.dim_color}[?] \{question}\u001b[0m"
      ignore(buf.append_text(entry, OutputKind::System))
    }
    None => ()
  }
}
