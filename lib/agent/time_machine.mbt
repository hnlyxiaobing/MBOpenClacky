///| Time Machine implementation for task snapshot/undo/redo.

///|
let absent_marker : String = ".mbopenclacky-absent"

///|
/// Create a new TimeMachine for a session.
pub fn TimeMachineState::new(session_id : String) -> TimeMachineState {
  let snapshot_dir = "~/.mbopenclacky/snapshots/" + session_id
  {
    session_id,
    tasks: [],
    current_task_id: None,
    task_counter: 0,
    snapshot_dir,
  }
}

///|
/// Start a new task, creating a snapshot boundary.
pub fn TimeMachineState::start_new_task(
  self : TimeMachineState,
  description : String?,
) -> String {
  self.task_counter = self.task_counter + 1
  let counter_str = self.task_counter.to_string()
  let padded = if self.task_counter < 10 {
    "00" + counter_str
  } else if self.task_counter < 100 {
    "0" + counter_str
  } else {
    counter_str
  }
  let task_id = "task-" + padded
  let parent_id = self.current_task_id
  let snapshot : TaskSnapshot = {
    task_id,
    parent_id,
    before_entries: [],
    after_entries: [],
    created_at: current_time_ms().to_int(),
    description,
  }
  self.tasks.push(snapshot)
  self.current_task_id = Some(task_id)
  task_id
}

///|
/// Record a file's state before it's changed (called on first touch).
pub fn TimeMachineState::record_file_before_change(
  self : TimeMachineState,
  path : String,
  content : String?,
) -> Unit {
  let task : TaskSnapshot? = match self.current_task_id {
    Some(tid) => self.find_task(tid)
    None => None
  }
  match task {
    Some(t) => {
      // Only record if not already recorded in current task's before_entries
      let mut already_recorded = false
      for entry in t.before_entries {
        if entry.path == path {
          already_recorded = true
          break
        }
      }
      if !already_recorded {
        let is_absent = content is None
        let entry : SnapshotEntry = { path, content, is_absent }
        t.before_entries.push(entry)
      }
    }
    None => ()
  }
}

///|
/// Checkpoint the current task's after state.
pub fn TimeMachineState::checkpoint_after(
  self : TimeMachineState,
  path : String,
  content : String?,
) -> Unit {
  let task : TaskSnapshot? = match self.current_task_id {
    Some(tid) => self.find_task(tid)
    None => None
  }
  match task {
    Some(t) => {
      // Replace existing after entry for same path, or add new
      let mut found_idx : Int = -1
      for i = 0; i < t.after_entries.length(); i = i + 1 {
        if t.after_entries[i].path == path {
          found_idx = i
          break
        }
      }
      let is_absent = content is None
      let entry : SnapshotEntry = { path, content, is_absent }
      if found_idx >= 0 {
        t.after_entries[found_idx] = entry
      } else {
        t.after_entries.push(entry)
      }
    }
    None => ()
  }
}

///|
/// Restore workspace to the state after a specific task completed.
pub fn TimeMachineState::restore_to_task_state(
  self : TimeMachineState,
  task_id : String,
) -> Result[Array[SnapshotEntry], String] {
  let target = self.find_task(task_id)
  match target {
    None => Err("Task not found: " + task_id)
    Some(_) => {
      // Build ancestor chain from target task to root
      let chain = self.build_ancestor_chain(task_id)
      // Collect all files ever touched in ancestor chain
      let file_paths : Array[String] = []
      for ancestor_id in chain {
        match self.find_task(ancestor_id) {
          Some(t) => {
            for entry in t.before_entries {
              if !array_contains(file_paths, entry.path) {
                file_paths.push(entry.path)
              }
            }
            for entry in t.after_entries {
              if !array_contains(file_paths, entry.path) {
                file_paths.push(entry.path)
              }
            }
          }
          None => ()
        }
      }
      // For each file, find the nearest ancestor's after entry
      let result : Array[SnapshotEntry] = []
      for path in file_paths {
        let mut found = false
        // Search from target task backward through ancestors
        for ancestor_id in chain {
          match self.find_task(ancestor_id) {
            Some(t) =>
              for entry in t.after_entries {
                if entry.path == path {
                  result.push(entry)
                  found = true
                  break
                }
              }
            None => ()
          }
          if found {
            break
          }
        }
        // If no ancestor has it: use earliest before (original state)
        if !found {
          let last_idx = chain.length() - 1
          if last_idx >= 0 {
            let earliest_id = chain[last_idx]
            match self.find_task(earliest_id) {
              Some(t) =>
                for entry in t.before_entries {
                  if entry.path == path {
                    result.push(entry)
                    found = true
                    break
                  }
                }
              None => ()
            }
          }
        }
        // fallback: absent file if still not found
        if !found {
          result.push({ path, content: None, is_absent: true })
        }
      }
      Ok(result)
    }
  }
}

///|
/// Undo the last active task.
pub fn TimeMachineState::undo_last_task(
  self : TimeMachineState,
) -> Result[Array[SnapshotEntry], String] {
  match self.current_task_id {
    None => Err("No active task to undo")
    Some(tid) => {
      let task = self.find_task(tid)
      match task {
        None => Err("Current task not found: " + tid)
        Some(t) => {
          // Set current to parent
          self.current_task_id = t.parent_id
          // Restore to parent task's after state
          match t.parent_id {
            Some(parent_id) => self.restore_to_task_state(parent_id)
            None => {
              // No parent - restore to original state (before entries of first task)
              let result : Array[SnapshotEntry] = []
              for entry in t.before_entries {
                result.push(entry)
              }
              Ok(result)
            }
          }
        }
      }
    }
  }
}

///|
/// Redo a previously undone task.
pub fn TimeMachineState::redo_task(
  self : TimeMachineState,
  task_id : String,
) -> Result[Array[SnapshotEntry], String] {
  let task = self.find_task(task_id)
  match task {
    None => Err("Task not found: " + task_id)
    Some(_) => {
      // Re-activate the task
      self.current_task_id = Some(task_id)
      // Restore to that task's after state
      self.restore_to_task_state(task_id)
    }
  }
}

///|
/// Get task history for UI display (max 10 entries).
pub fn TimeMachineState::get_task_history(
  self : TimeMachineState,
) -> Array[TaskSnapshot] {
  let len = self.tasks.length()
  if len <= 10 {
    self.tasks
  } else {
    let result : Array[TaskSnapshot] = []
    for i = len - 10; i < len; i = i + 1 {
      result.push(self.tasks[i])
    }
    result
  }
}

///|
/// Build ancestor chain from a task to root (inclusive, target first).
fn TimeMachineState::build_ancestor_chain(
  self : TimeMachineState,
  task_id : String,
) -> Array[String] {
  let chain : Array[String] = []
  let mut current_id : String? = Some(task_id)
  // Limit iterations to prevent infinite loops
  let mut limit = self.tasks.length() + 1
  while limit > 0 {
    match current_id {
      None => break
      Some(id) => {
        chain.push(id)
        match self.find_task(id) {
          Some(t) => current_id = t.parent_id
          None => break
        }
      }
    }
    limit = limit - 1
  }
  chain
}

///|
/// Find a task by ID.
fn TimeMachineState::find_task(
  self : TimeMachineState,
  task_id : String,
) -> TaskSnapshot? {
  self.tasks.iter().find_first(fn(t) { t.task_id == task_id })
}

///|
/// Helper: check if an array contains a string value.
fn array_contains(arr : Array[String], value : String) -> Bool {
  for item in arr {
    if item == value {
      return true
    }
  }
  false
}
