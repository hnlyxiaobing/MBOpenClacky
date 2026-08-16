///| Terminal session manager: tracks background and interactive sessions.

///| Reference: D:/MoonBit/openclacky/lib/clacky/tools/terminal/session_manager.rb

///|

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
/// Kill a session by ID. Returns true if the session was found and killed.
pub fn TerminalSessionManager::kill(id : Int) -> Bool {
  match TerminalSessionManager::get(id) {
    Some(s) if s.status == Starting || s.status == Running => {
      s.status = Killed
      true
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
pub fn TerminalSessionManager::kill_all() -> Unit {
  for s in session_manager_state.sessions {
    if s.status == Starting || s.status == Running {
      s.status = Killed
    }
  }
}

///|
/// Get session count.
pub fn TerminalSessionManager::count() -> Int {
  session_manager_state.sessions.length()
}
