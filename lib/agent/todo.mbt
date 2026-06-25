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
  let id = "task_" + self.next_id.to_string()
  self.next_id = self.next_id + 1
  id
}

///|
/// Add a new task and return it.
pub fn TodoManager::add(
  self : TodoManager,
  title : String,
  description : String,
) -> TodoItem {
  let id = self.gen_id()
  let ts = current_timestamp_ms()
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
  let ts = current_timestamp_ms()
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
  let ts = current_timestamp_ms()
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
  let items_json : Array[Json] = self.items.map(i => i.to_json())
  Json::object({
    "next_id": self.next_id.to_json(),
    "items": items_json.to_json(),
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
