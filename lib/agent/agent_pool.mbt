///|
/// Pool of sub-agent handles with concurrency control.
pub(all) struct AgentPool {
  mut handles : Array[SubAgentHandle]
  max_running : Int
  max_idle : Int
}

///|
pub fn AgentPool::new(max_running : Int, max_idle : Int) -> AgentPool {
  { handles: [], max_running, max_idle }
}

///|
/// Return true if a new sub-agent can be spawned (active count < max_running).
pub fn AgentPool::can_spawn(self : AgentPool) -> Bool {
  self.active_count() < self.max_running
}

///|
/// Add a sub-agent handle to the pool.
pub fn AgentPool::add(self : AgentPool, handle : SubAgentHandle) -> Unit {
  self.handles.push(handle)
}

///|
/// Get a handle by ID.
pub fn AgentPool::get(self : AgentPool, id : String) -> SubAgentHandle? {
  self.handles.iter().find_first(fn(h) { h.id == id })
}

///|
/// Collect and remove all finished (Completed or Failed) handles.
/// Returns the collected handles.
pub fn AgentPool::collect_completed(self : AgentPool) -> Array[SubAgentHandle] {
  let done = self.handles.filter(fn(h) { h.is_done() })
  self.handles = self.handles.filter(fn(h) { !h.is_done() })
  done
}

///|
/// Count handles that are actively Running or Pending.
pub fn AgentPool::active_count(self : AgentPool) -> Int {
  let mut count = 0
  for h in self.handles {
    if h.status == Running || h.status == Pending {
      count = count + 1
    }
  }
  count
}

///|
/// Return true when all handles in the pool are done.
pub fn AgentPool::all_done(self : AgentPool) -> Bool {
  if self.handles.length() == 0 {
    return true
  }
  let mut done = true
  for h in self.handles {
    if !h.is_done() {
      done = false
      break
    }
  }
  done
}

///|
/// Return the total number of handles (active + done).
pub fn AgentPool::size(self : AgentPool) -> Int {
  self.handles.length()
}

///|
/// Generate a summary of the pool state.
pub fn AgentPool::summary(self : AgentPool) -> String {
  let total = self.handles.length()
  if total == 0 {
    return "Agent pool: empty"
  }
  let mut running = 0
  let mut pending = 0
  let mut completed = 0
  let mut failed = 0
  for h in self.handles {
    match h.status {
      Running => running = running + 1
      Pending => pending = pending + 1
      Completed => completed = completed + 1
      Failed => failed = failed + 1
    }
  }
  "Agent pool: \{total} total | \{running} running | \{pending} pending | \{completed} completed | \{failed} failed (max_running=\{self.max_running}, max_idle=\{self.max_idle})"
}
