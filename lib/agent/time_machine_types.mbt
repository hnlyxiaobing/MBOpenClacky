///| Types for the Time Machine feature (task snapshot/undo/redo).

///|
/// Task snapshot entry representing a file's state.
pub(all) struct SnapshotEntry {
  path : String
  content : String? // None means file was absent
  is_absent : Bool // marked with .mbopenclacky-absent
} derive(Eq, Debug, ToJson)

///|
/// A task's complete snapshot (before and after states).
pub(all) struct TaskSnapshot {
  task_id : String
  parent_id : String?
  mut before_entries : Array[SnapshotEntry]
  mut after_entries : Array[SnapshotEntry]
  created_at : Int // millisecond timestamp
  description : String?
} derive(Eq, Debug, ToJson)

///|
/// Task tree node for navigation.
pub(all) struct TaskNode {
  task_id : String
  parent_id : String?
  children : Array[String]
  is_active : Bool // not undone
} derive(Eq, Debug, ToJson)

///|
/// Time Machine state.
pub(all) struct TimeMachineState {
  session_id : String
  mut tasks : Array[TaskSnapshot]
  mut current_task_id : String?
  mut task_counter : Int
  snapshot_dir : String // ~/.mbopenclacky/snapshots/<session_id>/
} derive(Eq, Debug)
