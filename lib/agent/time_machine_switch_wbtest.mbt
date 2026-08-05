///|
/// Tests for switch_to_task and the branch-coverage fix (SPEC-02 package 2).

///|
/// Look up an entry by path in a result set.
fn find_entry(entries : Array[SnapshotEntry], path : String) -> SnapshotEntry? {
  entries.iter().find_first(fn(e) { e.path == path })
}

///|
test "undo reverts files created exclusively by the undone task" {
  // Linear chain: task-001 touches a.mbt, task-002 creates new.mbt.
  // Undoing task-002 must mark new.mbt absent — the old parent branch
  // (restore_to_task_state over the parent chain only) never saw it.
  let tm = TimeMachineState::new("sess-sw1")
  ignore(tm.start_new_task(Some("Task 1")))
  tm.record_file_before_change("a.mbt", Some("orig-a"))
  tm.checkpoint_after("a.mbt", Some("after-t1-a"))
  ignore(tm.start_new_task(Some("Task 2")))
  tm.record_file_before_change("new.mbt", None) // did not exist before
  tm.checkpoint_after("new.mbt", Some("created-by-t2"))
  let result = tm.undo_last_task()
  match result {
    Ok(entries) => {
      // a.mbt back to after-t1 state
      assert_eq(
        find_entry(entries, "a.mbt").unwrap().content,
        Some("after-t1-a"),
      )
      // new.mbt must be reverted to absent
      let e = find_entry(entries, "new.mbt").unwrap()
      assert_true(e.is_absent)
      assert_eq(e.content, None)
    }
    Err(e) => fail("Expected Ok, got Err: " + e)
  }
  assert_eq(tm.current_task_id, Some("task-001"))
}

///|
test "switch_to_task across a branch reverts the abandoned task's files" {
  // Chain: task-001 → task-002 (touches b.mbt) → undo → task-003 branches
  // off task-001 and creates d.mbt. Switching back to task-002 must revert
  // d.mbt to absent and restore b.mbt to its after-t2 state.
  let tm = TimeMachineState::new("sess-sw2")
  ignore(tm.start_new_task(Some("Task 1")))
  tm.record_file_before_change("a.mbt", Some("orig-a"))
  tm.checkpoint_after("a.mbt", Some("after-t1-a"))
  ignore(tm.start_new_task(Some("Task 2")))
  tm.record_file_before_change("b.mbt", Some("orig-b"))
  tm.checkpoint_after("b.mbt", Some("after-t2-b"))
  ignore(tm.undo_last_task()) // back to task-001
  ignore(tm.start_new_task(Some("Task 3 branch")))
  tm.record_file_before_change("d.mbt", None)
  tm.checkpoint_after("d.mbt", Some("created-by-t3"))
  // Switch from the branch (task-003) back to task-002.
  let result = tm.switch_to_task("task-002")
  match result {
    Ok(entries) => {
      assert_eq(
        find_entry(entries, "b.mbt").unwrap().content,
        Some("after-t2-b"),
      )
      let d = find_entry(entries, "d.mbt").unwrap()
      assert_true(d.is_absent)
    }
    Err(e) => fail("Expected Ok, got Err: " + e)
  }
  assert_eq(tm.current_task_id, Some("task-002"))
}

///|
test "switch_to_task forward restores the target state (redo path)" {
  let tm = TimeMachineState::new("sess-sw3")
  ignore(tm.start_new_task(Some("Task 1")))
  tm.record_file_before_change("x.mbt", Some("orig"))
  tm.checkpoint_after("x.mbt", Some("after-t1"))
  ignore(tm.start_new_task(Some("Task 2")))
  tm.record_file_before_change("x.mbt", Some("after-t1"))
  tm.checkpoint_after("x.mbt", Some("after-t2"))
  ignore(tm.undo_last_task()) // current = task-001
  let result = tm.switch_to_task("task-002")
  match result {
    Ok(entries) =>
      assert_eq(find_entry(entries, "x.mbt").unwrap().content, Some("after-t2"))
    Err(e) => fail("Expected Ok, got Err: " + e)
  }
  assert_eq(tm.current_task_id, Some("task-002"))
}

///|
test "switch_to_task with unknown id fails and keeps current" {
  let tm = TimeMachineState::new("sess-sw4")
  ignore(tm.start_new_task(Some("Task 1")))
  let result = tm.switch_to_task("task-999")
  assert_true(result is Err(_))
  assert_eq(tm.current_task_id, Some("task-001"))
}

///|
test "history_with_status marks current, on-path and undone branch tasks" {
  let tm = TimeMachineState::new("sess-sw5")
  ignore(tm.start_new_task(Some("Task 1")))
  ignore(tm.start_new_task(Some("Task 2")))
  ignore(tm.undo_last_task()) // current = task-001, task-002 now undone
  ignore(tm.start_new_task(Some("Task 3 branch")))
  let entries = tm.history_with_status()
  assert_eq(entries.length(), 3)
  assert_eq(entries[0].status, TaskNavStatus::Past) // task-001
  assert_eq(entries[1].status, TaskNavStatus::Undone) // task-002
  assert_eq(entries[2].status, TaskNavStatus::Current) // task-003
  // task-001 has two children (task-002 and task-003) → branch marker.
  assert_true(entries[0].has_branches)
  assert_true(!entries[1].has_branches)
  assert_eq(entries[1].task_num, 2)
}

///|
test "task_num_of parses padded task ids" {
  assert_eq(task_num_of("task-001"), 1)
  assert_eq(task_num_of("task-042"), 42)
  assert_eq(task_num_of("task-1000"), 1000)
  assert_eq(task_num_of("garbage"), 0)
}
