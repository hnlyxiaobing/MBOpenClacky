///| Tests for the Time Machine feature.

///|
test "time_machine_new" {
  let tm = TimeMachineState::new("session-abc")
  inspect(tm.session_id, content="session-abc")
  inspect(tm.tasks.length(), content="0")
  inspect(tm.current_task_id, content="None")
  inspect(tm.task_counter, content="0")
}

///|
test "start_new_task" {
  let tm = TimeMachineState::new("sess-1")
  let tid = tm.start_new_task(Some("First task"))
  inspect(tid, content="task-001")
  inspect(tm.task_counter, content="1")
  inspect(tm.current_task_id, content="Some(task-001)")
  inspect(tm.tasks.length(), content="1")
}

///|
test "start_multiple_tasks" {
  let tm = TimeMachineState::new("sess-2")
  let t1 = tm.start_new_task(Some("Task one"))
  let t2 = tm.start_new_task(Some("Task two"))
  let t3 = tm.start_new_task(None)
  inspect(t1, content="task-001")
  inspect(t2, content="task-002")
  inspect(t3, content="task-003")
  inspect(tm.task_counter, content="3")
  // Check parent chain
  inspect(tm.tasks[0].parent_id, content="None")
  inspect(tm.tasks[1].parent_id, content="Some(task-001)")
  inspect(tm.tasks[2].parent_id, content="Some(task-002)")
}

///|
test "record_file_before_change" {
  let tm = TimeMachineState::new("sess-3")
  let _ = tm.start_new_task(Some("Edit files"))
  tm.record_file_before_change("src/main.mbt", Some("old content"))
  inspect(tm.tasks[0].before_entries.length(), content="1")
  inspect(tm.tasks[0].before_entries[0].path, content="src/main.mbt")
  inspect(tm.tasks[0].before_entries[0].content, content="Some(old content)")
  inspect(tm.tasks[0].before_entries[0].is_absent, content="false")
}

///|
test "record_file_before_change_duplicate" {
  let tm = TimeMachineState::new("sess-4")
  let _ = tm.start_new_task(Some("Edit"))
  tm.record_file_before_change("file.mbt", Some("original"))
  tm.record_file_before_change("file.mbt", Some("should not overwrite"))
  // Should still be only one entry
  inspect(tm.tasks[0].before_entries.length(), content="1")
  inspect(tm.tasks[0].before_entries[0].content, content="Some(original)")
}

///|
test "record_absent_file" {
  let tm = TimeMachineState::new("sess-5")
  let _ = tm.start_new_task(Some("Create file"))
  tm.record_file_before_change("new_file.mbt", None)
  inspect(tm.tasks[0].before_entries[0].is_absent, content="true")
  inspect(tm.tasks[0].before_entries[0].content, content="None")
}

///|
test "checkpoint_after" {
  let tm = TimeMachineState::new("sess-6")
  let _ = tm.start_new_task(Some("Modify"))
  tm.checkpoint_after("src/main.mbt", Some("new content"))
  inspect(tm.tasks[0].after_entries.length(), content="1")
  inspect(tm.tasks[0].after_entries[0].content, content="Some(new content)")
  // Overwrite with updated content
  tm.checkpoint_after("src/main.mbt", Some("even newer"))
  inspect(tm.tasks[0].after_entries.length(), content="1")
  inspect(tm.tasks[0].after_entries[0].content, content="Some(even newer)")
}

///|
test "restore_to_task_state_simple" {
  let tm = TimeMachineState::new("sess-7")
  let tid = tm.start_new_task(Some("Simple edit"))
  tm.record_file_before_change("a.mbt", Some("before-a"))
  tm.checkpoint_after("a.mbt", Some("after-a"))
  let result = tm.restore_to_task_state(tid)
  match result {
    Ok(entries) => {
      inspect(entries.length(), content="1")
      inspect(entries[0].path, content="a.mbt")
      inspect(entries[0].content, content="Some(after-a)")
    }
    Err(e) => fail("Expected Ok, got Err: " + e)
  }
}

///|
test "restore_to_task_state_chain" {
  let tm = TimeMachineState::new("sess-8")
  // Task 1: modify a.mbt
  let t1 = tm.start_new_task(Some("Task 1"))
  tm.record_file_before_change("a.mbt", Some("original-a"))
  tm.checkpoint_after("a.mbt", Some("after-t1-a"))
  // Task 2: modify b.mbt
  let _ = tm.start_new_task(Some("Task 2"))
  tm.record_file_before_change("b.mbt", Some("original-b"))
  tm.checkpoint_after("b.mbt", Some("after-t2-b"))
  // Restore to task 1: should have a.mbt from t1, not b.mbt
  let result = tm.restore_to_task_state(t1)
  match result {
    Ok(entries) => {
      inspect(entries.length(), content="1")
      inspect(entries[0].path, content="a.mbt")
      inspect(entries[0].content, content="Some(after-t1-a)")
    }
    Err(e) => fail("Expected Ok, got Err: " + e)
  }
}

///|
test "restore_absent_file" {
  let tm = TimeMachineState::new("sess-9")
  let tid = tm.start_new_task(Some("Delete file"))
  tm.record_file_before_change("temp.mbt", Some("content"))
  tm.checkpoint_after("temp.mbt", None)
  let result = tm.restore_to_task_state(tid)
  match result {
    Ok(entries) => {
      inspect(entries.length(), content="1")
      inspect(entries[0].is_absent, content="true")
    }
    Err(e) => fail("Expected Ok, got Err: " + e)
  }
}

///|
test "undo_last_task" {
  let tm = TimeMachineState::new("sess-10")
  let _ = tm.start_new_task(Some("Task 1"))
  tm.record_file_before_change("x.mbt", Some("orig"))
  tm.checkpoint_after("x.mbt", Some("modified"))
  let result = tm.undo_last_task()
  match result {
    Ok(entries) => {
      // Should restore to before state
      inspect(entries.length(), content="1")
      inspect(entries[0].content, content="Some(orig)")
    }
    Err(e) => fail("Expected Ok, got Err: " + e)
  }
  inspect(tm.current_task_id, content="None")
}

///|
test "redo_task" {
  let tm = TimeMachineState::new("sess-11")
  let tid = tm.start_new_task(Some("Task 1"))
  tm.record_file_before_change("y.mbt", Some("orig"))
  tm.checkpoint_after("y.mbt", Some("changed"))
  let _ = tm.undo_last_task()
  // Now redo
  let result = tm.redo_task(tid)
  match result {
    Ok(entries) => {
      inspect(entries.length(), content="1")
      inspect(entries[0].content, content="Some(changed)")
    }
    Err(e) => fail("Expected Ok, got Err: " + e)
  }
  inspect(tm.current_task_id, content="Some(task-001)")
}

///|
test "get_task_history" {
  let tm = TimeMachineState::new("sess-12")
  let _ = tm.start_new_task(Some("T1"))
  let _ = tm.start_new_task(Some("T2"))
  let _ = tm.start_new_task(Some("T3"))
  let hist = tm.get_task_history()
  inspect(hist.length(), content="3")
}

///|
test "get_task_history_max_10" {
  let tm = TimeMachineState::new("sess-13")
  for i = 0; i < 15; i = i + 1 {
    let _ = tm.start_new_task(Some("Task " + i.to_string()))
  }
  let hist = tm.get_task_history()
  inspect(hist.length(), content="10")
  // Should be the last 10
  inspect(hist[0].task_id, content="task-006")
  inspect(hist[9].task_id, content="task-015")
}

///|
test "build_ancestor_chain" {
  let tm = TimeMachineState::new("sess-14")
  let _ = tm.start_new_task(Some("Root"))
  let _ = tm.start_new_task(Some("Child"))
  let _ = tm.start_new_task(Some("Grandchild"))
  let chain = tm.build_ancestor_chain("task-003")
  inspect(chain.length(), content="3")
  inspect(chain[0], content="task-003")
  inspect(chain[1], content="task-002")
  inspect(chain[2], content="task-001")
}

///|
test "task_counter_increment" {
  let tm = TimeMachineState::new("sess-15")
  inspect(tm.task_counter, content="0")
  let _ = tm.start_new_task(None)
  inspect(tm.task_counter, content="1")
  let _ = tm.start_new_task(None)
  inspect(tm.task_counter, content="2")
  let _ = tm.start_new_task(None)
  inspect(tm.task_counter, content="3")
}

///|
test "parent_child_relationship" {
  let tm = TimeMachineState::new("sess-16")
  let t1 = tm.start_new_task(Some("Parent"))
  let t2 = tm.start_new_task(Some("Child"))
  inspect(tm.tasks[0].parent_id, content="None")
  inspect(tm.tasks[1].parent_id, content="Some(task-001)")
  inspect(t1, content="task-001")
  inspect(t2, content="task-002")
}

///|
test "snapshot_dir_path" {
  let tm = TimeMachineState::new("my-session-123")
  inspect(tm.snapshot_dir, content="~/.mbopenclacky/snapshots/my-session-123")
}

///|
test "empty_time_machine" {
  let tm = TimeMachineState::new("empty")
  let result = tm.undo_last_task()
  match result {
    Err(msg) => inspect(msg, content="No active task to undo")
    Ok(_) => fail("Expected Err for empty time machine")
  }
  let hist = tm.get_task_history()
  inspect(hist.length(), content="0")
}

///|
test "find_task_not_found" {
  let tm = TimeMachineState::new("sess-17")
  let _ = tm.start_new_task(Some("Exists"))
  let result = tm.restore_to_task_state("nonexistent-task")
  match result {
    Err(msg) => inspect(msg, content="Task not found: nonexistent-task")
    Ok(_) => fail("Expected Err for missing task")
  }
}
