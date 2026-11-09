///| Types for the Time Machine feature (task snapshot/undo/redo).

///|
/// Task snapshot entry representing a file's state.
#derive(Eq, Debug, ToJson)
pub(all) struct SnapshotEntry {
  path : String
  content : String? // None means file was absent
  is_absent : Bool // marked with .mbopenclacky-absent
}

///|
pub extend SnapshotEntry with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend SnapshotEntry with Eq::{not_equal, equal}

///|
pub extend SnapshotEntry with ToJson::{to_json}

///|
/// A task's complete snapshot (before and after states).
#derive(Eq, Debug, ToJson)
pub(all) struct TaskSnapshot {
  task_id : String
  parent_id : String?
  mut before_entries : Array[SnapshotEntry]
  mut after_entries : Array[SnapshotEntry]
  created_at : Int32 // millisecond timestamp
  description : String?
}

///|
pub extend TaskSnapshot with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend TaskSnapshot with Eq::{not_equal, equal}

///|
pub extend TaskSnapshot with ToJson::{to_json}

///|
/// Task tree node for navigation.
#derive(Eq, Debug, ToJson)
pub(all) struct TaskNode {
  task_id : String
  parent_id : String?
  children : Array[String]
  is_active : Bool // not undone
}

///|
pub extend TaskNode with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend TaskNode with Eq::{not_equal, equal}

///|
pub extend TaskNode with ToJson::{to_json}

///|
/// Time Machine state.
#derive(Eq, Debug)
pub(all) struct TimeMachineState {
  session_id : String
  mut tasks : Array[TaskSnapshot]
  mut current_task_id : String?
  mut task_counter : Int32
  snapshot_dir : String // ~/.mbopenclacky/snapshots/<session_id>/
}

///|
pub extend TimeMachineState with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend TimeMachineState with Eq::{not_equal, equal}
