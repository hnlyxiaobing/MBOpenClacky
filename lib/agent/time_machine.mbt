///| Time Machine implementation for task snapshot/undo/redo.

///|
let _absent_marker : String = ".mbopenclacky-absent"

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
      Ok(self.collect_chain_state(chain))
    }
  }
}

///|
/// Compute the workspace state after the last task of `chain` completed.
///
/// `chain` is an ancestor chain (target first, root last). For every file
/// ever touched in the chain, take the after entry of the task NEAREST to
/// the chain head; files with no after entry fall back to the earliest
/// before entry, then to absent.
fn TimeMachineState::collect_chain_state(
  self : TimeMachineState,
  chain : Array[String],
) -> Array[SnapshotEntry] {
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
  result
}

///|
/// Compute the workspace state after switching to `target_id`, covering
/// files of tasks that will be UNAPPLIED by the switch.
///
/// The plain ancestor-chain state (`collect_chain_state`) only knows files
/// touched by the target's ancestors. When switching backward (or across
/// branches), files touched exclusively by tasks being left — e.g. a file
/// created by the undone task — are invisible to the chain and would stay
/// on disk unrestored. For those, revert to the before entry recorded by
/// the unapplied task closest to the common ancestor (i.e. the file state
/// right after the common ancestor).
fn TimeMachineState::compute_switch_entries(
  self : TimeMachineState,
  target_id : String,
) -> Array[SnapshotEntry] {
  let chain_t = self.build_ancestor_chain(target_id)
  let base = self.collect_chain_state(chain_t)
  let cur = match self.current_task_id {
    None => return base
    Some(id) => id
  }
  if cur == target_id {
    return base
  }
  let chain_c = self.build_ancestor_chain(cur)
  // Least common ancestor: first task of cur's chain also in target's chain.
  let mut lca : String? = None
  for id in chain_c {
    if array_contains(chain_t, id) {
      lca = Some(id)
      break
    }
  }
  // Unapplied tasks: cur's chain up to (excluding) the LCA; the whole chain
  // when the trees share no ancestor.
  let unapplied : Array[String] = []
  for id in chain_c {
    match lca {
      Some(l) if id == l => break
      _ => unapplied.push(id)
    }
  }
  // Files already covered by the target chain keep their target state.
  let handled : Array[String] = []
  for entry in base {
    handled.push(entry.path)
  }
  let result : Array[SnapshotEntry] = []
  for entry in base {
    result.push(entry)
  }
  // Scan unapplied tasks from closest-to-LCA outward: the first before
  // entry seen for a file is its state right after the LCA.
  let mut i = unapplied.length() - 1
  while i >= 0 {
    match self.find_task(unapplied[i]) {
      Some(t) =>
        for entry in t.before_entries {
          if !array_contains(handled, entry.path) {
            handled.push(entry.path)
            result.push(entry)
          }
        }
      None => ()
    }
    i = i - 1
  }
  result
}

///|
/// Switch the active task to an arbitrary historical task (Ruby
/// time_machine.rb switch_to_task): computes the full target workspace
/// state — including reverting files of tasks that become unapplied — and
/// makes `task_id` current. This single entry covers both undo (target
/// before current) and redo (target after current).
pub fn TimeMachineState::switch_to_task(
  self : TimeMachineState,
  task_id : String,
) -> Result[Array[SnapshotEntry], String] {
  match self.find_task(task_id) {
    None => Err("Task not found: " + task_id)
    Some(_) => {
      let entries = self.compute_switch_entries(task_id)
      self.current_task_id = Some(task_id)
      Ok(entries)
    }
  }
}

///|
/// Apply restored snapshot entries to the workspace: write file content
/// back, delete files that should be absent. Returns the number of files
/// applied, or the first error encountered.
pub fn apply_snapshot_entries(
  entries : Array[SnapshotEntry],
) -> Result[Int, String] {
  let mut applied = 0
  for entry in entries {
    if entry.is_absent {
      if @fs.path_exists(entry.path) {
        @fs.remove_file(entry.path) catch {
          e =>
            return Err("failed to remove \{entry.path}: \{@debug.to_string(e)}")
        }
        applied = applied + 1
      }
    } else {
      match entry.content {
        Some(content) => {
          @fs.write_string_to_file(entry.path, content) catch {
            e =>
              return Err(
                "failed to write \{entry.path}: \{@debug.to_string(e)}",
              )
          }
          applied = applied + 1
        }
        None => ()
      }
    }
  }
  Ok(applied)
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
        Some(t) =>
          // Delegate to the unified switch entry so files touched only by
          // the undone task are reverted too (the old parent branch called
          // restore_to_task_state(parent), which never saw them).
          match t.parent_id {
            Some(parent_id) => self.switch_to_task(parent_id)
            None => {
              // No parent - restore to original state (before entries of
              // the root task, the only applied one).
              self.current_task_id = None
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

///|
/// Redo a previously undone task.
pub fn TimeMachineState::redo_task(
  self : TimeMachineState,
  task_id : String,
) -> Result[Array[SnapshotEntry], String] {
  // Redo is a forward switch to the task — same unified entry.
  self.switch_to_task(task_id)
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
/// Navigation status of a task relative to the active chain (Ruby
/// get_task_history): on the current path, the current task itself, or an
/// undone/abandoned branch.
pub(all) enum TaskNavStatus {
  Current
  Past
  Undone
} derive(Eq, Debug)

///|
/// A task entry enriched for the Time Machine navigation menu.
pub(all) struct TaskHistoryEntry {
  /// Task identifier ("task-001").
  task_id : String
  /// Numeric task counter (for undo/redo comparison and display).
  task_num : Int
  /// Short summary (description or fallback).
  summary : String
  /// Status relative to the active chain.
  status : TaskNavStatus
  /// Whether more than one child branches off this task.
  has_branches : Bool
} derive(Debug)

///|
/// Parse the numeric counter out of a "task-NNN" identifier (0 if unknown).
pub fn task_num_of(task_id : String) -> Int {
  if !task_id.has_prefix("task-") {
    return 0
  }
  let digits = task_id[5:].to_owned()
  @string.parse_int(digits) catch {
    _ => 0
  }
}

///|
/// Get the last 10 tasks enriched with navigation status for the Time
/// Machine menu (Ruby get_task_history: current / on-path / undone markers
/// and branch detection).
pub fn TimeMachineState::history_with_status(
  self : TimeMachineState,
) -> Array[TaskHistoryEntry] {
  let chain : Array[String] = match self.current_task_id {
    Some(cur) => self.build_ancestor_chain(cur)
    None => []
  }
  let result : Array[TaskHistoryEntry] = []
  for t in self.get_task_history() {
    let status = match self.current_task_id {
      Some(cur) if cur == t.task_id => TaskNavStatus::Current
      _ =>
        if array_contains(chain, t.task_id) {
          TaskNavStatus::Past
        } else {
          TaskNavStatus::Undone
        }
    }
    let mut children = 0
    for other in self.tasks {
      if other.parent_id == Some(t.task_id) {
        children = children + 1
      }
    }
    let num = task_num_of(t.task_id)
    let summary = match t.description {
      Some(d) if d.length() > 0 => d
      _ => "Task \{num}"
    }
    result.push({
      task_id: t.task_id,
      task_num: num,
      summary,
      status,
      has_branches: children > 1,
    })
  }
  result
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
