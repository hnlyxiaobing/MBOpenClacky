///|
/// Session store for persisting Agent state to JSON files.
///
/// Provides CRUD operations for session data stored as JSON files
/// in the `~/.mbopenclacky/sessions/` directory.
///
/// Reference: openclacky/lib/clacky/agent/session_persister.rb

///|
/// Get the sessions directory path, creating it if necessary.
pub fn ensure_sessions_dir() -> String raise @fs.IOError {
  match @utils.sessions_dir() {
    Some(dir) => {
      let dir = strip_trailing_separators(dir)
      if dir.is_empty() {
        raise @fs.IOError(
          "Sessions directory path is empty after normalization",
        )
      }
      @utils.ensure_dir(dir)
      // Defensive: verify the directory really exists and is a directory
      // before handing the path to read_dir (Windows error 267 otherwise).
      let is_directory = @fs.is_dir(dir) catch { _ => false }
      if !is_directory {
        raise @fs.IOError("Sessions directory is not usable: \{dir}")
      }
      dir
    }
    None => raise @fs.IOError("Could not determine home directory for sessions")
  }
}

///|
/// Strip trailing `/` and `\` separators from a directory path.
fn strip_trailing_separators(path : String) -> String {
  let mut end = path.length()
  while end > 0 {
    let c = path[end - 1]
    if c == '/' || c == '\\' {
      end = end - 1
    } else {
      break
    }
  }
  path[:end].to_owned()
}

///|
/// Build the full file path for a session ID.
fn session_file_path(sessions_dir : String, session_id : String) -> String {
  @path.Path::join(sessions_dir, @path.Path(session_id + ".json")).to_string()
}

///|
/// Timestamp used in session filenames: ISO 8601 with ':' replaced by '-'
/// so the name stays legal on Windows (Ruby uses a human-sortable
/// `<datetime>-<id8>.json` layout).
fn session_filename_datetime() -> String {
  current_timestamp_iso().replace(old=":", new="-")
}

///|
/// Locate the on-disk file for a session. New sessions are written as
/// `<datetime>-<id8>.json`; legacy files (pre-alignment) were written as
/// `<session_id>.json` and must remain loadable (decision 3).
/// Returns None when no matching file exists.
fn find_session_file(sessions_dir : String, session_id : String) -> String? {
  let exact = session_file_path(sessions_dir, session_id)
  if @fs.path_exists(exact) {
    return Some(exact)
  }
  // New format: any file whose name ends with `-<id8>.json`.
  let id8 = if session_id.length() >= 8 {
    session_id[:8].to_owned()
  } else {
    session_id
  }
  let suffix = "-" + id8 + ".json"
  let names = @fs.read_dir(sessions_dir) catch { _ => return None }
  for name in names {
    if name.has_suffix(suffix) {
      return Some(@path.Path::join(sessions_dir, @path.Path(name)).to_string())
    }
  }
  None
}

///|
/// Save a session snapshot to disk as a JSON file.
/// Overwrites any existing file with the same session ID.
pub fn save_session(data : SessionData) -> Unit raise @fs.IOError {
  let dir = ensure_sessions_dir()
  // New files use the `<datetime>-<id8>.json` layout; re-saving an
  // existing session keeps its current file (found by id) so the
  // filename stays stable across updates.
  let path = match find_session_file(dir, data.session_id) {
    Some(p) => p
    None => {
      let id8 = if data.session_id.length() >= 8 {
        data.session_id[:8].to_owned()
      } else {
        data.session_id
      }
      @path.Path::join(
        dir,
        @path.Path(session_filename_datetime() + "-" + id8 + ".json"),
      ).to_string()
    }
  }
  let json_str = data.to_json().stringify(indent=2)
  @fs.write_string_to_file(path, json_str)
  // Verify the file was actually written (catch silent write failures).
  if !@fs.path_exists(path) {
    raise @fs.IOError("save_session: file not found after write: \{path}")
  }
  // Note: Ruby chmods session files to 0600; moonbitlang/x/fs exposes no
  // permission API, so the 0600 restriction is recorded as a documented
  // exemption (decision 5) rather than silently attempted.
}

///|
/// Load a session from disk by session ID.
/// Returns None if the session file does not exist or if any error occurs.
pub fn load_session(session_id : String) -> SessionData? {
  let dir = ensure_sessions_dir() catch { _ => return None }
  let path = match find_session_file(dir, session_id) {
    Some(p) => p
    None => return None
  }
  if !@fs.path_exists(path) {
    return None
  }
  let json_str = @fs.read_file_to_string(path) catch { _ => return None }
  let json = @json.parse(json_str) catch { _ => return None }
  let parsed : SessionData = @json.from_json(json) catch { _ => return None }
  Some(parsed)
}

///|
/// Delete a session file from disk.
/// Does nothing if the session file does not exist.
pub fn delete_session(session_id : String) -> Unit {
  let dir = ensure_sessions_dir() catch { _ => return }
  let path = match find_session_file(dir, session_id) {
    Some(p) => p
    None => return
  }
  if @fs.path_exists(path) {
    @fs.remove_file(path) catch {
      _ => ()
    }
  }
}

///|
/// List all saved sessions, sorted by updated_at descending (most recently
/// touched first; Ruby session_manager.rb ordering). Sessions whose
/// updated_at is absent fall back to created_at.
/// Silently skips files that fail to load or parse.
/// Soft-deleted sessions (deleted_at set) are excluded; the capacity
/// cleanup policy handles them separately.
pub fn list_sessions() -> Array[SessionData] {
  let dir = ensure_sessions_dir() catch { _ => return [] }
  let filenames = @fs.read_dir(dir) catch { _ => return [] }
  let sessions : Array[SessionData] = []
  for name in filenames {
    if name.has_suffix(".json") {
      // Read the session_id from the file content: new filenames carry
      // only the first 8 id chars, so the content is the authoritative
      // source (fallback to the legacy filename when unparseable).
      let filepath = @path.Path::join(dir, @path.Path(name)).to_string()
      let json_str = @fs.read_file_to_string(filepath) catch { _ => continue }
      let json = @json.parse(json_str) catch { _ => continue }
      let parsed : SessionData = @json.from_json(json) catch { _ => continue }
      match parsed.deleted_at {
        Some(_) => continue
        None => ()
      }
      sessions.push(parsed)
    }
  }
  // Sort by updated_at descending (most recent first), falling back to
  // created_at for sessions written before updated_at existed.
  sessions.sort_by((a, b) => {
    let a_ts = if a.updated_at.length() > 0 {
      a.updated_at
    } else {
      a.created_at
    }
    let b_ts = if b.updated_at.length() > 0 {
      b.updated_at
    } else {
      b.created_at
    }
    if a_ts > b_ts {
      -1
    } else if a_ts < b_ts {
      1
    } else {
      0
    }
  })
  sessions
}

///|
/// Find sessions whose session_id starts with the given prefix.
/// Ruby matches id prefixes for CLI attach/continue completion; the
/// ordering follows list_sessions (updated_at descending).
pub fn find_sessions_by_prefix(prefix : String) -> Array[SessionData] {
  let sessions = list_sessions()
  let result : Array[SessionData] = []
  for s in sessions {
    if s.session_id.has_prefix(prefix) {
      result.push(s)
    }
  }
  result
}

///|
/// Find the most recently updated session.
/// Returns None if no sessions exist.
pub fn find_most_recent() -> SessionData? {
  let sessions = list_sessions()
  if sessions.is_empty() {
    return None
  }
  // sessions is sorted descending, first element is most recent
  Some(sessions[0])
}
