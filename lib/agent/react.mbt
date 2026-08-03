///| ReAct conversation loop.

///| Implements the Think → Act → Observe cycle that drives

///| the Agent's autonomous task execution.

///| Reference: openclacky/lib/clacky/agent.rb (run/think/act/observe)

///|

///|
/// Build a session context message for the current run.
fn Agent::build_session_context(self : Agent) -> String {
  let now = current_iso8601()
  let date_part = if now.length() >= 10 { now[:10].to_owned() } else { now }
  let weekday = current_weekday()
  let os = detect_os()
  let wd = self.working_dir
  let model = self.client.model
  "[Session context: Today is \{date_part}, \{weekday}. Current model: \{model}. OS: \{os}. Working directory: \{wd}]"
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
pub async fn Agent::run(self : Agent, user_input : String) -> RunResult {
  // ── 1. Initialize ──────────────────────────────────────────────────
  let old_status = self.status
  self.status = Running
  self.hook_manager.emit(StatusChanged(old_status, Running))
  self.idle_timer.cancel()
  self.error = None
  self.error_code = None
  self.top_up_url = None
  self.raw_message = None
  // Inject system prompt on first run
  if self.history.length() == 0 {
    let system_prompt = self.build_system_prompt()
    self.history.push(stamp_created_at(@message.Message::system(system_prompt)))
    self.hook_manager.emit(MessageAdded)
  }
  // Inject per-run session context
  let ctx_msg : @message.Message = {
    role: @message.User,
    content: @message.Text(self.build_session_context()),
    tool_calls: None,
    tool_call_id: None,
    name: None,
    reasoning_content: None,
    task_id: None,
    created_at: Some(current_time_ms().to_string()),
    system_injected: Some(true),
    memory_update: None,
    subagent_instructions: None,
    subagent_result: None,
    token_usage: None,
    compressed_summary: None,
    transient: None,
  }
  self.history.push(ctx_msg)
  self.hook_manager.emit(MessageAdded)
  // Add user message
  self.history.push(stamp_created_at(@message.Message::user(user_input)))
  self.hook_manager.emit(MessageAdded)
  self.total_tasks = self.total_tasks + 1

  // ── 2. ReAct Loop ──────────────────────────────────────────────────
  let result = self.react_loop_async() catch {
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
  // T17: Auto memory update - extract memorable info from conversation
  self.auto_update_memory() catch {
    _ => ()
  }
  // Start idle timer for automatic compression
  self.idle_timer.start(current_time_ms().to_int())
  // Skill evolution: detect patterns and create/improve skills
  if result.status == Success {
    self.run_skill_evolution_hooks()
  }
  result
}

///|
/// Async entry point: run the ReAct loop without blocking the event loop.
/// Alias for `Agent::run` (kept for existing callers).
pub async fn Agent::run_async(self : Agent, user_input : String) -> RunResult {
  self.run(user_input)
}

///|
/// Internal result of the act phase.
priv struct ActionResult {
  denied : Bool
  feedback : String?
  tool_results : Array[ToolResultEntry]
  awaiting_feedback : Bool
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
    self.history.push(stamp_created_at(msg))
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
  // Check if compression is needed; if so, insert the compression
  // instruction message so the upcoming LLM call produces a summary.
  let compression_ctx = self.compress_messages_if_needed(false)
  let did_insert_compression = match compression_ctx {
    Some(_) => {
      self.history.push(build_compression_message())
      self.hook_manager.emit(MessageAdded)
      true
    }
    None => false
  }
  self.hook_manager.emit(BeforeLlmCall)
  let response = self.call_stream_with_retry_async(fn(chunk) {
    self.hook_manager.emit(StreamChunk(chunk))
  })
  match response.latency {
    Some(lat) => self.latest_latency = Some(lat)
    None => ()
  }
  // If we inserted a compression instruction, the LLM response is a
  // compression summary — process it instead of treating it as a normal
  // assistant turn.
  if did_insert_compression {
    // Remove the compression instruction message we inserted (last msg).
    self.history.pop() |> ignore
    let content = match response.content {
      Some(c) => c
      None => ""
    }
    match compression_ctx {
      Some(ctx) => {
        self.compression_level = self.compression_level + 1
        match compress_with_level_fallback(self.history, content, ctx) {
          Success(_) => {
            // Save archived chunk to disk for future recall.
            let to_archive : Array[@message.Message] = []
            for m in self.history {
              to_archive.push(m)
            }
            match
              save_compressed_chunk(
                to_archive,
                self.session_id,
                self.compression_level,
              ) {
              Ok(_) => ()
              Err(_) => () // chunk save failure is non-fatal
            }
          }
          Failed(_) => self.compression_level = self.compression_level - 1
        }
      }
      None => ()
    }
    self.hook_manager.emit(AfterLlmCall)
    // Return None so the react loop skips tool execution for this pass
    // and starts a fresh think cycle with the compressed history.
    return None
  }
  let content = match response.content {
    Some(c) => c
    None => ""
  }
  let msg = @message.Message::assistant(content)
  msg.tool_calls = response.tool_calls
  msg.reasoning_content = response.reasoning_content
  self.history.push(stamp_created_at(msg))
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
  let mut fake_tool_call_retries = 0
  let mut empty_response_retries = 0
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
                stamp_created_at(
                  @message.Message::assistant(
                    "Response was truncated multiple times. Please break your task into smaller steps.",
                  ),
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
                stamp_created_at(
                  @message.Message::user(
                    "Your previous response was truncated. Please continue from where you left off.",
                  ),
                ),
              )
              self.hook_manager.emit(MessageAdded)
            }
          }
          _ => {
            let has_tool_calls = match resp.tool_calls {
              Some(calls) => calls.length() > 0
              None => false
            }
            if !has_tool_calls {
              let content = match resp.content {
                Some(c) => c
                None => ""
              }
              if content.is_empty() {
                empty_response_retries = empty_response_retries + 1
                if empty_response_retries >= 3 {
                  done = Some(
                    self.build_result(
                      Error,
                      error=Some("Empty response after 3 retries"),
                    ),
                  )
                } else {
                  self.history.push(
                    stamp_created_at(
                      @message.Message::user(
                        "Your response was empty. Please continue with the task.",
                      ),
                    ),
                  )
                  self.hook_manager.emit(MessageAdded)
                }
              } else if fake_tool_call_retries < max_fake_tool_call_retries &&
                detect_fake_tool_call(content) {
                fake_tool_call_retries = fake_tool_call_retries + 1
                self.history.push(
                  stamp_created_at(
                    @message.Message::user(fake_tool_call_correction_prompt),
                  ),
                )
                self.hook_manager.emit(MessageAdded)
              } else {
                match resp.usage {
                  Some(usage) => self.track_cost(usage) |> ignore
                  None => ()
                }
                done = Some(self.build_result(Success))
              }
            } else {
              let tool_calls = resp.tool_calls.unwrap()
              let action_result = self.act_async(tool_calls)
              self.observe(resp, action_result.tool_results)
              if action_result.awaiting_feedback {
                done = Some(self.build_result(Success))
              } else if action_result.denied {
                match action_result.feedback {
                  Some(fb) if fb.length() > 0 => {
                    self.history.push(
                      stamp_created_at(@message.Message::user(fb)),
                    )
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
/// Run skill evolution hooks after a successful run.
/// Detects repeated patterns and creates/improves skills automatically.
fn Agent::run_skill_evolution_hooks(self : Agent) -> Unit {
  match self.config.skill_evolution {
    None => ()
    Some(_) => {
      let engine = @skill.EvolutionEngine::new()
      let history : Array[String] = []
      for msg in self.history {
        match msg.content {
          @message.Text(text) => history.push(text)
          _ => ()
        }
      }
      let scenario = @skill.AutoDetect(
        conversation_history=history,
        iteration_count=self.iterations,
      )
      engine.evolve(scenario) |> ignore
    }
  }
}
