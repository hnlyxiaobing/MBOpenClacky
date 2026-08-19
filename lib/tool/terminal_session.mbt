///| Terminal session manager: tracks background and interactive sessions.

///| Reference: D:/MoonBit/openclacky/lib/clacky/tools/terminal/session_manager.rb

///|
/// Status of a terminal session.
pub(all) enum SessionStatus {
  Starting
  Running
  Exited
  Killed
} derive(Eq, Debug)

///|
pub extend SessionStatus with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend SessionStatus with Eq::{not_equal, equal}

///|
pub fn SessionStatus::to_string(self : SessionStatus) -> String {
  match self {
    Starting => "starting"
    Running => "running"
    Exited => "exited"
    Killed => "killed"
  }
}

///|
/// A tracked terminal session.
pub(all) struct TerminalSession {
  id : Int
  mut command : String
  mut status : SessionStatus
  mut output : String
  started_at : Int
  mut exit_code : Int?
  mut pid : Int?
  mut cwd : String
  mut overflow_file : String?
  /// Output capture file for background sessions (spawn_orphan).
  mut output_file : String?
  /// Completion marker token for the background command.
  mut marker_token : String
  /// Incremental read offset into the background output file.
  mut output_offset : Int
} derive(Debug)

///|
pub extend TerminalSession with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub fn TerminalSession::new(
  id : Int,
  command : String,
  cwd : String,
) -> TerminalSession {
  {
    id,
    command,
    status: Starting,
    output: "",
    started_at: 0,
    exit_code: None,
    pid: None,
    cwd,
    overflow_file: None,
    output_file: None,
    marker_token: "",
    output_offset: 0,
  }
}

///|
/// Session manager state stored as a singleton.
priv struct SessionManagerState {
  sessions : Array[TerminalSession]
  mut next_id : Int
}

///|
/// Get the singleton session manager state (top-level let creates a persistent instance).
let session_manager_state : SessionManagerState = { sessions: [], next_id: 0 }

///|
let _terminal_session_manager : TerminalSessionManager = TerminalSessionManager::{

}

///|
/// Session manager operations (namespace via empty struct).
pub struct TerminalSessionManager {}

///|
/// Register a new session, returning its assigned ID.
pub fn TerminalSessionManager::register(command : String, cwd : String) -> Int {
  session_manager_state.next_id = session_manager_state.next_id + 1
  let id = session_manager_state.next_id
  let session = TerminalSession::new(id, command, cwd)
  session_manager_state.sessions.push(session)
  id
}

///|
/// Get a session by ID.
pub fn TerminalSessionManager::get(id : Int) -> TerminalSession? {
  session_manager_state.sessions.iter().find_first(fn(s) { s.id == id })
}

///|
/// List all sessions sorted by ID.
pub fn TerminalSessionManager::list() -> Array[TerminalSession] {
  let result = session_manager_state.sessions.iter().collect()
  result
}

///|
/// Mark a session as running.
pub fn TerminalSessionManager::mark_running(id : Int) -> Unit {
  match TerminalSessionManager::get(id) {
    Some(s) => if s.status == Starting { s.status = Running }
    _ => ()
  }
}

///|
/// Record the spawned process PID for a session.
pub fn TerminalSessionManager::set_pid(id : Int, pid : Int) -> Unit {
  match TerminalSessionManager::get(id) {
    Some(s) => s.pid = Some(pid)
    _ => ()
  }
}

///|
/// Record the output capture file and marker token for a background session.
pub fn TerminalSessionManager::set_output_file(
  id : Int,
  path : String,
  marker_token : String,
) -> Unit {
  match TerminalSessionManager::get(id) {
    Some(s) => {
      s.output_file = Some(path)
      s.marker_token = marker_token
    }
    _ => ()
  }
}

///|
/// Update session with completed output and exit code.
pub fn TerminalSessionManager::complete(
  id : Int,
  output : String,
  exit_code : Int,
  overflow_file? : String? = None,
) -> Unit {
  match TerminalSessionManager::get(id) {
    Some(s) => {
      s.output = output
      s.exit_code = Some(exit_code)
      s.status = Exited
      s.overflow_file = overflow_file
    }
    _ => ()
  }
}

///|
/// stdin pipe writers for interactive input, keyed by session id.
/// WriteToProcess is not Debug-derivable, so it lives outside the
/// session struct in a parallel map.
let session_stdin_writers : Ref[Map[Int, @process.WriteToProcess]] = Ref(
  Map([]),
)

///|
/// Record the stdin pipe writer for interactive input.
pub fn TerminalSessionManager::set_stdin_writer(
  id : Int,
  writer : @process.WriteToProcess,
) -> Unit {
  let m = session_stdin_writers.val
  m[id] = writer
}

///|
/// Write a line of interactive input to a background session's stdin.
/// Returns true if the write was delivered.
pub async fn TerminalSessionManager::send_input(
  id : Int,
  input : String,
) -> Bool {
  let m = session_stdin_writers.val
  match m.get(id) {
    Some(writer) => {
      writer.write(input + "\n") catch {
        _ => return false
      }
      true
    }
    None => false
  }
}

///|
/// Drop the stdin writer when a session is finalized.
pub fn TerminalSessionManager::drop_stdin_writer(id : Int) -> Unit {
  let m = session_stdin_writers.val
  match m.get(id) {
    Some(writer) => {
      writer.close()
      ignore(m.remove(id))
    }
    None => ()
  }
}

///|
/// Kill a session by ID: send real termination signals to the underlying
/// process when a PID is tracked (graceful TERM then KILL), otherwise
/// fall back to marking the session killed.
///
/// Returns true if the session was found and killed.
pub async fn TerminalSessionManager::kill(id : Int) -> Bool {
  match TerminalSessionManager::get(id) {
    Some(s) if s.status == Starting || s.status == Running =>
      match s.pid {
        Some(pid) => {
          // Ruby do_kill semantics: TERM, brief grace period, then KILL.
          // graceful_cancel(100) sends the default signal and force-kills
          // after 100ms — matching the Ruby TERM + sleep(0.1) + KILL shape.
          let handler = @process.graceful_cancel(timeout=100)
          let _ = handler(pid) catch { _ => () }
          s.status = Killed
          true
        }
        None => {
          s.status = Killed
          true
        }
      }
    _ => false
  }
}

///|
/// Refresh a session (check if it's still alive).
pub fn TerminalSessionManager::refresh(id : Int) -> TerminalSession? {
  TerminalSessionManager::get(id)
}

///|
/// Remove a session from tracking.
pub fn TerminalSessionManager::forget(id : Int) -> Unit {
  let sessions = session_manager_state.sessions
  let mut idx = 0
  while idx < sessions.length() {
    if sessions[idx].id == id {
      ignore(sessions.remove(idx))
      return
    }
    idx = idx + 1
  }
}

///|
/// Kill all tracked sessions.
pub async fn TerminalSessionManager::kill_all() -> Unit {
  for s in session_manager_state.sessions {
    if s.status == Starting || s.status == Running {
      match s.pid {
        Some(pid) => {
          let handler = @process.graceful_cancel(timeout=100)
          let _ = handler(pid) catch { _ => () }
        }
        None => ()
      }
      s.status = Killed
    }
  }
}

///|
/// Get session count.
pub fn TerminalSessionManager::count() -> Int {
  session_manager_state.sessions.length()
}
