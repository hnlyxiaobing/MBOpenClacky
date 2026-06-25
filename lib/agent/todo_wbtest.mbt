///| Tests for TodoManager and TodoStatus/TodoItem types.

///|
test "todo_status_to_string" {
  inspect(
    TodoStatus::Pending.to_string_value(),
    content=(
      #|pending
    ),
  )
  inspect(
    InProgress.to_string_value(),
    content=(
      #|in_progress
    ),
  )
  inspect(
    TodoStatus::Completed.to_string_value(),
    content=(
      #|completed
    ),
  )
  inspect(
    TodoStatus::Cancelled.to_string_value(),
    content=(
      #|cancelled
    ),
  )
  inspect(
    TodoStatus::Failed.to_string_value(),
    content=(
      #|failed
    ),
  )
}

///|
test "todo_status_from_string_valid" {
  inspect(TodoStatus::from_string("pending"), content="Some(Pending)")
  inspect(TodoStatus::from_string("in_progress"), content="Some(InProgress)")
  inspect(TodoStatus::from_string("completed"), content="Some(Completed)")
  inspect(TodoStatus::from_string("cancelled"), content="Some(Cancelled)")
  inspect(TodoStatus::from_string("failed"), content="Some(Failed)")
}

///|
test "todo_status_from_string_invalid" {
  inspect(TodoStatus::from_string("unknown"), content="None")
  inspect(TodoStatus::from_string(""), content="None")
}

///|
test "todo_manager_new" {
  let tm = TodoManager::new()
  inspect(tm.size(), content="0")
}

///|
test "todo_manager_add" {
  let tm = TodoManager::new()
  let item = tm.add("First task", "Do something")
  inspect(
    item.id,
    content=(
      #|task_1
    ),
  )
  inspect(
    item.title,
    content=(
      #|First task
    ),
  )
  inspect(
    item.description,
    content=(
      #|Do something
    ),
  )
  inspect(item.status, content="Pending")
  inspect(tm.size(), content="1")
}

///|
test "todo_manager_add_multiple_ids" {
  let tm = TodoManager::new()
  let t1 = tm.add("Task A", "")
  let t2 = tm.add("Task B", "")
  inspect(
    t1.id,
    content=(
      #|task_1
    ),
  )
  inspect(
    t2.id,
    content=(
      #|task_2
    ),
  )
  inspect(tm.size(), content="2")
}

///|
test "todo_manager_get" {
  let tm = TodoManager::new()
  let item = tm.add("Find me", "desc")
  let found = tm.get(item.id)
  inspect(found is None, content="false")
  match found {
    Some(t) =>
      inspect(
        t.title,
        content=(
          #|Find me
        ),
      )
    None => fail("Expected to find task")
  }
}

///|
test "todo_manager_get_missing" {
  let tm = TodoManager::new()
  let found = tm.get("task_999")
  inspect(found is None, content="true")
}

///|
test "todo_manager_update_status" {
  let tm = TodoManager::new()
  let item = tm.add("Task", "desc")
  let ok = tm.update_status(item.id, InProgress)
  inspect(ok, content="true")
  match tm.get(item.id) {
    Some(t) => inspect(t.status, content="InProgress")
    None => fail("Task should exist")
  }
}

///|
test "todo_manager_update_status_missing" {
  let tm = TodoManager::new()
  let ok = tm.update_status("task_999", Completed)
  inspect(ok, content="false")
}

///|
test "todo_manager_remove" {
  let tm = TodoManager::new()
  let item = tm.add("To be removed", "")
  inspect(tm.size(), content="1")
  let ok = tm.remove(item.id)
  inspect(ok, content="true")
  inspect(tm.size(), content="0")
}

///|
test "todo_manager_remove_missing" {
  let tm = TodoManager::new()
  let ok = tm.remove("task_999")
  inspect(ok, content="false")
}

///|
test "todo_manager_set_blocked_by" {
  let tm = TodoManager::new()
  let t1 = tm.add("Blocker", "")
  let t2 = tm.add("Blocked", "")
  let ok = tm.set_blocked_by(t2.id, [t1.id])
  inspect(ok, content="true")
  match tm.get(t2.id) {
    Some(t) => inspect(t.blocked_by.length(), content="1")
    None => fail("Task should exist")
  }
}

///|
test "todo_manager_is_blocked_true" {
  let tm = TodoManager::new()
  let t1 = tm.add("Dep", "")
  let t2 = tm.add("Depends on dep", "")
  let _ = tm.set_blocked_by(t2.id, [t1.id])
  // t1 is still Pending, so t2 is blocked
  inspect(tm.is_blocked(t2.id), content="true")
}

///|
test "todo_manager_is_blocked_false_after_complete" {
  let tm = TodoManager::new()
  let t1 = tm.add("Dep", "")
  let t2 = tm.add("Depends on dep", "")
  let _ = tm.set_blocked_by(t2.id, [t1.id])
  let _ = tm.update_status(t1.id, Completed)
  // t1 is Completed, so t2 is no longer blocked
  inspect(tm.is_blocked(t2.id), content="false")
}

///|
test "todo_manager_list_actionable" {
  let tm = TodoManager::new()
  let t1 = tm.add("Independent", "")
  let t2 = tm.add("Blocked task", "")
  let _ = tm.set_blocked_by(t2.id, [t1.id])
  let _t3 = tm.add("Another independent", "")
  let actionable = tm.list_actionable()
  // t1 and t3 are actionable (Pending and not blocked)
  // t2 is blocked by t1
  inspect(actionable.length(), content="2")
  // After completing t1, t2 becomes actionable
  let _ = tm.update_status(t1.id, Completed)
  let actionable2 = tm.list_actionable()
  // t3 and t2 are now actionable (t1 is completed, not pending)
  inspect(actionable2.length(), content="2")
}

///|
test "todo_manager_list_all" {
  let tm = TodoManager::new()
  let _ = tm.add("A", "")
  let _ = tm.add("B", "")
  let all = tm.list_all()
  inspect(all.length(), content="2")
}

///|
test "todo_manager_to_json_and_load" {
  let tm = TodoManager::new()
  let t1 = tm.add("Task One", "Description one")
  let _ = tm.update_status(t1.id, InProgress)
  let t2 = tm.add("Task Two", "Description two")
  let _ = tm.set_blocked_by(t2.id, [t1.id])
  let json = tm.to_json()

  let tm2 = TodoManager::new()
  tm2.load_from_json(json)
  inspect(tm2.size(), content="2")
  match tm2.get("task_1") {
    Some(t) => {
      inspect(
        t.title,
        content=(
          #|Task One
        ),
      )
      inspect(t.status, content="InProgress")
    }
    None => fail("task_1 should exist after load")
  }
  match tm2.get("task_2") {
    Some(t) => inspect(t.blocked_by.length(), content="1")
    None => fail("task_2 should exist after load")
  }
}

///|
test "todo_manager_summary_empty" {
  let tm = TodoManager::new()
  inspect(
    tm.summary(),
    content=(
      #|No tasks.
    ),
  )
}

///|
test "todo_manager_summary_non_empty" {
  let tm = TodoManager::new()
  let _ = tm.add("My Task", "Some description")
  let s = tm.summary()
  guard s.contains("My Task") else { fail("Summary should contain task title") }
  guard s.contains("pending") else { fail("Summary should contain status") }
}

///|
test "todo_manager_status_flow" {
  let tm = TodoManager::new()
  let item = tm.add("Workflow task", "")
  inspect(item.status, content="Pending")
  let _ = tm.update_status(item.id, InProgress)
  match tm.get(item.id) {
    Some(t) => inspect(t.status, content="InProgress")
    None => fail("Should exist")
  }
  let _ = tm.update_status(item.id, Completed)
  match tm.get(item.id) {
    Some(t) => inspect(t.status, content="Completed")
    None => fail("Should exist")
  }
}
