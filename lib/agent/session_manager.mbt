///|
/// Session lifecycle management: capacity enforcement and compression.
///
/// Reference: openclacky/lib/clacky/agent/session_manager.rb

///|
/// Maximum number of sessions to keep on disk.
pub let max_sessions : Int = 200

///|
/// Soft-delete grace period: a soft-deleted session stays in place for this
/// long (7 days) before it is moved into the trash directory.
let soft_delete_grace_ms : Int64 = 7 * 24 * 3600 * 1000L

///|
/// Trash retention: files are physically deleted after this long (30 days)
/// in the trash directory.
let trash_retention_ms : Int64 = 30 * 24 * 3600 * 1000L

///|
/// Enforce the maximum session cap with a three-tier cleanup policy
/// (decision 4: soft-delete → trash → purge):
///   1. sessions soft-deleted longer than the grace period are moved to the
///      trash directory (`.trash/`, hidden from session listing);
///   2. trash files older than the retention period are physically removed;
///   3. if the session count still exceeds `max_sessions`, the oldest
///      non-pinned sessions are soft-deleted (deleted_at set in place).
pub fn enforce_session_cap() -> Unit {
  purge_expired_soft_deleted()
  purge_expired_trash()
  let sessions = list_sessions()
  let count = sessions.length()
  if count <= max_sessions {
    return
  }
  let excess = count - max_sessions
  let mut deleted = 0
  // list_sessions is updated_at descending; walk from the oldest end so the
  // least-recently-touched sessions are soft-deleted first.
  for i = sessions.length() - 1; i >= 0; i = i - 1 {
    if deleted >= excess {
      break
    }
    let session = sessions[i]
    if session.pinned {
      continue
    }
    soft_delete_session(session.session_id)
    deleted = deleted + 1
  }
}

///|
/// Mark a session as soft-deleted (set deleted_at) without removing the file.
fn soft_delete_session(session_id : String) -> Unit {
  match load_session(session_id) {
    None => ()
    Some(data) => {
      let updated = { ..data, deleted_at: Some(current_iso8601()) }
      save_session(updated) catch {
        _ => ()
      }
    }
  }
}

///|
/// Move soft-deleted sessions whose grace period has elapsed into the trash.
fn purge_expired_soft_deleted() -> Unit {
  let dir = ensure_sessions_dir() catch { _ => return }
  let filenames = @fs.read_dir(dir) catch { _ => return }
  let now_ms = current_time_ms()
  let threshold_iso = ms_to_iso8601(now_ms - soft_delete_grace_ms)
  for name in filenames {
    if !name.has_suffix(".json") {
      continue
    }
    let filepath = @path.Path::join(dir, @path.Path(name)).to_string()
    let json_str = @fs.read_file_to_string(filepath) catch { _ => continue }
    let json = @json.parse(json_str) catch { _ => continue }
    let parsed : SessionData = @json.from_json(json) catch { _ => continue }
    match parsed.deleted_at {
      None => continue
      Some(deleted_at) =>
        // ISO strings with a consistent offset compare in chronological order.
        if deleted_at < threshold_iso {
          move_file_to_trash(dir, name, filepath)
        }
    }
  }
}

///|
/// Move a session file into the `.trash` directory. Implemented as
/// read + write + remove because moonbitlang/x/fs exposes no rename API.
fn move_file_to_trash(
  sessions_dir : String,
  filename : String,
  filepath : String,
) -> Unit {
  let trash_dir = @path.Path::join(sessions_dir, @path.Path(".trash")).to_string()
  if !@fs.path_exists(trash_dir) {
    @utils.ensure_dir(trash_dir)
  }
  let content = @fs.read_file_to_string(filepath) catch { _ => return }
  let dest = @path.Path::join(trash_dir, @path.Path(filename)).to_string()
  @fs.write_string_to_file(dest, content) catch {
    _ => return
  }
  @fs.remove_file(filepath) catch {
    _ => ()
  }
}

///|
/// Physically delete trash files older than the retention period.
/// Trash files keep their original `<datetime>-<id8>.json` names, so the
/// datetime prefix is parsed from the filename (no mtime API in x/fs).
fn purge_expired_trash() -> Unit {
  let dir = ensure_sessions_dir() catch { _ => return }
  let trash_dir = @path.Path::join(dir, @path.Path(".trash")).to_string()
  if !@fs.path_exists(trash_dir) {
    return
  }
  let filenames = @fs.read_dir(trash_dir) catch { _ => return }
  let now_ms = current_time_ms()
  let threshold_iso = ms_to_iso8601(now_ms - trash_retention_ms)
  let threshold_sanitized = threshold_iso.replace(old=":", new="-")
  for name in filenames {
    if !name.has_suffix(".json") {
      continue
    }
    // Filename layout `<datetime>-<id8>.json`; the datetime prefix is
    // everything before the last '-' (the id8 segment). The prefix is
    // sanitized the same way session_filename_datetime() is, so a
    // dictionary comparison stays chronological.
    let parts = name.split("-")
    let stamp = parts[0:parts.length() - 1].join("-")
    if stamp < threshold_sanitized {
      let filepath = @path.Path::join(trash_dir, @path.Path(name)).to_string()
      @fs.remove_file(filepath) catch {
        _ => ()
      }
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
/// Fork a session: create a complete copy with a new session ID and reset
/// statistics. Mirrors Ruby forked-from semantics: the Time Machine state
/// carries over and `forked_from` is left unset (the CLI records the
/// lineage separately; decision 8).
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
        created_at: current_timestamp_iso(),
        source: src.source,
        reasoning_effort: src.reasoning_effort,
        model_name: src.model_name,
        model_config_id: src.model_config_id,
        channel_info: src.channel_info,
        latest_latency_ms: None,
        latest_ttft_ms: None,
        time_machine: src.time_machine,
        pending_error_rollback: false,
        model_base_url: src.model_base_url,
        last_status: "",
        last_error: "",
        error_code: None,
        top_up_url: None,
        raw_message: None,
        forked_from: None,
        chunk_count: 0,
        agent_profile: src.agent_profile,
        sub_model: src.sub_model,
        pinned: false,
        todos: src.todos,
        updated_at: current_timestamp_iso(),
        previous_total_tokens: 0,
        deleted_at: None,
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
  // Check the main JSON file (new `<datetime>-<id8>.json` or legacy layout)
  match find_session_file(dir, session_id) {
    Some(p) => result.push(p)
    None => ()
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
/// Soft timeout for full-text search: scanning stops after this many
/// milliseconds even if files remain (Ruby wraps the search in
/// Timeout.timeout; MoonBit has no cooperative cancellation for sync IO,
/// so a deadline check between files is the closest equivalent).
let search_timeout_ms : Int64 = 5000L

///|
/// Extract a snippet around the first query match in a line: up to 60 chars
/// of context on each side, ellipsized at the window edges.
fn snippet_around(line : StringView, query : String) -> String {
  let window = 60
  match line.find(query) {
    None => line.trim().to_owned()
    Some(idx) => {
      let start = if idx > window { idx - window } else { 0 }
      let end = if idx + query.length() + window < line.length() {
        idx + query.length() + window
      } else {
        line.length()
      }
      let mut out = ""
      if start > 0 {
        out = out + "…"
      }
      out = out + line[start:end].to_owned()
      if end < line.length() {
        out = out + "…"
      }
      out
    }
  }
}

///|
/// Search all session files (main JSON + chunk MD archives) for the given
/// query string (case-sensitive). Returns an array of
/// (session_id, snippet_around_match) pairs, one per session, bounded by a
/// soft deadline.
pub fn search_content(query : String) -> Array[(String, String)] {
  if query.length() < 2 {
    return []
  }
  let dir = ensure_sessions_dir() catch { _ => return [] }
  let filenames = @fs.read_dir(dir) catch { _ => return [] }
  let results : Array[(String, String)] = []
  let deadline = current_time_ms() + search_timeout_ms
  for name in filenames {
    if current_time_ms() > deadline {
      break
    }
    if !name.has_suffix(".json") {
      continue
    }
    let filepath = @path.Path::join(dir, @path.Path(name)).to_string()
    let content = @fs.read_file_to_string(filepath) catch { _ => continue }
    // New filenames carry only the first 8 id chars; the content is the
    // authoritative source for the session_id.
    let json = @json.parse(content) catch { _ => continue }
    let parsed : SessionData = @json.from_json(json) catch { _ => continue }
    let session_id = parsed.session_id
    // Search line by line
    let lines = content.split("\n")
    let mut found = false
    for line in lines {
      if line.contains(query) {
        results.push((session_id, snippet_around(line, query)))
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
            results.push((session_id, snippet_around(line, query)))
            break
          }
        }
      }
    }
  }
  results
}
