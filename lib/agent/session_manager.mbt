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
    channel_info: session.channel_info,
    latest_latency_ms: session.latest_latency_ms,
    latest_ttft_ms: session.latest_ttft_ms,
    time_machine: session.time_machine,
    pending_error_rollback: session.pending_error_rollback,
    model_base_url: session.model_base_url,
    last_status: session.last_status,
    last_error: session.last_error,
    forked_from: session.forked_from,
    chunk_count: session.chunk_count,
    agent_profile: session.agent_profile,
    sub_model: session.sub_model,
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

// ── Session Fork ──────────────────────────────────────────────────────────────

///|
/// Fork a session: create a complete copy with a new session ID,
/// reset statistics, and mark the origin via forked_from.
/// Returns the forked SessionData or an error message.
pub fn fork_session(session_id : String) -> Result[SessionData, String] {
  let original = load_session(session_id)
  match original {
    None => Err("Session not found: \{session_id}")
    Some(src) => {
      let new_id = generate_session_id()
      let forked_stats : SessionStats = {
        total_iterations: 0,
        total_cost_usd: 0.0,
        total_tasks: 0,
        cost_source: src.stats.cost_source,
        cache_creation_input_tokens: 0,
        cache_read_input_tokens: 0,
        total_requests: 0,
        cache_hit_requests: 0,
      }
      let forked : SessionData = {
        session_id: new_id,
        name: "\{src.name} (copy)",
        messages: src.messages,
        stats: forked_stats,
        working_dir: src.working_dir,
        created_at: current_timestamp_ms(),
        source: src.source,
        reasoning_effort: src.reasoning_effort,
        model_name: src.model_name,
        channel_info: src.channel_info,
        latest_latency_ms: None,
        latest_ttft_ms: None,
        time_machine: None,
        pending_error_rollback: false,
        model_base_url: src.model_base_url,
        last_status: "",
        last_error: "",
        forked_from: Some(src.session_id),
        chunk_count: 0,
        agent_profile: src.agent_profile,
        sub_model: src.sub_model,
      }
      save_session(forked) catch {
        e => return Err("Failed to save forked session: \{@debug.to_string(e)}")
      }
      Ok(forked)
    }
  }
}

// ── Associated File Discovery ─────────────────────────────────────────────────

///|
/// Find all files associated with a session: the main JSON file
/// and any chunk MD archive files.
/// Returns an array of file paths, or empty if session not found.
pub fn files_for(session_id : String) -> Array[String] {
  let dir = ensure_sessions_dir() catch { _ => return [] }
  let result : Array[String] = []
  // Check the main JSON file
  let json_path = @path.Path::join(dir, @path.Path(session_id + ".json")).to_string()
  if @fs.path_exists(json_path) {
    result.push(json_path)
  }
  // Find associated chunk MD files
  let chunks = chunks_for_current(session_id)
  for chunk in chunks {
    result.push(chunk)
  }
  result
}

// ── Chunk Management ─────────────────────────────────────────────────────────

///|
/// List all chunk MD files for a given session, sorted by index ascending.
/// Returns an array of absolute file paths.
pub fn chunks_for_current(session_id : String) -> Array[String] {
  let dir = ensure_sessions_dir() catch { _ => return [] }
  let filenames = @fs.read_dir(dir) catch { _ => return [] }
  let prefix = session_id + "-chunk-"
  let suffix = ".md"
  let chunks : Array[(Int, String)] = []
  for name in filenames {
    if name.has_prefix(prefix) && name.has_suffix(suffix) {
      // Extract index from "{session_id}-chunk-{N}.md"
      let idx_str = name[prefix.length():name.length() - suffix.length()].to_owned()
      let idx = parse_chunk_index(idx_str)
      let full_path = @path.Path::join(dir, @path.Path(name)).to_string()
      chunks.push((idx, full_path))
    }
  }
  chunks.sort_by((a, b) => {
    if a.0 < b.0 {
      -1
    } else if a.0 > b.0 {
      1
    } else {
      0
    }
  })
  chunks.map(fn(p) { p.1 })
}

///|
/// Write a chunk MD file to disk for a session.
/// Returns the absolute file path on success.
pub fn write_chunk(
  session_id : String,
  index : Int,
  content : String,
) -> Result[String, String] {
  let dir = ensure_sessions_dir() catch {
    _ => return Err("Cannot access sessions directory")
  }
  let filename = session_id + "-chunk-" + index.to_string() + ".md"
  let chunk_path = @path.Path::join(dir, @path.Path(filename)).to_string()
  @fs.write_string_to_file(chunk_path, content) catch {
    e => return Err("Failed to write chunk: \{@debug.to_string(e)}")
  }
  Ok(chunk_path)
}

///|
/// Compute the next unused chunk index for a session by scanning existing chunk files.
pub fn next_chunk_index(session_id : String) -> Int {
  let dir = ensure_sessions_dir() catch { _ => return 0 }
  let filenames = @fs.read_dir(dir) catch { _ => return 0 }
  let prefix = session_id + "-chunk-"
  let suffix = ".md"
  let mut max_idx = -1
  for name in filenames {
    if name.has_prefix(prefix) && name.has_suffix(suffix) {
      let idx_str = name[prefix.length():name.length() - suffix.length()].to_owned()
      let idx = parse_chunk_index(idx_str)
      if idx > max_idx {
        max_idx = idx
      }
    }
  }
  max_idx + 1
}

///|
/// Parse a chunk index string to Int, returning 0 on failure.
fn parse_chunk_index(s : String) -> Int {
  if s.is_empty() {
    return 0
  }
  let mut result = 0
  for ch in s {
    if ch >= '0' && ch <= '9' {
      result = result * 10 + (ch.to_int() - '0'.to_int())
    } else {
      return 0
    }
  }
  result
}

// ── Full-Text Search ─────────────────────────────────────────────────────────

///|
/// Search all session files for the given query string (case-sensitive).
/// Returns an array of (session_id, matching_line) pairs.
pub fn search_content(query : String) -> Array[(String, String)] {
  if query.length() < 2 {
    return []
  }
  let dir = ensure_sessions_dir() catch { _ => return [] }
  let filenames = @fs.read_dir(dir) catch { _ => return [] }
  let results : Array[(String, String)] = []
  for name in filenames {
    if !name.has_suffix(".json") {
      continue
    }
    let session_id = name[:name.length() - 5].to_owned()
    let filepath = @path.Path::join(dir, @path.Path(name)).to_string()
    let content = @fs.read_file_to_string(filepath) catch { _ => continue }
    // Search line by line
    let lines = content.split("\n")
    let mut found = false
    for line in lines {
      if line.contains(query) {
        results.push((session_id, line.trim().to_owned()))
        found = true
        break // one match per session
      }
    }
    if !found {
      // Also check chunk files for this session
      let chunks = chunks_for_current(session_id)
      for chunk_path in chunks {
        let chunk_content = @fs.read_file_to_string(chunk_path) catch {
          _ => continue
        }
        let chunk_lines = chunk_content.split("\n")
        for line in chunk_lines {
          if line.contains(query) {
            results.push((session_id, line.trim().to_owned()))
            break
          }
        }
      }
    }
  }
  results
}
