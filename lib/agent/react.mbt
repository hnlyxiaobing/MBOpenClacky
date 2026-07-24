///| ReAct conversation loop.

///| Implements the Think → Act → Observe cycle that drives

///| the Agent's autonomous task execution.

///| Reference: openclacky/lib/clacky/agent.rb (run/think/act/observe)

///|

///|
/// Internal result of the act phase.
priv struct ActionResult {
  denied : Bool
  feedback : String?
  tool_results : Array[ToolResultEntry]
  awaiting_feedback : Bool
}

///|
/// Run the Agent's ReAct conversation loop.
///
/// This is the main entry point for autonomous task execution:
/// 1. Initialize: set status, inject system prompt (first run), add user message
/// 2. Loop: think → act → observe until no more tool calls
/// 3. Finalize: build result, update status
///
/// Raises AgentInterrupted on user interruption (Ctrl+C).
/// Raises AgentError on unrecoverable errors.
pub fn Agent::run(self : Agent, user_input : String) -> RunResult raise {
  // ── 1. Initialize ──────────────────────────────────────────────────
  let old_status = self.status
  self.status = Running
  self.hook_manager.emit(StatusChanged(old_status, Running))
  self.error = None
  self.error_code = None
  self.top_up_url = None
  self.raw_message = None
  // Inject system prompt on first run
  if self.history.length() == 0 {
    let system_prompt = self.build_system_prompt()
    self.history.push(@message.Message::system(system_prompt))
    self.hook_manager.emit(MessageAdded)
  }
  // Add user message
  self.history.push(@message.Message::user(user_input))
  self.hook_manager.emit(MessageAdded)
  self.total_tasks = self.total_tasks + 1

  // ── 2. ReAct Loop ──────────────────────────────────────────────────
  let result = self.react_loop() catch {
    err => {
      self.status = Error
      let err_msg = @errors.error_message(err)
      self.error = Some(err_msg)
      self.hook_manager.emit(ErrorOccurred(err_msg))
      raise @errors.AgentError(err_msg)
    }
  }

  // ── 3. Finalize ────────────────────────────────────────────────────
  let completed_status = self.status
  self.status = Completed
  self.hook_manager.emit(StatusChanged(completed_status, Completed))
  self.hook_manager.emit(RunCompleted(result))
  result
}

///|
/// Internal ReAct loop using functional for loop.
fn Agent::react_loop(self : Agent) -> RunResult raise {
  // We use a mutable truncation counter and a simple while-style loop.
  let mut truncation_count = 0
  let mut done : RunResult? = None

  while done is None {
    self.iterations = self.iterations + 1
    self.hook_manager.emit(BeforeIteration(self.iterations))

    // ── THINK ────────────────────────────────────────────────────────
    let response = self.think()

    match response {
      None =>
        // Compression occurred — continue loop
        ()
      Some(resp) =>
        // Check for truncation
        match resp.finish_reason {
          Some("length") => {
            truncation_count = truncation_count + 1
            if truncation_count >= 3 {
              self.history.push(
                @message.Message::assistant(
                  "Response was truncated multiple times. Please break your task into smaller steps.",
                ),
              )
              self.hook_manager.emit(MessageAdded)
              done = Some(
                self.build_result(
                  Error,
                  error=Some("Repeated response truncation"),
                ),
              )
            } else {
              self.history.push(
                @message.Message::user(
                  "Your previous response was truncated. Please continue from where you left off, or break the task into smaller steps.",
                ),
              )
              self.hook_manager.emit(MessageAdded)
            }
          }
          _ => {
            // Reset truncation counter on normal response
            truncation_count = 0

            // Check if there are tool calls
            let has_tool_calls = match resp.tool_calls {
              Some(calls) => calls.length() > 0
              None => false
            }

            if !has_tool_calls {
              // No tool calls — final response, build result and exit
              match resp.usage {
                Some(usage) => self.track_cost(usage) |> ignore
                None => ()
              }
              done = Some(self.build_result(Success))
            } else {
              // Has tool calls — execute them
              let tool_calls = resp.tool_calls.unwrap()
              let action_result = self.act(tool_calls)

              // OBSERVE: inject tool results
              self.observe(resp, action_result.tool_results)

              // Handle denial / feedback
              if action_result.awaiting_feedback {
                done = Some(self.build_result(Success))
              } else if action_result.denied {
                match action_result.feedback {
                  Some(fb) if fb.length() > 0 => {
                    // Inject user feedback and continue
                    self.history.push(@message.Message::user(fb))
                    self.hook_manager.emit(MessageAdded)
                  }
                  _ =>
                    // Denied without feedback — stop
                    done = Some(self.build_result(Success))
                }
              }
            }
          }
        }
    }
    // Emit AfterIteration at end of each loop body
    self.hook_manager.emit(AfterIteration(self.iterations))
  }

  // Unwrap: loop exits only when done is Some
  match done {
    Some(r) => r
    None => self.build_result(Success) // unreachable but needed for type checker
  }
}

///|
/// THINK phase: call the LLM and return the response.
///
/// Returns None if compression was triggered (caller should retry).
/// Returns Some(response) with the LLM's response otherwise.
fn Agent::think(self : Agent) -> @client.LlmResponse? raise {
  // Check if compression is needed
  match self.compress_messages_if_needed(false) {
    Some(_) =>
      // Phase 4: compression detected but not executed.
      // In Phase 5+ this would trigger an LLM compression call.
      ()
    None => ()
  }

  // Call the LLM
  self.hook_manager.emit(BeforeLlmCall)
  let response = self.call_llm()

  // Update latency
  match response.latency {
    Some(lat) => self.latest_latency = Some(lat)
    None => ()
  }

  // Add assistant message to history (with tool_calls if present)
  let content = match response.content {
    Some(c) => c
    None => ""
  }
  let msg = @message.Message::assistant(content)
  msg.tool_calls = response.tool_calls
  self.history.push(msg)
  self.hook_manager.emit(MessageAdded)
  self.hook_manager.emit(AfterLlmCall)

  Some(response)
}

///|
/// ACT phase: execute tool calls and collect results.
fn Agent::act(
  self : Agent,
  tool_calls : Array[@message.ToolCall],
) -> ActionResult {
  let results : Array[ToolResultEntry] = []
  let mut denied = false
  let feedback : String? = None
  let awaiting_feedback = false

  for call in tool_calls {
    if denied {
      // Skip remaining tools after a denial
      break
    }
    let tool_name = call.function.name

    // Permission check
    let args = parse_tool_arguments(call)
    if !self.should_auto_execute(tool_name, args) {
      // Tool needs confirmation
      let approved = match self.confirmation_callback {
        Some(cb) => {
          let args_summary = call.function.arguments
          cb(tool_name, args_summary)
        }
        None => false // Headless: deny tools needing confirmation
      }
      if approved {
        // User approved — execute the tool
        let args_json = call.function.arguments
        self.hook_manager.emit(ToolExecuting(tool_name, args_json))
        let entry = self.execute_single_tool(call)
        self.hook_manager.emit(ToolExecuted(tool_name, entry))
        results.push(entry)
      } else {
        let entry = build_denied_result(call, None)
        self.hook_manager.emit(ToolDenied(tool_name))
        results.push(entry)
        denied = true
      }
    } else {
      // Emit hook before execution
      let args_json = call.function.arguments
      self.hook_manager.emit(ToolExecuting(tool_name, args_json))
      // Execute the tool
      let entry = self.execute_single_tool(call)
      self.hook_manager.emit(ToolExecuted(tool_name, entry))
      results.push(entry)
    }
  }

  { denied, feedback, tool_results: results, awaiting_feedback }
}

///|
/// OBSERVE phase: inject tool results into conversation history.
///
/// Uses client.format_tool_results to produce protocol-correct
/// tool result messages (Anthropic vs OpenAI format).
fn Agent::observe(
  self : Agent,
  response : @client.LlmResponse,
  tool_results : Array[ToolResultEntry],
) -> Unit {
  // Build the map expected by format_tool_results
  let results_map : Map[String, String] = Map([])
  for entry in tool_results {
    results_map[entry.id] = entry.content
  }
  // Format into protocol-specific messages
  let formatted = self.client.format_tool_results(response, results_map)
  for msg in formatted {
    self.history.push(msg)
    self.hook_manager.emit(MessageAdded)
  }
}

// ═══════════════════════════════════════════════════════════════════
// ASYNC VARIANTS (for TUI interactive mode - non-blocking HTTP)
// ═══════════════════════════════════════════════════════════════════

///|
/// THINK phase (async): call the LLM via non-blocking HTTP, streaming
/// content deltas to the UI as StreamChunk hook events.
async fn Agent::think_async(self : Agent) -> @client.LlmResponse? {
  match self.compress_messages_if_needed(false) {
    Some(_) => ()
    None => ()
  }
  self.hook_manager.emit(BeforeLlmCall)
  let response = self.call_llm_stream_async(fn(chunk) {
    self.hook_manager.emit(StreamChunk(chunk))
  })
  match response.latency {
    Some(lat) => self.latest_latency = Some(lat)
    None => ()
  }
  let content = match response.content {
    Some(c) => c
    None => ""
  }
  let msg = @message.Message::assistant(content)
  msg.tool_calls = response.tool_calls
  self.history.push(msg)
  self.hook_manager.emit(MessageAdded)
  self.hook_manager.emit(AfterLlmCall)
  Some(response)
}

///|
/// ACT phase (async): execute tool calls with async confirmation.
async fn Agent::act_async(
  self : Agent,
  tool_calls : Array[@message.ToolCall],
) -> ActionResult {
  let results : Array[ToolResultEntry] = []
  let mut denied = false
  let feedback : String? = None
  let awaiting_feedback = false

  for call in tool_calls {
    if denied {
      break
    }
    let tool_name = call.function.name
    let args = parse_tool_arguments(call)
    if !self.should_auto_execute(tool_name, args) {
      // Tool needs confirmation - use async queue if available
      let approved = match self.confirmation_request {
        Some(req_q) =>
          match self.confirmation_response {
            Some(resp_q) => {
              req_q.put((tool_name, call.function.arguments))
              resp_q.get()
            }
            None => false
          }
        None =>
          // Fallback to sync callback (non-interactive mode)
          match self.confirmation_callback {
            Some(cb) => cb(tool_name, call.function.arguments)
            None => false
          }
      }
      if approved {
        let args_json = call.function.arguments
        self.hook_manager.emit(ToolExecuting(tool_name, args_json))
        let entry = self.execute_single_tool(call)
        self.hook_manager.emit(ToolExecuted(tool_name, entry))
        results.push(entry)
      } else {
        let entry = build_denied_result(call, None)
        self.hook_manager.emit(ToolDenied(tool_name))
        results.push(entry)
        denied = true
      }
    } else {
      let args_json = call.function.arguments
      self.hook_manager.emit(ToolExecuting(tool_name, args_json))
      let entry = self.execute_single_tool(call)
      self.hook_manager.emit(ToolExecuted(tool_name, entry))
      results.push(entry)
    }
  }
  { denied, feedback, tool_results: results, awaiting_feedback }
}

///|
/// Internal async ReAct loop.
async fn Agent::react_loop_async(self : Agent) -> RunResult {
  let mut truncation_count = 0
  let mut done : RunResult? = None
  while done is None {
    self.iterations = self.iterations + 1
    self.hook_manager.emit(BeforeIteration(self.iterations))
    let response = self.think_async()
    match response {
      None => ()
      Some(resp) =>
        match resp.finish_reason {
          Some("length") => {
            truncation_count = truncation_count + 1
            if truncation_count >= 3 {
              self.history.push(
                @message.Message::assistant(
                  "Response was truncated multiple times. Please break your task into smaller steps.",
                ),
              )
              self.hook_manager.emit(MessageAdded)
              done = Some(
                self.build_result(
                  Error,
                  error=Some("Repeated response truncation"),
                ),
              )
            } else {
              self.history.push(
                @message.Message::user(
                  "Your previous response was truncated. Please continue from where you left off.",
                ),
              )
              self.hook_manager.emit(MessageAdded)
            }
          }
          _ => {
            truncation_count = 0
            let has_tool_calls = match resp.tool_calls {
              Some(calls) => calls.length() > 0
              None => false
            }
            if !has_tool_calls {
              match resp.usage {
                Some(usage) => self.track_cost(usage) |> ignore
                None => ()
              }
              done = Some(self.build_result(Success))
            } else {
              let tool_calls = resp.tool_calls.unwrap()
              let action_result = self.act_async(tool_calls)
              self.observe(resp, action_result.tool_results)
              if action_result.awaiting_feedback {
                done = Some(self.build_result(Success))
              } else if action_result.denied {
                match action_result.feedback {
                  Some(fb) if fb.length() > 0 => {
                    self.history.push(@message.Message::user(fb))
                    self.hook_manager.emit(MessageAdded)
                  }
                  _ => done = Some(self.build_result(Success))
                }
              }
            }
          }
        }
    }
    self.hook_manager.emit(AfterIteration(self.iterations))
  }
  match done {
    Some(r) => r
    None => self.build_result(Success)
  }
}

///|
/// Async entry point: run the ReAct loop without blocking the event loop.
/// Uses call_llm_async (C thread HTTP offloading) for non-blocking I/O.
pub async fn Agent::run_async(self : Agent, user_input : String) -> RunResult {
  let old_status = self.status
  self.status = Running
  self.hook_manager.emit(StatusChanged(old_status, Running))
  self.error = None
  self.error_code = None
  self.top_up_url = None
  self.raw_message = None
  if self.history.length() == 0 {
    let system_prompt = self.build_system_prompt()
    self.history.push(@message.Message::system(system_prompt))
    self.hook_manager.emit(MessageAdded)
  }
  self.history.push(@message.Message::user(user_input))
  self.hook_manager.emit(MessageAdded)
  self.total_tasks = self.total_tasks + 1
  let result = self.react_loop_async() catch {
    err => {
      self.status = Error
      let err_msg = @errors.error_message(err)
      self.error = Some(err_msg)
      self.hook_manager.emit(ErrorOccurred(err_msg))
      raise @errors.AgentError(err_msg)
    }
  }
  let completed_status = self.status
  self.status = Completed
  self.hook_manager.emit(StatusChanged(completed_status, Completed))
  self.hook_manager.emit(RunCompleted(result))
  result
}
