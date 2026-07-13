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
      @utils.ensure_dir(dir)
      dir
    }
    None => raise @fs.IOError("Could not determine home directory for sessions")
  }
}

///|
/// Build the full file path for a session ID.
fn session_file_path(sessions_dir : String, session_id : String) -> String {
  @path.Path::join(sessions_dir, @path.Path(session_id + ".json")).to_string()
}

///|
/// Save a session snapshot to disk as a JSON file.
/// Overwrites any existing file with the same session ID.
pub fn save_session(data : SessionData) -> Unit raise @fs.IOError {
  let dir = ensure_sessions_dir()
  let path = session_file_path(dir, data.session_id)
  let json_str = data.to_json().stringify()
  @fs.write_string_to_file(path, json_str)
}

///|

///|
/// Load a session from disk by session ID.
/// Returns None if the session file does not exist or if any error occurs.
pub fn load_session(session_id : String) -> SessionData? {
  let dir = ensure_sessions_dir() catch { _ => return None }
  let path = session_file_path(dir, session_id)
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
  let path = session_file_path(dir, session_id)
  if @fs.path_exists(path) {
    @fs.remove_file(path) catch {
      _ => ()
    }
  }
}

///|
/// List all saved sessions, sorted by created_at ascending (oldest first).
/// Silently skips files that fail to load or parse.
pub fn list_sessions() -> Array[SessionData] {
  let dir = ensure_sessions_dir() catch { _ => return [] }
  let filenames = @fs.read_dir(dir) catch { _ => return [] }
  let sessions : Array[SessionData] = []
  for name in filenames {
    if name.has_suffix(".json") {
      let session_id = name[:name.length() - 5].to_owned()
      let result = load_session(session_id)
      match result {
        Some(s) => sessions.push(s)
        None => ()
      }
    }
  }
  // Sort by created_at ascending (oldest first)
  sessions.sort_by((a, b) => {
    if a.created_at < b.created_at {
      -1
    } else if a.created_at > b.created_at {
      1
    } else {
      0
    }
  })
  sessions
}

///|
/// Find the most recent session by created_at.
/// Returns None if no sessions exist.
pub fn find_most_recent() -> SessionData? {
  let sessions = list_sessions()
  if sessions.is_empty() {
    return None
  }
  // sessions is sorted ascending, last element is most recent
  Some(sessions[sessions.length() - 1])
}
