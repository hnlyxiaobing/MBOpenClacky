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
  // Per-task one-shot state: the [SYSTEM] truncation hint may be injected
  // at most once per task (mirrors Ruby's @task_upstream_truncation_hint_injected).
  self.upstream_truncation_hint_injected = false
  self.top_up_url = None
  self.raw_message = None
  // Inject system prompt on first run
  if self.history.size() == 0 {
    let system_prompt = self.build_system_prompt()
    self.history.append(
      stamp_created_at(@message.Message::system(system_prompt)),
    )
    self.hook_manager.emit(MessageAdded)
  }
  // Inject per-run session context.
  // NOTE: `created_at` is intentionally left None. The context message is an
  // injected artifact, not a real user message: stamping it with the current
  // ms would collide with the user message pushed right after (same
  // millisecond), and the Web UI's history dedup keys on created_at — two
  // history_user_message events with an identical timestamp would cause the
  // real user message to be skipped and its assistant reply hidden.
  let ctx_msg : @message.Message = {
    role: @message.User,
    content: @message.Text(self.build_session_context()),
    tool_calls: None,
    tool_call_id: None,
    name: None,
    reasoning_content: None,
    task_id: None,
    created_at: None,
    system_injected: Some(true),
    memory_update: None,
    subagent_instructions: None,
    subagent_result: None,
    token_usage: None,
    compressed_summary: None,
    transient: None,
  }
  self.history.append(ctx_msg)
  self.hook_manager.emit(MessageAdded)
  // Add user message
  self.history.append(stamp_created_at(@message.Message::user(user_input)))
  self.hook_manager.emit(MessageAdded)
  self.total_tasks = self.total_tasks + 1

  // ── 2. ReAct Loop ──────────────────────────────────────────────────
  let result = self.react_loop_async() catch {
    err => {
      self.status = Error
      let err_msg = @errors.error_message(err)
      self.error = Some(err_msg)
      // B7 decision 4: 400-class failures poison the conversation (e.g.
      // dangling tool_calls or a rejected message), so flag the session
      // for deferred rollback. Mirrors Ruby's @pending_error_rollback
      // (set by restore_session, consumed at the next run start); the
      // data layer + recovery chain live in B5 (to_session_data /
      // restore_from_session → apply_error_rollback).
      match err {
        @errors.BadRequestError(_, _) => self.pending_error_rollback = true
        _ => ()
      }
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
/// Auto-reply hint appended when request_user_feedback runs without any
/// interactive feedback channel (non-interactive mode). Aligned with the
/// Ruby `@ui.nil?` path in agent.rb which merges `auto_reply` into the
/// tool result so the LLM makes a reasonable decision and continues.
let feedback_auto_reply_hint = "\n\n[auto_reply] No user is available. Please make a reasonable decision based on the context and continue."

///|
/// Extract (question, context, options) from request_user_feedback args.
fn extract_feedback_args(
  args : Map[String, Json],
) -> (String, String?, Array[String]?) {
  let question = match args.get("question") {
    Some(String(q)) => q
    _ => ""
  }
  let context = match args.get("context") {
    Some(String(c)) => Some(c)
    _ => None
  }
  let options = match args.get("options") {
    Some(Array(arr)) => {
      let opts : Array[String] = []
      for item in arr {
        match item {
          String(s) => opts.push(s)
          _ => ()
        }
      }
      Some(opts)
    }
    _ => None
  }
  (question, context, options)
}

///|
/// Post-execution handling for `request_user_feedback` (Ruby agent.rb
/// L1299-1331): render the question via the FeedbackRequested hook, then
/// wait for a reply through the wired feedback channel.
///
/// Returns `(entry, feedback?, awaiting)`:
/// - `entry`   : tool result, possibly extended with the auto-reply hint
/// - `feedback`: the user's answer (non-empty) to feed back to the LLM
/// - `awaiting`: true when the run must suspend (user reply timed out or
///   was empty — Ruby confirm_all waiting path)
///
/// With no feedback channel wired (headless), the auto-reply hint is
/// appended so the LLM can proceed (Ruby `@ui.nil?` path).
async fn Agent::handle_feedback_tool(
  self : Agent,
  tool_name : String,
  entry : ToolResultEntry,
  args : Map[String, Json],
) -> (ToolResultEntry, String?, Bool) {
  if tool_name != "request_user_feedback" || entry.is_error {
    return (entry, None, false)
  }
  let (question, context, options) = extract_feedback_args(args)
  self.hook_manager.emit(FeedbackRequested(question, context, options))
  let (fb, aw) = match self.feedback_request {
    Some(req_q) =>
      match self.feedback_response {
        Some(resp_q) => {
          req_q.put((question, context, options))
          let reply = resp_q.get()
          if reply.length() > 0 {
            // User answered: route the reply back to the LLM immediately
            // (Ruby countdown String path → denied+feedback).
            (Some(reply), false)
          } else {
            // Timed out / empty reply: suspend the run; the user's next
            // message resumes it.
            (None, true)
          }
        }
        None => (None, false)
      }
    None => (None, false)
  }
  if fb is None && !aw {
    let entry = {
      id: entry.id,
      content: entry.content + feedback_auto_reply_hint,
      is_error: entry.is_error,
      image_inject: entry.image_inject,
    }
    (entry, None, false)
  } else {
    (entry, fb, aw)
  }
}

///|
/// OBSERVE phase: inject tool results into conversation history.
///
/// Uses client.format_tool_results to produce protocol-correct
/// tool result messages (Anthropic vs OpenAI format), then appends a
/// follow-up `role:"user"` message for any image payloads that could not
/// be delivered inside the tool message.
///
/// Background (Ruby `Agent#observe`): OpenAI-compatible APIs only accept
/// image_url content blocks in `role:"user"` messages. Putting base64
/// data in a `role:"tool"` message causes it to be JSON-encoded as plain
/// text, inflating token counts by 20-40x. The tool result carries a
/// plain-text description for the LLM; the actual image is delivered
/// here as a data URL.
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
    self.history.append(stamp_created_at(msg))
    self.hook_manager.emit(MessageAdded)
  }
  // Append a follow-up `role:"user"` message for image payloads.
  let vision_supported = self.client.vision_supported
  for entry in tool_results {
    match entry.image_inject {
      None => ()
      Some(inject) => {
        let data_url = "data:\{inject.mime_type};base64,\{inject.base64_data}"
        let label = match inject.path {
          Some(p) => {
            let segs = p.split("/").collect()
            if segs.length() > 0 {
              segs[segs.length() - 1]
            } else {
              "image"
            }
          }
          None => "image"
        }
        let blocks : Array[@message.ContentBlock] = if vision_supported {
          [
            @message.ContentBlock::Text({ text: "[Image: \{label}]" }),
            @message.ContentBlock::Image({ url: data_url, detail: None }),
          ]
        } else {
          // No vision support: keep a plain-text placeholder so the model
          // still knows an image was captured. (Ruby falls back to OCR
          // here — not yet ported.)
          let suffix = match inject.path {
            Some(p) => " (saved at \{p})"
            None => ""
          }
          [@message.ContentBlock::Text({ text: "[Image: \{label}]\{suffix}" })]
        }
        let msg = @message.Message::user_blocks(blocks)
        self.history.append(stamp_created_at(msg))
        self.hook_manager.emit(MessageAdded)
      }
    }
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
      self.history.append(build_compression_message())
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
    self.history.pop_last() |> ignore
    let content = match response.content {
      Some(c) => c
      None => ""
    }
    match compression_ctx {
      Some(ctx) => {
        self.compression_level = self.compression_level + 1
        match compress_with_level_fallback(self.history.all(), content, ctx) {
          Success(_) => {
            // Save archived chunk to disk for future recall.
            let to_archive : Array[@message.Message] = []
            for m in self.history.all() {
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
            // Reset previous_total_tokens to the compressed history's
            // estimated size so the next think() does not immediately
            // re-trigger compression (Ruby handle_compression_response).
            self.previous_total_tokens = estimate_history_tokens(
              self.history.all(),
            )
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
  self.history.append(stamp_created_at(msg))
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
  let mut feedback : String? = None
  let mut awaiting_feedback = false

  for call in tool_calls {
    if denied {
      // Ruby semantics: once a call is denied, auto-deny every remaining
      // tool_use in this assistant message so each one has a paired
      // tool_result (protocol invariant for Anthropic/OpenAI).
      let entry = build_denied_result(
        call,
        Some("Auto-denied due to user rejection of previous tool"),
      )
      self.hook_manager.emit(ToolDenied(call.function.name))
      results.push(entry)
      continue
    }
    // Resolve the canonical name BEFORE permission checks so aliases and
    // case variants (e.g. "Write", "EDIT") cannot bypass confirmation.
    let tool_name = match self.tool_registry.resolve(call.function.name) {
      Some(name) => name
      None => call.function.name
    }
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
        let (entry2, fb, aw) = self.handle_feedback_tool(tool_name, entry, args)
        match fb {
          Some(text) => feedback = Some(text)
          None => ()
        }
        if aw {
          awaiting_feedback = true
        }
        results.push(entry2)
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
      let (entry2, fb, aw) = self.handle_feedback_tool(tool_name, entry, args)
      match fb {
        Some(text) => feedback = Some(text)
        None => ()
      }
      if aw {
        awaiting_feedback = true
      }
      results.push(entry2)
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
    // B7 decision 6: max_iterations ceiling (MB superset — Ruby has none).
    // Protects against runaway loops; a generous multiple of observed
    // real-world task lengths so legitimate long tasks are never hit.
    if self.iterations > MAX_ITERATIONS {
      done = Some(
        self.build_result(
          Error,
          error=Some(
            "Task exceeded the maximum of \{MAX_ITERATIONS} iterations. Stopping.",
          ),
        ),
      )
      break
    }
    self.hook_manager.emit(BeforeIteration(self.iterations))
    let response = self.think_async()
    match response {
      None => ()
      Some(resp) =>
        match resp.finish_reason {
          Some("length") => {
            truncation_count = truncation_count + 1
            if truncation_count >= 3 {
              // Ruby agent.rb think: too many truncations — apologize and end
              // the task normally (Success), instead of killing it with Error.
              // The message appears in the conversation so the user sees why.
              let apology = "I apologize, but this task is too complex to complete in a single response. " +
                "Please break it down into smaller steps, or reduce the amount of content to generate at once.\n\n" +
                "For example, when creating a long document:\n" +
                "1. First create the file with a basic structure\n" +
                "2. Then use edit() to add content section by section"
              self.history.append(
                stamp_created_at(@message.Message::assistant(apology)),
              )
              self.hook_manager.emit(MessageAdded)
              done = Some(self.build_result(Success))
            } else {
              // Drop the truncated assistant message that think_async just
              // appended (its tool_calls are dangling — protocol poison that
              // would 400 the next request), then re-append it text-only so
              // the model sees what it attempted (Ruby truncated_msg).
              // The last history entry is guaranteed to be that assistant
              // message: think_async appends it before returning Some, and
              // the compression path returns None instead.
              self.history.pop_last() |> ignore
              let truncated_text = match resp.content {
                Some(c) => if c.trim().is_empty() { "..." } else { c }
                None => "..."
              }
              let truncated_msg = @message.Message::assistant(truncated_text)
              truncated_msg.reasoning_content = resp.reasoning_content
              self.history.append(stamp_created_at(truncated_msg))
              self.hook_manager.emit(MessageAdded)
              // Insert the detailed [SYSTEM] continuation hint (Ruby
              // agent.rb think truncated branch) so the model retries with
              // smaller steps instead of re-triggering length again.
              let max_tokens = self.config.max_tokens
              self.history.append(
                stamp_created_at(
                  @message.Message::user(
                    "[SYSTEM] Your previous response was truncated because it exceeded the output token limit (max_tokens=\{max_tokens}). " +
                    "The incomplete tool call has been discarded. Please retry with a different approach:\n" +
                    "- For long file content: create the file with a basic structure first, then use edit() to add content section by section\n" +
                    "- Break down large tasks into multiple smaller tool calls\n" +
                    "- Keep each tool call argument under 2000 characters\n" +
                    "- Use multiple tool calls instead of one large call",
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
                // Defense-in-depth fallback: empty responses are already
                // intercepted in llm_caller (check_empty_response raises
                // RetryableError → 10-retry pipeline). Reaching this branch
                // means the mock path bypassed the check; keep a bounded
                // fallback so the loop can never spin forever.
                empty_response_retries = empty_response_retries + 1
                if empty_response_retries >= 3 {
                  done = Some(
                    self.build_result(
                      Error,
                      error=Some("Empty response after 3 retries"),
                    ),
                  )
                } else {
                  self.history.append(
                    stamp_created_at(
                      @message.Message::user(
                        "Your response was empty. Please continue with the task.",
                      ),
                    ),
                  )
                  self.hook_manager.emit(MessageAdded)
                }
              } else if detect_fake_tool_call(content) {
                fake_tool_call_retries = fake_tool_call_retries + 1
                if fake_tool_call_retries > max_fake_tool_call_retries {
                  // Ruby fake_tool_call_detector.rb: over-limit → :stop.
                  // Keep the fake content visible as an assistant message
                  // (Ruby emit_assistant_message), then fail the run with a
                  // clear error instead of silently returning the XML text
                  // as the final answer (previous Success behavior).
                  self.history.append(
                    stamp_created_at(@message.Message::assistant(content)),
                  )
                  self.hook_manager.emit(MessageAdded)
                  done = Some(
                    self.build_result(
                      Error,
                      error=Some(
                        "Model repeatedly emitted text-formatted tool calls instead of using the tool_calls API. Stopping.",
                      ),
                    ),
                  )
                } else {
                  self.history.append(
                    stamp_created_at(
                      @message.Message::user(fake_tool_call_correction_prompt),
                    ),
                  )
                  self.hook_manager.emit(MessageAdded)
                }
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
              // Deferred skill injections (invoke_skill tool) are flushed
              // AFTER observe() so the toolResult is appended first
              // (Ruby agent.rb L833 flush_pending_injections).
              self.flush_pending_injections()
              if action_result.awaiting_feedback {
                // request_user_feedback suspended the run (no reply yet):
                // end this run awaiting the user's next message.
                done = Some(self.build_result(Success))
              } else {
                // A user answer (feedback) is pushed as a user message so
                // the LLM responds to it immediately. Without feedback the
                // denied path ends the run (Ruby agent.rb denied handling).
                match action_result.feedback {
                  Some(fb) if fb.length() > 0 => {
                    self.history.append(
                      stamp_created_at(@message.Message::user(fb)),
                    )
                    self.hook_manager.emit(MessageAdded)
                  }
                  _ =>
                    if action_result.denied {
                      done = Some(self.build_result(Success))
                    }
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
      for msg in self.history.all() {
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
