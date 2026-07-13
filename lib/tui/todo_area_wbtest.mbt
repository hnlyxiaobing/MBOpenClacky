///|
/// Tests for TodoArea rendering and visibility.

///|
test "todo_area: new is hidden and empty" {
  let todo = TodoArea::new()
  assert_true(todo.hidden)
  @debug.assert_eq(todo.items.length(), 0)
  @debug.assert_eq(todo.completed_count, 0)
  @debug.assert_eq(todo.total_count, 0)
}

///|
test "todo_area: render_lines empty when hidden" {
  let todo = TodoArea::new()
  // update sets hidden=false when items > 0, so re-hide after
  todo.update(
    [{ id: 1, title: "Task A", status: "pending", description: "" }],
    0,
    1,
  )
  todo.hide()
  let lines = todo.render_lines()
  @debug.assert_eq(lines.length(), 0)
}

///|
test "todo_area: render_lines empty when no items" {
  let todo = TodoArea::new()
  todo.show()
  let lines = todo.render_lines()
  @debug.assert_eq(lines.length(), 0)
}

///|
test "todo_area: render_lines shows header and items" {
  let todo = TodoArea::new()
  todo.show()
  todo.update(
    [
      { id: 1, title: "Task A", status: "pending", description: "" },
      { id: 2, title: "Task B", status: "completed", description: "" },
    ],
    1,
    2,
  )
  let lines = todo.render_lines()
  // Header + 2 items
  @debug.assert_eq(lines.length(), 3)
  assert_true(lines[0].contains("Tasks [1/2]"))
  assert_true(lines[1].contains("○ #1"))
  assert_true(lines[1].contains("Task A"))
  assert_true(lines[2].contains("✓ #2"))
  assert_true(lines[2].contains("Task B"))
}

///|
test "todo_area: status bullets" {
  let todo = TodoArea::new()
  todo.show()
  // Use max_display = 3, so only first 3 items render
  // Use 3 items to avoid truncation
  todo.update(
    [
      { id: 1, title: "Pending", status: "pending", description: "" },
      { id: 2, title: "InProgress", status: "in_progress", description: "" },
      { id: 3, title: "Done", status: "completed", description: "" },
    ],
    1,
    3,
  )
  let lines = todo.render_lines()
  assert_true(lines[1].contains("○")) // pending
  assert_true(lines[2].contains("●")) // in_progress
  assert_true(lines[3].contains("✓")) // completed
}

///|
test "todo_area: max_display truncation" {
  let todo = TodoArea::new()
  todo.show()
  // max_display = 3, but we add 5 items
  let items : Array[TodoDisplayItem] = []
  for i = 1; i <= 5; i = i + 1 {
    items.push({ id: i, title: "Task \{i}", status: "pending", description: "" })
  }
  todo.update(items, 0, 5)
  let lines = todo.render_lines()
  // Header + 3 items + "... and 2 more"
  @debug.assert_eq(lines.length(), 5)
  assert_true(lines[4].contains("... and 2 more"))
}

///|
test "todo_area: hide and show" {
  let todo = TodoArea::new()
  todo.update(
    [{ id: 1, title: "Task", status: "pending", description: "" }],
    0,
    1,
  )
  // update sets hidden=false when items > 0
  assert_false(todo.hidden)
  todo.hide()
  assert_true(todo.hidden)
  assert_false(todo.visible())
  todo.show()
  assert_false(todo.hidden)
  assert_true(todo.visible())
}

///|
test "todo_area: visible returns false when no items" {
  let todo = TodoArea::new()
  todo.show()
  assert_false(todo.visible())
}

///|
test "todo_area: update sets hidden to false when items exist" {
  let todo = TodoArea::new()
  assert_true(todo.hidden)
  todo.update(
    [{ id: 1, title: "Task", status: "pending", description: "" }],
    0,
    1,
  )
  assert_false(todo.hidden)
}

///|
test "todo_area: update with empty items keeps hidden state" {
  let todo = TodoArea::new()
  todo.show()
  todo.update([], 0, 0)
  // When items is empty, don't change hidden state (it stays shown)
  // But render_lines returns empty because items.length() == 0
  @debug.assert_eq(todo.render_lines().length(), 0)
}

///|
test "todo_area: slash command Todo variant exists" {
  // Verify the Todo variant is in the SlashCommand enum
  let cmd : SlashCommand = Todo
  let s = @debug.to_string(cmd)
  assert_true(s.contains("Todo"))
}
