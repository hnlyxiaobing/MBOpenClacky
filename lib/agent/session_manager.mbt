///|
/// Session lifecycle management: capacity enforcement and compression.
///
/// Reference: openclacky/lib/clacky/agent/session_manager.rb

///|
/// Maximum number of sessions to keep on disk.
pub let max_sessions : Int = 200

///|
/// Enforce the maximum session cap by removing the oldest sessions.
///
/// When the number of saved sessions exceeds `max_sessions`,
/// the oldest excess sessions are deleted from disk.
pub fn enforce_session_cap() -> Unit {
  let sessions = list_sessions()
  let count = sessions.length()
  if count <= max_sessions {
    return
  }
  let excess = count - max_sessions
  // sessions is sorted ascending (oldest first); delete the first `excess`
  let mut deleted = 0
  for session in sessions {
    if deleted >= excess {
      break
    }
    delete_session(session.session_id)
    deleted = deleted + 1
  }
}

///|
/// Truncate a session's messages, keeping only the most recent ones.
fn truncate_session(session : SessionData) -> Unit {
  let msg_count = session.messages.length()
  if msg_count <= max_recent_messages {
    return
  }
  let keep_start = msg_count - max_recent_messages
  let truncated : Array[@message.Message] = []
  for i = keep_start; i < msg_count; i = i + 1 {
    truncated.push(session.messages[i])
  }
  // Mark compression on the first kept message
  let msg_count_str = (msg_count - max_recent_messages).to_string()
  let first_msg = truncated[0]
  let compressed_msg = @message.Message::{
    role: first_msg.role,
    content: first_msg.content,
    tool_calls: first_msg.tool_calls,
    tool_call_id: first_msg.tool_call_id,
    name: first_msg.name,
    task_id: first_msg.task_id,
    created_at: first_msg.created_at,
    system_injected: first_msg.system_injected,
    memory_update: first_msg.memory_update,
    subagent_instructions: first_msg.subagent_instructions,
    subagent_result: first_msg.subagent_result,
    token_usage: first_msg.token_usage,
    compressed_summary: Some("Compressed \{msg_count_str} older messages"),
    transient: first_msg.transient,
  }
  truncated[0] = compressed_msg
  let data : SessionData = {
    session_id: session.session_id,
    name: session.name,
    messages: truncated,
    stats: session.stats,
    working_dir: session.working_dir,
    created_at: session.created_at,
    source: session.source,
    reasoning_effort: session.reasoning_effort,
    model_name: session.model_name,
  }
  save_session(data) catch {
    _ => ()
  }
}

///|
/// Check old sessions and apply compression placeholder truncation.
///
/// Phase 6 implementation: identifies sessions exceeding compression thresholds,
/// truncates messages beyond `max_recent_messages (20)`, and sets a
/// `compressed_summary` marker on the first preserved message.
/// Actual LLM-driven summary generation is deferred.
pub fn compress_old_sessions_if_needed(current_id : String) -> Unit {
  let sessions = list_sessions()
  for session in sessions {
    // Skip the currently active session
    if session.session_id == current_id {
      continue
    }
    // Check if this session needs compression
    let needs_it = session.messages.length() >= message_count_threshold
    if needs_it {
      truncate_session(session)
    } else if estimate_history_tokens(session.messages) >= compression_threshold {
      truncate_session(session)
    }
  }
}

///|
/// Format a session summary line for display (e.g., in --list output).
///
/// Format: `<session_id>  <created_at>  <msg_count> msgs  <model>`
pub fn format_session_summary(data : SessionData) -> String {
  let id = data.session_id
  let created = data.created_at
  let msg_count = data.messages.length().to_string()
  let model = match data.model_name {
    Some(m) => m
    None => "-"
  }
  "\{id}\t\{created}\t\{msg_count} msgs\t\{model}"
}
