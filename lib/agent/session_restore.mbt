///| Enhanced session restoration with full state recovery.

///|

///| Supports: channel_info, latency, Time Machine state, error rollback,

///| and model recovery.

///|

///| Reference: openclacky/lib/clacky/agent/session_serializer.rb

///|
/// Result of an enhanced session restoration.
pub(all) struct RestoreResult {
  session_id : String
  name : String
  messages : Array[@message.Message]
  working_dir : String
  created_at : String
  total_cost : Double
  cost_source : String
  channel_info : ChannelInfo?
  latest_latency_ms : Int?
  latest_ttft_ms : Int?
  time_machine : SessionTimeMachine?
  needs_error_rollback : Bool
  model_recovered : Bool // Whether original model was found
  recovered_model_name : String // Resolved model name (may differ from saved)
  warnings : Array[String] // Non-fatal restoration warnings
} derive(Eq, Debug)

///|
/// Enhanced session restoration with full state recovery.
///
/// Restores: channel_info, latency, Time Machine, error state, model.
/// Performs model recovery check against agent_config.
pub fn restore_session_enhanced(
  agent_config : @config.AgentConfig,
  data : SessionData,
) -> RestoreResult {
  let warnings : Array[String] = []

  // Basic fields
  let session_id = data.session_id
  let name = data.name
  let messages = data.messages
  let working_dir = data.working_dir
  let created_at = data.created_at

  // Cost recovery
  let total_cost = data.stats.total_cost_usd
  let cost_source = data.stats.cost_source

  // Channel info pass-through
  let channel_info = data.channel_info

  // Latency pass-through
  let latest_latency_ms = data.latest_latency_ms
  let latest_ttft_ms = data.latest_ttft_ms

  // Time Machine state pass-through
  let time_machine = data.time_machine

  // Error rollback detection
  let needs_error_rollback = data.pending_error_rollback ||
    data.last_status == "error"

  // Model recovery: check if saved model still exists in config
  let mut model_recovered = false
  let mut recovered_model_name = ""
  match data.model_name {
    Some(saved_name) => {
      // Search for the model in current config
      let mut found = false
      for m in agent_config.models {
        if m.model == saved_name {
          // Additionally check base_url match if non-empty
          if data.model_base_url.is_empty() || m.base_url == data.model_base_url {
            found = true
            model_recovered = true
            recovered_model_name = saved_name
            break
          }
        }
      }
      if !found {
        // Model not found; fall back to current default
        warnings.push(
          "Model '" +
          saved_name +
          "' no longer exists in config; using current default",
        )
        match agent_config.current_model() {
          Some(cm) => recovered_model_name = cm.model
          None => recovered_model_name = ""
        }
      }
    }
    None =>
      match agent_config.current_model() {
        Some(cm) => recovered_model_name = cm.model
        None => recovered_model_name = ""
      }
  }

  {
    session_id,
    name,
    messages,
    working_dir,
    created_at,
    total_cost,
    cost_source,
    channel_info,
    latest_latency_ms,
    latest_ttft_ms,
    time_machine,
    needs_error_rollback,
    model_recovered,
    recovered_model_name,
    warnings,
  }
}

///|
/// Apply error rollback: remove messages after last real user message.
///
/// Call this after restoration if needs_error_rollback is true.
/// Finds the last real user message (role=User, system_injected != Some(true))
/// and truncates everything after it.
pub fn apply_error_rollback(
  messages : Array[@message.Message],
) -> Array[@message.Message] {
  // Find index of last real user message
  let mut last_user_idx = -1
  for i = 0; i < messages.length(); i = i + 1 {
    let msg = messages[i]
    if msg.role == @message.User {
      // Must NOT be system_injected
      match msg.system_injected {
        Some(true) => ()
        _ => last_user_idx = i
      }
    }
  }
  if last_user_idx < 0 {
    // No real user message found; return as-is
    return messages
  }
  // Keep messages up to and including the last real user message
  let result : Array[@message.Message] = []
  for i = 0; i <= last_user_idx; i = i + 1 {
    result.push(messages[i])
  }
  result
}

///|
/// Backfill task metadata from message history.
///
/// Scans messages for task_id fields and builds SessionTimeMachine state.
/// Merges with existing state if provided.
pub fn backfill_task_meta_from_history(
  messages : Array[@message.Message],
  existing : SessionTimeMachine?,
) -> SessionTimeMachine {
  let task_parents : Map[String, String] = Map([])
  let task_meta : Map[String, SessionTaskMeta] = Map([])
  let mut current_task_id = 0
  let mut active_task_id = 0

  // Merge from existing state first
  match existing {
    Some(ex) => {
      ex.task_parents.each(fn(k, v) { task_parents[k] = v })
      ex.task_meta.each(fn(k, v) { task_meta[k] = v })
      current_task_id = ex.current_task_id
      active_task_id = ex.active_task_id
    }
    None => ()
  }

  // Scan messages for task_id fields
  let mut prev_task_id = ""
  for msg in messages {
    match msg.task_id {
      Some(tid) => {
        if tid.is_empty() {
          continue
        }
        // Skip system_injected messages
        match msg.system_injected {
          Some(true) => continue
          _ => ()
        }
        // Build parent chain (sequential)
        if !task_parents.contains(tid) &&
          !prev_task_id.is_empty() &&
          prev_task_id != tid {
          task_parents[tid] = prev_task_id
        }
        // Build task_meta from first user message of each task
        if !task_meta.contains(tid) {
          if msg.role == @message.User {
            let title = extract_title_from_content(msg.content)
            let started = match msg.created_at {
              Some(ts) => ts
              None => ""
            }
            task_meta[tid] = { title, started_at: started, ended_at: "" }
          }
        }
        // Update ended_at with latest timestamp
        match task_meta.get(tid) {
          Some(meta) =>
            match msg.created_at {
              Some(ts) =>
                if ts > meta.ended_at {
                  task_meta[tid] = {
                    title: meta.title,
                    started_at: meta.started_at,
                    ended_at: ts,
                  }
                }
              None => ()
            }
          None => ()
        }
        prev_task_id = tid
      }
      None => ()
    }
  }

  { task_parents, task_meta, current_task_id, active_task_id }
}

///|
/// Extract a short title from message content (first 60 chars of text).
fn extract_title_from_content(content : @message.MessageContent) -> String {
  let text = match content {
    @message.Text(s) => s
    @message.Blocks(_) => ""
  }
  let trimmed = text.trim().to_owned()
  if trimmed.length() > 60 {
    trimmed[:57].to_owned() + "..."
  } else {
    trimmed
  }
}
