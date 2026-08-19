///|
/// Task manager that tracks work items with dependency blocking.
pub(all) struct TodoManager {
  mut items : Array[TodoItem]
  mut next_id : Int
}

///|
pub fn TodoManager::new() -> TodoManager {
  { items: [], next_id: 1 }
}

///|
/// Generate the next unique task ID.
fn TodoManager::gen_id(self : TodoManager) -> String {
  // Ruby semantics: next id is always max existing id + 1 (1 when empty),
  // so cleared/removed task ids get reused after a wipe.
  let mut n = 1
  for item in self.items {
    let int_id = todo_int_id(item.id)
    if int_id >= n {
      n = int_id + 1
    }
  }
  "task_" + n.to_string()
}

///|
/// Convert a model-facing integer task id (as used by the tool schema)
/// into the internal `task_N` string id.
pub fn TodoManager::id_str(_self : TodoManager, n : Int) -> String {
  "task_" + n.to_string()
}

///|
/// Convert an internal `task_N` id back to the integer id exposed to the
/// model. Falls back to 0 if malformed.
pub fn todo_int_id(id : String) -> Int {
  let s = if id.has_prefix("task_") { id[5:].to_owned() } else { id }
  @string.parse_int(s) catch {
    _ => 0
  }
}

///|
/// Auto-clear completed tasks (Ruby add_todos semantics: old completed
/// items are dropped before adding new ones). Returns how many were
/// cleared.
pub fn TodoManager::clear_completed(self : TodoManager) -> Int {
  let before = self.items.length()
  self.items = self.items.filter(fn(item) { item.status != Completed })
  before - self.items.length()
}

///|
/// Mark several tasks completed in one call (Ruby complete_todos
/// semantics: tolerates already-completed and not-found ids).
/// Returns (completed_now, already_completed, not_found_ids).
pub fn TodoManager::complete_by_ids(
  self : TodoManager,
  ids : Array[Int],
) -> (Array[TodoItem], Array[TodoItem], Array[Int]) {
  let ts = current_timestamp_iso()
  let completed_now : Array[TodoItem] = []
  let already : Array[TodoItem] = []
  let not_found : Array[Int] = []
  for n in ids {
    let sid = self.id_str(n)
    let mut found = false
    for item in self.items {
      if item.id == sid {
        found = true
        if item.status == Completed {
          already.push(item)
        } else {
          item.status = Completed
          item.updated_at = ts
          completed_now.push(item)
        }
        break
      }
    }
    if !found {
      not_found.push(n)
    }
  }
  (completed_now, already, not_found)
}

///|
/// Remove several tasks in one call (Ruby remove_todos semantics).
/// Returns (removed, not_found_ids).
pub fn TodoManager::remove_by_ids(
  self : TodoManager,
  ids : Array[Int],
) -> (Array[TodoItem], Array[Int]) {
  let removed : Array[TodoItem] = []
  let not_found : Array[Int] = []
  let to_remove : Array[String] = []
  for n in ids {
    let sid = self.id_str(n)
    match self.get(sid) {
      None => not_found.push(n)
      Some(item) => {
        removed.push(item)
        to_remove.push(sid)
      }
    }
  }
  if to_remove.length() > 0 {
    self.items = self.items.filter(fn(item) { !to_remove.contains(item.id) })
  }
  (removed, not_found)
}

///|
/// Clear all tasks (Ruby clear_todos semantics). Returns cleared count.
pub fn TodoManager::clear_all(self : TodoManager) -> Int {
  let count = self.items.length()
  self.items = []
  count
}

///|
/// Render a task as the JSON object the model sees, aligned with the Ruby
/// todo_manager result schema (`id` as integer, `task` for the text).
pub fn todo_item_to_model_json(item : TodoItem) -> Json {
  Json::object({
    "id": todo_int_id(item.id).to_json(),
    "task": ToJson::to_json(item.title),
    "status": ToJson::to_json(item.status),
    "created_at": ToJson::to_json(item.created_at),
  })
}

///|
/// Render the full todo list as model-facing JSON (Ruby list_todos shape).
pub fn TodoManager::list_to_model_json(self : TodoManager) -> Json {
  let todos : Array[Json] = self.items.map(todo_item_to_model_json)
  let pending = self.items.filter(fn(i) { i.status == Pending }).length()
  let completed = self.items.filter(fn(i) { i.status == Completed }).length()
  Json::object({
    "message": "TODO list".to_json(),
    "todos": ToJson::to_json(todos),
    "total": self.items.length().to_json(),
    "pending": pending.to_json(),
    "completed": completed.to_json(),
  })
}

///|
/// The next pending task after a completion, or None when all done.
pub fn TodoManager::next_pending(self : TodoManager) -> TodoItem? {
  self.items.iter().find_first(fn(item) { item.status == Pending })
}

///|
/// Add a new task and return it.
pub fn TodoManager::add(
  self : TodoManager,
  title : String,
  description : String,
) -> TodoItem {
  let id = self.gen_id()
  let ts = current_timestamp_iso()
  let item : TodoItem = {
    id,
    title,
    description,
    status: Pending,
    blocked_by: [],
    created_at: ts,
    updated_at: ts,
  }
  self.items.push(item)
  item
}

///|
/// Update the status of a task by ID.
/// Returns true if found and updated.
pub fn TodoManager::update_status(
  self : TodoManager,
  id : String,
  status : TodoStatus,
) -> Bool {
  let ts = current_timestamp_iso()
  let mut found = false
  for item in self.items {
    if item.id == id {
      item.status = status
      item.updated_at = ts
      found = true
      break
    }
  }
  found
}

///|
/// Set the blocked_by dependency list for a task.
/// Returns true if the task was found.
pub fn TodoManager::set_blocked_by(
  self : TodoManager,
  id : String,
  deps : Array[String],
) -> Bool {
  let ts = current_timestamp_iso()
  let mut found = false
  let new_items : Array[TodoItem] = []
  for item in self.items {
    if item.id == id {
      found = true
      new_items.push({
        id: item.id,
        title: item.title,
        description: item.description,
        status: item.status,
        blocked_by: deps,
        created_at: item.created_at,
        updated_at: ts,
      })
    } else {
      new_items.push(item)
    }
  }
  self.items = new_items
  found
}

///|
/// Get a task by ID.
pub fn TodoManager::get(self : TodoManager, id : String) -> TodoItem? {
  self.items.iter().find_first(fn(item) { item.id == id })
}

///|
/// Check whether a task is blocked (any dependency is not Completed).
pub fn TodoManager::is_blocked(self : TodoManager, id : String) -> Bool {
  match self.get(id) {
    None => false
    Some(item) => {
      let mut blocked = false
      for dep_id in item.blocked_by {
        match self.get(dep_id) {
          None => {
            blocked = true
            break
          }
          Some(dep) =>
            if dep.status != Completed {
              blocked = true
              break
            }
        }
      }
      blocked
    }
  }
}

///|
/// Return tasks that are Pending and not blocked (all deps Completed).
pub fn TodoManager::list_actionable(self : TodoManager) -> Array[TodoItem] {
  self.items.filter(fn(item) {
    item.status == Pending && !self.is_blocked(item.id)
  })
}

///|
/// Return all tasks.
pub fn TodoManager::list_all(self : TodoManager) -> Array[TodoItem] {
  self.items
}

///|
/// Remove a task by ID.
/// Returns true if found and removed.
pub fn TodoManager::remove(self : TodoManager, id : String) -> Bool {
  let before = self.items.length()
  self.items = self.items.filter(fn(item) { item.id != id })
  self.items.length() < before
}

///|
/// Return the number of tasks.
pub fn TodoManager::size(self : TodoManager) -> Int {
  self.items.length()
}

///|
/// Generate a formatted summary of all tasks.
pub fn TodoManager::summary(self : TodoManager) -> String {
  if self.items.length() == 0 {
    return "No tasks."
  }
  let mut buf = "## Task List (\{self.items.length()} tasks)\n"
  for item in self.items {
    let blocked_mark = if self.is_blocked(item.id) { " [BLOCKED]" } else { "" }
    buf = buf +
      "\n- [\{item.status.to_string_value()}]\{blocked_mark} \{item.id}: \{item.title}\n"
    if item.description != "" {
      buf = buf + "  \{item.description}\n"
    }
    if item.blocked_by.length() > 0 {
      buf = buf + "  Depends on: " + item.blocked_by.join(", ") + "\n"
    }
  }
  buf
}

///|
/// Serialize the todo manager to JSON.
pub fn TodoManager::to_json(self : TodoManager) -> Json {
  let items_json : Array[Json] = self.items.map(i => ToJson::to_json(i))
  Json::object({
    "next_id": ToJson::to_json(self.next_id),
    "items": ToJson::to_json(items_json),
  })
}

///|
/// Restore the todo manager from a JSON snapshot.
pub fn TodoManager::load_from_json(self : TodoManager, json : Json) -> Unit {
  match json {
    Object(map) => {
      match map.get("next_id") {
        Some(Number(d, ..)) => self.next_id = d.to_int()
        _ => ()
      }
      match map.get("items") {
        Some(Array(arr)) => {
          self.items = []
          for item_json in arr {
            let item : TodoItem = @json.from_json(item_json) catch {
              _ => continue
            }
            self.items.push(item)
          }
        }
        _ => ()
      }
    }
    _ => ()
  }
}
