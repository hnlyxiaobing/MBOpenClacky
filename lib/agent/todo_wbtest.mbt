///| Tests for TodoManager and TodoStatus/TodoItem types.

///|
test "todo_status_to_string" {
  @debug.debug_inspect(
    TodoStatus::Pending.to_string_value(),
    content=(
      #|"pending"
    ),
  )
  @debug.debug_inspect(
    InProgress.to_string_value(),
    content=(
      #|"in_progress"
    ),
  )
  @debug.debug_inspect(
    TodoStatus::Completed.to_string_value(),
    content=(
      #|"completed"
    ),
  )
  @debug.debug_inspect(
    TodoStatus::Cancelled.to_string_value(),
    content=(
      #|"cancelled"
    ),
  )
  @debug.debug_inspect(
    TodoStatus::Failed.to_string_value(),
    content=(
      #|"failed"
    ),
  )
}

///|
test "todo_status_from_string_valid" {
  @debug.debug_inspect(
    TodoStatus::from_string("pending"),
    content="Some(Pending)",
  )
  @debug.debug_inspect(
    TodoStatus::from_string("in_progress"),
    content="Some(InProgress)",
  )
  @debug.debug_inspect(
    TodoStatus::from_string("completed"),
    content="Some(Completed)",
  )
  @debug.debug_inspect(
    TodoStatus::from_string("cancelled"),
    content="Some(Cancelled)",
  )
  @debug.debug_inspect(
    TodoStatus::from_string("failed"),
    content="Some(Failed)",
  )
}

///|
test "todo_status_from_string_invalid" {
  @debug.debug_inspect(TodoStatus::from_string("unknown"), content="None")
  @debug.debug_inspect(TodoStatus::from_string(""), content="None")
}

///|
test "todo_manager_new" {
  let tm = TodoManager::new()
  @debug.debug_inspect(tm.size(), content="0")
}

///|
test "todo_manager_add" {
  let tm = TodoManager::new()
  let item = tm.add("First task", "Do something")
  @debug.debug_inspect(
    item.id,
    content=(
      #|"task_1"
    ),
  )
  @debug.debug_inspect(
    item.title,
    content=(
      #|"First task"
    ),
  )
  @debug.debug_inspect(
    item.description,
    content=(
      #|"Do something"
    ),
  )
  @debug.debug_inspect(item.status, content="Pending")
  @debug.debug_inspect(tm.size(), content="1")
}

///|
test "todo_manager_add_multiple_ids" {
  let tm = TodoManager::new()
  let t1 = tm.add("Task A", "")
  let t2 = tm.add("Task B", "")
  @debug.debug_inspect(
    t1.id,
    content=(
      #|"task_1"
    ),
  )
  @debug.debug_inspect(
    t2.id,
    content=(
      #|"task_2"
    ),
  )
  @debug.debug_inspect(tm.size(), content="2")
}

///|
test "todo_manager_get" {
  let tm = TodoManager::new()
  let item = tm.add("Find me", "desc")
  let found = tm.get(item.id)
  @debug.debug_inspect(found is None, content="false")
  match found {
    Some(t) =>
      @debug.debug_inspect(
        t.title,
        content=(
          #|"Find me"
        ),
      )
    None => fail("Expected to find task")
  }
}

///|
test "todo_manager_get_missing" {
  let tm = TodoManager::new()
  let found = tm.get("task_999")
  @debug.debug_inspect(found is None, content="true")
}

///|
test "todo_manager_update_status" {
  let tm = TodoManager::new()
  let item = tm.add("Task", "desc")
  let ok = tm.update_status(item.id, InProgress)
  @debug.debug_inspect(ok, content="true")
  match tm.get(item.id) {
    Some(t) => @debug.debug_inspect(t.status, content="InProgress")
    None => fail("Task should exist")
  }
}

///|
test "todo_manager_update_status_missing" {
  let tm = TodoManager::new()
  let ok = tm.update_status("task_999", Completed)
  @debug.debug_inspect(ok, content="false")
}

///|
test "todo_manager_remove" {
  let tm = TodoManager::new()
  let item = tm.add("To be removed", "")
  @debug.debug_inspect(tm.size(), content="1")
  let ok = tm.remove(item.id)
  @debug.debug_inspect(ok, content="true")
  @debug.debug_inspect(tm.size(), content="0")
}

///|
test "todo_manager_remove_missing" {
  let tm = TodoManager::new()
  let ok = tm.remove("task_999")
  @debug.debug_inspect(ok, content="false")
}

///|
test "todo_manager_set_blocked_by" {
  let tm = TodoManager::new()
  let t1 = tm.add("Blocker", "")
  let t2 = tm.add("Blocked", "")
  let ok = tm.set_blocked_by(t2.id, [t1.id])
  @debug.debug_inspect(ok, content="true")
  match tm.get(t2.id) {
    Some(t) => @debug.debug_inspect(t.blocked_by.length(), content="1")
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
  @debug.debug_inspect(tm.is_blocked(t2.id), content="true")
}

///|
test "todo_manager_is_blocked_false_after_complete" {
  let tm = TodoManager::new()
  let t1 = tm.add("Dep", "")
  let t2 = tm.add("Depends on dep", "")
  let _ = tm.set_blocked_by(t2.id, [t1.id])
  let _ = tm.update_status(t1.id, Completed)
  // t1 is Completed, so t2 is no longer blocked
  @debug.debug_inspect(tm.is_blocked(t2.id), content="false")
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
  @debug.debug_inspect(actionable.length(), content="2")
  // After completing t1, t2 becomes actionable
  let _ = tm.update_status(t1.id, Completed)
  let actionable2 = tm.list_actionable()
  // t3 and t2 are now actionable (t1 is completed, not pending)
  @debug.debug_inspect(actionable2.length(), content="2")
}

///|
test "todo_manager_list_all" {
  let tm = TodoManager::new()
  let _ = tm.add("A", "")
  let _ = tm.add("B", "")
  let all = tm.list_all()
  @debug.debug_inspect(all.length(), content="2")
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
  @debug.debug_inspect(tm2.size(), content="2")
  match tm2.get("task_1") {
    Some(t) => {
      @debug.debug_inspect(
        t.title,
        content=(
          #|"Task One"
        ),
      )
      @debug.debug_inspect(t.status, content="InProgress")
    }
    None => fail("task_1 should exist after load")
  }
  match tm2.get("task_2") {
    Some(t) => @debug.debug_inspect(t.blocked_by.length(), content="1")
    None => fail("task_2 should exist after load")
  }
}

///|
test "todo_manager_summary_empty" {
  let tm = TodoManager::new()
  @debug.debug_inspect(
    tm.summary(),
    content=(
      #|"No tasks."
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
  @debug.debug_inspect(item.status, content="Pending")
  let _ = tm.update_status(item.id, InProgress)
  match tm.get(item.id) {
    Some(t) => @debug.debug_inspect(t.status, content="InProgress")
    None => fail("Should exist")
  }
  let _ = tm.update_status(item.id, Completed)
  match tm.get(item.id) {
    Some(t) => @debug.debug_inspect(t.status, content="Completed")
    None => fail("Should exist")
  }
}

// ── execute_todo_tool (Ruby-aligned action dispatch) ─────────────────────────

///|
fn make_todo_call(action : String) -> @message.ToolCall {
  make_tool_call("call_todo", "todo_manager", "{\"action\": \"\{action}\"}")
}

///|
fn todo_args(pairs : Array[(String, Json)]) -> Map[String, Json] {
  let m : Map[String, Json] = Map([])
  for pair in pairs {
    let (k, v) = pair
    m[k] = v
  }
  m
}

///|
fn run_todo(
  action : String,
  pairs : Array[(String, Json)],
) -> (Agent, @message.ToolCall, ToolResultEntry) {
  let agent = make_test_agent()
  let call = make_tool_call(
    "call_todo",
    "todo_manager",
    "{\"action\": \"\{action}\"}",
  )
  let all : Array[(String, Json)] = [("action", ToJson::to_json(action))]
  let args = todo_args(all + pairs)
  (agent, call, agent.execute_todo_tool(call, args))
}

///|
test "execute_todo_add_single" {
  let (agent, _call, entry) = run_todo("add", [
    ("task", ToJson::to_json("First task")),
  ])
  assert_false(entry.is_error)
  guard entry.content.find("TODO added successfully") is Some(_) else {
    fail("should contain success message: \{entry.content}")
  }
  guard entry.content.find("\"id\":1") is Some(_) else {
    fail("todo should expose integer id 1: \{entry.content}")
  }
  guard entry.content.find("\"total\":1") is Some(_) else {
    fail("total should be 1: \{entry.content}")
  }
  guard entry.content.find("have NOT started working yet") is Some(_) else {
    fail("should contain add reminder: \{entry.content}")
  }
  @debug.assert_eq(agent.todo_manager.size(), 1)
}

///|
test "execute_todo_add_batch" {
  let (agent, _call, entry) = run_todo("add", [
    ("task", ToJson::to_json(["Task A", "Task B"])),
  ])
  assert_false(entry.is_error)
  guard entry.content.find("2 TODOs added successfully") is Some(_) else {
    fail("should count batched adds: \{entry.content}")
  }
  guard entry.content.find("\"total\":2") is Some(_) else {
    fail("total should be 2: \{entry.content}")
  }
  @debug.assert_eq(agent.todo_manager.size(), 2)
}

///|
test "execute_todo_add_blank_required" {
  let (_agent, _call, entry) = run_todo("add", [
    ("task", ToJson::to_json("   ")),
  ])
  assert_true(entry.is_error)
  guard entry.content.find("At least one task description is required")
    is Some(_) else {
    fail("blank tasks should error: \{entry.content}")
  }
}

///|
test "execute_todo_add_auto_clears_completed" {
  let agent = make_test_agent()
  let call = make_tool_call("c1", "todo_manager", "{}")
  let _ = agent.execute_todo_tool(
    call,
    todo_args([("action", "add".to_json()), ("task", "Old A".to_json())]),
  )
  let _ = agent.execute_todo_tool(
    call,
    todo_args([("action", "complete".to_json()), ("id", (1).to_json())]),
  )
  @debug.assert_eq(agent.todo_manager.size(), 0)
  let entry = agent.execute_todo_tool(
    call,
    todo_args([("action", "add".to_json()), ("task", "New B".to_json())]),
  )
  assert_false(entry.is_error)
  @debug.assert_eq(agent.todo_manager.size(), 1)
  guard entry.content.find("\"id\":1") is Some(_) else {
    fail("completed tasks should be cleared before adding: \{entry.content}")
  }
}

///|
test "execute_todo_list_empty" {
  let (_agent, _call, entry) = run_todo("list", [])
  assert_false(entry.is_error)
  guard entry.content.find("No TODO items") is Some(_) else {
    fail("empty list message: \{entry.content}")
  }
  guard entry.content.find("\"total\":0") is Some(_) else {
    fail("empty list total: \{entry.content}")
  }
}

///|
test "execute_todo_list_nonempty" {
  let (agent, _call, entry) = run_todo("list", [])
  let _ = agent.todo_manager.add("Task One", "")
  let _ = agent.todo_manager.add("Task Two", "")
  let entry2 = agent.execute_todo_tool(
    make_tool_call("c", "todo_manager", "{}"),
    todo_args([("action", "list".to_json())]),
  )
  assert_false(entry2.is_error)
  guard entry2.content.find("TODO list") is Some(_) else {
    fail("list message: \{entry2.content}")
  }
  guard entry2.content.find("\"pending\":2") is Some(_) else {
    fail("pending count: \{entry2.content}")
  }
  guard entry2.content.find("\"task\":\"Task One\"") is Some(_) else {
    fail("task text present: \{entry2.content}")
  }
  guard entry2.content.find("\"id\":1") is Some(_) else {
    fail("integer id present: \{entry2.content}")
  }
}

///|
test "execute_todo_complete_single" {
  let agent = make_test_agent()
  let call = make_tool_call("c", "todo_manager", "{}")
  let _ = agent.execute_todo_tool(
    call,
    todo_args([("action", "add".to_json()), ("task", "A".to_json())]),
  )
  let _ = agent.execute_todo_tool(
    call,
    todo_args([("action", "add".to_json()), ("task", "B".to_json())]),
  )
  let entry = agent.execute_todo_tool(
    call,
    todo_args([("action", "complete".to_json()), ("id", (1).to_json())]),
  )
  assert_false(entry.is_error)
  guard entry.content.find("Task marked as completed") is Some(_) else {
    fail("complete message: \{entry.content}")
  }
  guard entry.content.find("\"progress\":\"1/2\"") is Some(_) else {
    fail("progress: \{entry.content}")
  }
  guard entry.content.find("Next task: #2") is Some(_) else {
    fail("next task info: \{entry.content}")
  }
  guard entry.content.find("PROJECT-SPECIFIC RULES") is Some(_) else {
    fail("reminder present: \{entry.content}")
  }
}

///|
test "execute_todo_complete_all_auto_clears" {
  let agent = make_test_agent()
  let call = make_tool_call("c", "todo_manager", "{}")
  let _ = agent.execute_todo_tool(
    call,
    todo_args([("action", "add".to_json()), ("task", "A".to_json())]),
  )
  let _ = agent.execute_todo_tool(
    call,
    todo_args([("action", "add".to_json()), ("task", "B".to_json())]),
  )
  let entry = agent.execute_todo_tool(
    call,
    todo_args([
      ("action", "complete".to_json()),
      ("id", ToJson::to_json([1, 2])),
    ]),
  )
  assert_false(entry.is_error)
  guard entry.content.find("2 task(s) marked as completed") is Some(_) else {
    fail("batch complete message: \{entry.content}")
  }
  guard entry.content.find("All tasks completed and cleared! (2/2)") is Some(_) else {
    fail("completion message: \{entry.content}")
  }
  @debug.assert_eq(agent.todo_manager.size(), 0)
}

///|
test "execute_todo_complete_not_found" {
  let (_agent, _call, entry) = run_todo("complete", [("id", (99).to_json())])
  assert_true(entry.is_error)
  guard entry.content.find("Task not found: 99") is Some(_) else {
    fail("not found message: \{entry.content}")
  }
}

///|
test "execute_todo_complete_already_completed" {
  let agent = make_test_agent()
  let call = make_tool_call("c", "todo_manager", "{}")
  let _ = agent.execute_todo_tool(
    call,
    todo_args([("action", "add".to_json()), ("task", "A".to_json())]),
  )
  let _ = agent.execute_todo_tool(
    call,
    todo_args([("action", "add".to_json()), ("task", "B".to_json())]),
  )
  let _ = agent.execute_todo_tool(
    call,
    todo_args([("action", "complete".to_json()), ("id", (1).to_json())]),
  )
  let entry = agent.execute_todo_tool(
    call,
    todo_args([("action", "complete".to_json()), ("id", (1).to_json())]),
  )
  assert_false(entry.is_error)
  guard entry.content.find("Task already completed") is Some(_) else {
    fail("already completed message: \{entry.content}")
  }
  // Re-completing must not delete remaining tasks
  @debug.assert_eq(agent.todo_manager.size(), 2)
}

///|
test "execute_todo_complete_missing_id" {
  let (_agent, _call, entry) = run_todo("complete", [])
  assert_true(entry.is_error)
  guard entry.content.find("Task ID is required") is Some(_) else {
    fail("missing id message: \{entry.content}")
  }
}

///|
test "execute_todo_remove_single" {
  let agent = make_test_agent()
  let call = make_tool_call("c", "todo_manager", "{}")
  let _ = agent.execute_todo_tool(
    call,
    todo_args([("action", "add".to_json()), ("task", "A".to_json())]),
  )
  let _ = agent.execute_todo_tool(
    call,
    todo_args([("action", "add".to_json()), ("task", "B".to_json())]),
  )
  let entry = agent.execute_todo_tool(
    call,
    todo_args([("action", "remove".to_json()), ("id", (1).to_json())]),
  )
  assert_false(entry.is_error)
  guard entry.content.find("Task removed") is Some(_) else {
    fail("remove message: \{entry.content}")
  }
  guard entry.content.find("\"remaining\":1") is Some(_) else {
    fail("remaining count: \{entry.content}")
  }
  @debug.assert_eq(agent.todo_manager.size(), 1)
}

///|
test "execute_todo_remove_batch" {
  let agent = make_test_agent()
  let call = make_tool_call("c", "todo_manager", "{}")
  let _ = agent.execute_todo_tool(
    call,
    todo_args([("action", "add".to_json()), ("task", "A".to_json())]),
  )
  let _ = agent.execute_todo_tool(
    call,
    todo_args([("action", "add".to_json()), ("task", "B".to_json())]),
  )
  let _ = agent.execute_todo_tool(
    call,
    todo_args([("action", "add".to_json()), ("task", "C".to_json())]),
  )
  let entry = agent.execute_todo_tool(
    call,
    todo_args([("action", "remove".to_json()), ("id", ToJson::to_json([1, 3]))]),
  )
  assert_false(entry.is_error)
  guard entry.content.find("2 task(s) removed") is Some(_) else {
    fail("batch remove message: \{entry.content}")
  }
  guard entry.content.find("\"remaining\":1") is Some(_) else {
    fail("remaining count: \{entry.content}")
  }
  @debug.assert_eq(agent.todo_manager.size(), 1)
}

///|
test "execute_todo_remove_not_found" {
  let (_agent, _call, entry) = run_todo("remove", [("id", (99).to_json())])
  assert_true(entry.is_error)
  guard entry.content.find("Task not found: 99") is Some(_) else {
    fail("not found message: \{entry.content}")
  }
}

///|
test "execute_todo_clear" {
  let agent = make_test_agent()
  let call = make_tool_call("c", "todo_manager", "{}")
  let _ = agent.execute_todo_tool(
    call,
    todo_args([("action", "add".to_json()), ("task", "A".to_json())]),
  )
  let _ = agent.execute_todo_tool(
    call,
    todo_args([("action", "add".to_json()), ("task", "B".to_json())]),
  )
  let entry = agent.execute_todo_tool(
    call,
    todo_args([("action", "clear".to_json())]),
  )
  assert_false(entry.is_error)
  guard entry.content.find("All TODOs cleared") is Some(_) else {
    fail("clear message: \{entry.content}")
  }
  guard entry.content.find("\"cleared_count\":2") is Some(_) else {
    fail("cleared count: \{entry.content}")
  }
  @debug.assert_eq(agent.todo_manager.size(), 0)
}

///|
test "execute_todo_unknown_action" {
  let (_agent, _call, entry) = run_todo("explode", [])
  assert_true(entry.is_error)
  guard entry.content.find("Unknown action: explode") is Some(_) else {
    fail("unknown action message: \{entry.content}")
  }
}

///|
test "execute_todo_missing_action" {
  let agent = make_test_agent()
  let call = make_tool_call("c", "todo_manager", "{}")
  let entry = agent.execute_todo_tool(call, Map([]))
  assert_true(entry.is_error)
  guard entry.content.find("missing 'action'") is Some(_) else {
    fail("missing action message: \{entry.content}")
  }
}
