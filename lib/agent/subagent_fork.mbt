///| Forked subagent machinery (B7 decision 5).

///| Ports openclacky/lib/clacky/agent.rb fork_subagent / run_detached /

///| final_reply / generate_subagent_summary / extract_subagent_transcript:

///| config inheritance + model/credential handoff, history deep-clone,

///| system-prompt suffix with forbidden-tools notice, assistant ack,

///| runtime forbidden/allowed enforcement, cost absorption and the

///| transcript/summary extractors used by the parent's invoke_skill path.

///|
/// Fork a subagent with the given configuration. The subagent inherits all
/// messages and tools from the parent agent; tools are NOT removed from the
/// registry (cache reuse), forbidden tools are blocked at runtime in
/// execute_single_tool via the forbidden/allowed sets.
///
/// Mirrors Ruby agent.rb fork_subagent (agent.rb:1697-1904).
///
/// @param model "lite" resolves the current model's lite companion via the
///   config's virtual overlay; any other value is a model name lookup.
/// @param forbidden_tools tool names blocked at runtime.
/// @param system_prompt_suffix extra instructions, inserted as a user
///   message (for cache reuse) together with the fork-mode preamble and
///   the forbidden-tools notice.
/// @return a new standalone Agent (not running).
/// @raise @errors.AgentError when `model` names a model that does not
///   exist in the config.
pub fn Agent::fork_subagent(
  self : Agent,
  model? : String? = None,
  forbidden_tools? : Array[String] = [],
  system_prompt_suffix? : String? = None,
) -> Agent raise @errors.AgentError {
  // Clone config to avoid affecting the parent (Ruby @config.deep_copy).
  let mut subagent_config = self.config.deep_copy()
  // Switch to the requested model if provided.
  match model {
    Some("lite") =>
      // Special keyword: use the lite companion of the current model.
      // MB resolves lite via lite_model_config_for_current (explicit
      // type_="lite" entry first, provider preset derivation second) and
      // applies it as a virtual overlay on the subagent's config copy —
      // the shared @models list on the parent is never mutated (Ruby's
      // apply_virtual_model_overlay! intent).
      match subagent_config.lite_model_config_for_current() {
        Some(lite_cfg) =>
          subagent_config = subagent_config.virtual_model_overlay(lite_cfg)
        None => () // No lite resolvable: keep current (primary) model.
      }
    Some(name) =>
      // Regular model name lookup (Ruby: find first model whose "model"
      // matches, switch by id). Case-insensitive exact match.
      match subagent_config.switch_model_by_name(name) {
        Ok(_) => ()
        Err(_) => {
          let available = subagent_config.models
            .map(fn(m) { m.model })
            .join(", ")
          raise @errors.AgentError(
            "Model '\{name}' not found in config. Available models: \{available}",
          )
        }
      }
    None => ()
  }
  // Build the subagent's client from its (possibly overlaid) config so
  // credentials/model follow the fork (Ruby: new Clacky::Client from
  // subagent_config.api_key/base_url/model_name/anthropic_format).
  let subagent_client = match subagent_config.current_model() {
    Some(m) => {
      let api_type = if m.anthropic_format {
        @config.AnthropicMessages
      } else {
        @config.Providers::api_type_for_model(m.base_url, m.model)
      }
      @client.Client::new(
        m.api_key,
        m.base_url,
        m.model,
        api_type,
        provider_id=self.client.provider_id,
        vision_supported=Some(self.client.vision_supported),
      )
    }
    None => self.client
  }
  // Create the subagent: unique session_id, same name/working dir, fresh
  // todo/memory (Ruby creates a new Agent with a generated session id).
  let subagent = Agent::new(
    generate_session_id(),
    self.name,
    self.working_dir,
    subagent_client,
    subagent_config,
  )
  subagent.is_subagent = true
  // Inherit previous_total_tokens so the first iteration delta is
  // calculated correctly (Ruby ivar copy).
  subagent.previous_total_tokens = self.previous_total_tokens
  // Inherit the mock queue (test support) so a forked subagent can be
  // driven with mock responses in white-box tests.
  for r in self.mock_responses {
    subagent.mock_responses.push(r)
  }
  // Deep-clone history to avoid cross-contamination; dangling tool_calls
  // (no tool_result yet) are cleaned up by MessageHistory#append when the
  // subagent appends its first user message.
  subagent.history.replace_all(deep_clone_messages(self.history.all()))
  // Runtime tool restrictions (enforced in execute_single_tool).
  subagent.forbidden_tools = forbidden_tools
  subagent.allowed_tools = None
  // Append the fork preamble + suffix as a user message (cache reuse),
  // then an assistant ack so the conversation structure is complete:
  //   [user] role/constraints → [assistant] ack → [user] actual task (run)
  match system_prompt_suffix {
    Some(suffix) => {
      let forbidden_notice = if forbidden_tools.length() > 0 {
        let tool_list = forbidden_tools.map(fn(t) { "`\{t}`" }).join(", ")
        "\n\n[System Notice] The following tools are disabled in this subagent and will be rejected if called: \{tool_list}"
      } else {
        ""
      }
      let preamble = "CRITICAL: TASK CONTEXT SWITCH - FORKED SUBAGENT MODE\n\n" +
        "You are now running as a forked subagent — a temporary, isolated agent spawned by the parent agent to handle a specific task. " +
        "You run independently and cannot communicate back to the parent mid-task. " +
        "When you finish (i.e., you stop calling tools and return a final response), your output will be " +
        "automatically summarized and returned to the parent agent as a result so it can continue.\n\n" +
        suffix +
        forbidden_notice
      subagent.history.append(
        stamp_created_at({
          role: @message.User,
          content: @message.Text(preamble),
          tool_calls: None,
          tool_call_id: None,
          name: None,
          reasoning_content: None,
          task_id: None,
          created_at: None,
          system_injected: Some(true),
          memory_update: None,
          subagent_instructions: Some("true"),
          subagent_result: None,
          token_usage: None,
          compressed_summary: None,
          transient: None,
        }),
      )
      subagent.history.append(
        stamp_created_at({
          role: @message.Assistant,
          content: @message.Text(
            "Understood. I am now operating as a subagent with the constraints above. Please provide the task.",
          ),
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
        }),
      )
    }
    None => ()
  }
  // Mark subagent metadata for summary generation: the parent's history
  // size at fork time (Ruby sets @parent_message_count to the parent's
  // @history.size AFTER cloning — the suffix/ack live on the subagent).
  subagent.parent_message_count = self.history.size()
  subagent
}

///|
/// Deep-clone an array of messages for a subagent fork. Message structs
/// are mostly immutable; tool_calls arrays are defensively rebuilt so
/// parent and subagent can never alias mutable state.
fn deep_clone_messages(
  msgs : Array[@message.Message],
) -> Array[@message.Message] {
  let out : Array[@message.Message] = []
  for m in msgs {
    let tc : Array[@message.ToolCall]? = match m.tool_calls {
      Some(calls) =>
        Some(calls.map(fn(c) { { ..c, function: { ..c.function } } }))
      None => None
    }
    out.push({ ..m, tool_calls: tc })
  }
  out
}

///|
/// The subagent's last non-empty assistant message — its actual answer.
///
/// A subagent's `run` result carries cost and iteration counts but no reply
/// text, and its trailing history entries are usually tool results, so the
/// answer is found by scanning backwards from the end. Only messages after
/// the fork point are considered (Ruby agent.rb final_reply).
pub fn final_reply(subagent : Agent) -> String {
  let new_messages = subagent_history_after_fork(subagent)
  for i = new_messages.length() - 1; i >= 0; i = i - 1 {
    let m = new_messages[i]
    if m.role == @message.Assistant {
      match m.content {
        @message.Text(t) => if t.trim().length() > 0 { return t }
        _ => ()
      }
    }
  }
  ""
}

///|
/// Generate a concise summary of a completed subagent run. The summary
/// text replaces the subagent instructions message in the parent agent
/// (Ruby agent.rb generate_subagent_summary).
pub fn generate_subagent_summary(subagent : Agent) -> String {
  let new_messages = subagent_history_after_fork(subagent)
  // Extract tool calls.
  let tool_calls : Array[String] = []
  for m in new_messages {
    if m.role == @message.Assistant {
      match m.tool_calls {
        Some(calls) =>
          for tc in calls {
            let name = tc.function.name
            if !tool_calls.contains(name) {
              tool_calls.push(name)
            }
          }
        None => ()
      }
    }
  }
  // Extract the final assistant response.
  let mut last_response : String? = None
  for i = new_messages.length() - 1; i >= 0; i = i - 1 {
    let m = new_messages[i]
    if m.role == @message.Assistant {
      match m.content {
        @message.Text(t) =>
          if t.trim().length() > 0 {
            last_response = Some(t)
            break
          }
        _ => ()
      }
    }
  }
  // Build the summary (this replaces the subagent instructions message).
  let parts : Array[String] = []
  parts.push("[SUBAGENT SUMMARY]")
  parts.push(
    "Completed in \{subagent.iterations} iterations, cost: $\{format_cost(subagent.total_cost)}",
  )
  if tool_calls.length() > 0 {
    parts.push("Tools used: \{tool_calls.join(", ")}")
  }
  parts.push("")
  parts.push("Results:")
  parts.push(
    match last_response {
      Some(r) => r
      None => "(No response)"
    },
  )
  parts.join("\n")
}

///|
/// Extract the subagent's own message trail for persistence/replay —
/// a trimmed, LLM-free view of what the subagent did after the fork.
/// System-injected scaffolding (fork instructions, ack) is dropped so
/// the WebUI can render a collapsible sub-process without polluting the
/// main thread (Ruby agent.rb extract_subagent_transcript).
pub fn extract_subagent_transcript(
  subagent : Agent,
  skill_identifier : String,
) -> Json {
  let new_messages = subagent_history_after_fork(subagent)
  let events : Array[Json] = []
  for m in new_messages {
    if m.system_injected is Some(true) {
      continue
    }
    let role = match m.role {
      @message.Assistant => "assistant"
      @message.User => "user"
      @message.Tool => "tool"
      _ => continue
    }
    let obj : Map[String, Json] = { "role": role.to_json() }
    match m.content {
      @message.Text(t) =>
        if t.trim().length() > 0 {
          obj["content"] = t.to_json()
        }
      _ => ()
    }
    match m.tool_calls {
      Some(calls) =>
        if calls.length() > 0 {
          let arr : Array[Json] = []
          for tc in calls {
            arr.push(
              Json::object({
                "name": tc.function.name.to_json(),
                "arguments": tc.function.arguments.to_json(),
              }),
            )
          }
          obj["tool_calls"] = arr.to_json()
        }
      None => ()
    }
    match m.tool_call_id {
      Some(id) => obj["tool_call_id"] = id.to_json()
      None => ()
    }
    if obj.contains("content") || obj.contains("tool_calls") {
      events.push(Json::object(obj))
    }
  }
  Json::object({
    "skill": skill_identifier.to_json(),
    "iterations": subagent.iterations.to_json(),
    "cost_usd": format_cost(subagent.total_cost).to_json(),
    "events": events.to_json(),
  })
}

///|
/// Slice of the subagent history after the fork point (Ruby:
/// subagent.history.to_a[parent_message_count..]).
fn subagent_history_after_fork(subagent : Agent) -> Array[@message.Message] {
  let all = subagent.history.all()
  let from = subagent.parent_message_count
  if from >= all.length() {
    return []
  }
  let out : Array[@message.Message] = []
  for i = from; i < all.length(); i = i + 1 {
    out.push(all[i])
  }
  out
}

///|
/// Format a cost value with 4 decimals (Ruby total_cost.round(4)).
fn format_cost(cost : Double) -> String {
  let scaled = (cost * 10000.0).round().to_int()
  let int_part = scaled / 10000
  let frac_part = scaled % 10000
  let frac = if frac_part < 0 { -frac_part } else { frac_part }
  let frac_str = frac.to_string()
  let padded = if frac_str.length() == 1 {
    "000\{frac_str}"
  } else if frac_str.length() == 2 {
    "00\{frac_str}"
  } else if frac_str.length() == 3 {
    "0\{frac_str}"
  } else {
    frac_str
  }
  "\{int_part}.\{padded}"
}

///|
/// Run a one-off task on a forked subagent and return its final reply
/// text WITHOUT mutating this (parent) agent's history. Used by
/// extensions that need a side analysis which must reuse the parent's
/// cached context + unified billing but must NOT pollute the main
/// conversation (Ruby agent.rb run_detached).
///
/// The subagent deep-clones the parent history, runs to completion, and
/// is discarded — only its cost is merged back into the parent.
///
/// @param task the task/prompt for the subagent
/// @param model "lite" for the lite companion, nil = current
/// @param forbidden_tools tool names to block at runtime
/// @return the subagent's final assistant reply ("" if none)
pub async fn Agent::run_detached(
  self : Agent,
  task : String,
  model? : String? = None,
  forbidden_tools? : Array[String] = [],
) -> String {
  let subagent = self.fork_subagent(
    model~,
    forbidden_tools~,
    system_prompt_suffix=Some(
      "You are running a one-off background analysis. Do the task and return only the requested output. Do not ask follow-up questions.",
    ),
  )
  let result = subagent.run(task)
  // A detached run stays invisible: merge its cost silently (Ruby
  // absorb_subagent_cost(result, notify_ui: false)).
  self.total_cost = self.total_cost + result.total_cost_usd
  final_reply(subagent)
}

///|
/// A labeled job for concurrent execution (Ruby fanout.rb Fanout).
///
/// The `run` closure blocks inside the subagent's async run; it must be
/// the ONLY thing the caller does on the job (forking/deep-cloning must
/// happen on the calling thread before handing the job over — Ruby
/// fan_out_labeled documents the same constraint).
pub struct FanOutJob[X] {
  label : String
  run : async () -> X
}

///|
/// One fan-out slot, aligned to the input order (Ruby Fanout::Result).
///
/// `error` holds the error message when the job raised; `value` is `None`
/// in that case. `duration_ms` is the wall-clock time the job took.
/// When the batch times out, unfinished slots carry a timeout error and
/// `duration_ms` is 0 (Ruby fills them with FanoutTimeoutError).
pub struct FanOutResult[X] {
  index : Int
  value : X?
  error : String?
  duration_ms : Int64
} derive(Debug)

///|
pub extend FanOutResult with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// True when the job completed without raising (Ruby Result#ok?).
pub fn[X] FanOutResult::ok(self : FanOutResult[X]) -> Bool {
  self.error is None
}

///|
/// Default concurrency limit (Ruby Fanout::DEFAULT_MAX_CONCURRENCY).
pub const FAN_OUT_DEFAULT_MAX_CONCURRENCY : Int = 4

///|
/// Run a batch of jobs concurrently and collect one result per job,
/// aligned to the input order, regardless of completion order.
///
/// Mirrors Ruby `Clacky::Fanout#run`:
/// - a job that raises becomes a failed slot (its siblings are NOT torn down);
/// - at most `max_concurrency` jobs run at once (default 4);
/// - optional wall-clock budget for the whole batch: on timeout, still-running
///   jobs are cancelled and their slots are filled with a timeout error, while
///   already-finished slots are preserved (Ruby fill_unfinished semantics);
/// - an empty batch returns [].
///
/// @param jobs jobs to run, each `{ label, run }` (label informational)
/// @param max_concurrency jobs allowed to run at once (must be >= 1)
/// @param timeout_ms optional wall-clock budget for the whole batch
/// @return one FanOutResult per job, aligned to `jobs` order
pub async fn[X] fan_out(
  jobs : Array[FanOutJob[X]],
  max_concurrency? : Int = FAN_OUT_DEFAULT_MAX_CONCURRENCY,
  timeout_ms? : Int? = None,
) -> Array[FanOutResult[X]] {
  if jobs.is_empty() {
    return []
  }
  let n = max_concurrency.max(1)
  // Shared slots: each job writes its own index. A job raising is captured
  // into an error slot here, so @async.all below can never fail as a batch
  // (Ruby: a raising job must not tear down its siblings).
  let slots : Array[FanOutResult[X]?] = Array::make(jobs.length(), None)
  let tasks : Array[async () -> Unit] = []
  for i, job in jobs {
    let run = job.run
    tasks.push(() => {
      let started = current_time_ms()
      let outcome : Result[X, Error] = Ok(run()) catch {
        // A cancellation (e.g. the batch wall-clock timeout fired) is NOT a
        // job failure: leave the slot None so fill_unfinished below stamps
        // it with the timeout error, mirroring Ruby's FanoutTimeoutError.
        _ if @async.is_being_cancelled() => return
        e => Err(e)
      }
      let duration = current_time_ms() - started
      slots[i] = Some(
        match outcome {
          Ok(v) =>
            { index: i, value: Some(v), error: None, duration_ms: duration }
          Err(e) =>
            {
              index: i,
              value: None,
              error: Some(@errors.error_message(e)),
              duration_ms: duration,
            }
        },
      )
    })
  }
  let run_all = () => @async.all(tasks, max_concurrent=n) |> ignore
  match timeout_ms {
    None => run_all()
    Some(t) =>
      // Wall-clock budget for the whole batch: on timeout, still-running
      // jobs are cancelled and stay None → filled below (fill_unfinished).
      @async.with_timeout_opt(t, run_all) |> ignore
  }
  slots.mapi(fn(i, slot) {
    match slot {
      Some(r) => r
      None =>
        {
          index: i,
          value: None,
          error: Some(
            "fan-out job \{i} did not finish within \{timeout_ms.unwrap_or(0)}ms",
          ),
          duration_ms: 0,
        }
    }
  })
}

///|
/// Run labeled jobs in parallel (Ruby agent.rb fan_out_labeled).
///
/// Each job must carry a `label` and a `run` closure; a missing label gets
/// the default "Subagent {index+1}/{size}". The caller must build subagents
/// on the calling thread BEFORE handing jobs over — forking deep-copies
/// config + history and must not race. Only the blocking run belongs in the
/// lambda.
///
/// Ruby's within_phase/task_epoch wrapping has no MB counterpart (no UI
/// phase broadcaster / no cross-thread interruption model), so it is
/// intentionally omitted; the concurrency semantics are identical.
///
/// @param jobs labeled jobs; label defaults to "Subagent {i+1}/{size}"
/// @param max_concurrency jobs allowed to run at once
/// @param timeout_ms optional wall-clock budget for the whole batch
/// @return one FanOutResult per job, aligned to `jobs` order
pub async fn[X] fan_out_labeled(
  jobs : Array[FanOutJob[X]],
  max_concurrency? : Int = FAN_OUT_DEFAULT_MAX_CONCURRENCY,
  timeout_ms? : Int? = None,
) -> Array[FanOutResult[X]] {
  if jobs.is_empty() {
    return []
  }
  let labeled = jobs.mapi(fn(i, job) {
    let label = if job.label.is_empty() {
      "Subagent \{i + 1}/\{jobs.length()}"
    } else {
      job.label
    }
    FanOutJob::{ label, run: job.run }
  })
  fan_out(labeled, max_concurrency~, timeout_ms~)
}
