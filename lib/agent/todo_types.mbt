///|
/// Status of a todo task item.
pub(all) enum TodoStatus {
  Pending
  InProgress
  Completed
  Cancelled
  Failed
} derive(Eq, Compare, Show, Debug)

///|
pub fn TodoStatus::to_string_value(self : TodoStatus) -> String {
  match self {
    Pending => "pending"
    InProgress => "in_progress"
    Completed => "completed"
    Cancelled => "cancelled"
    Failed => "failed"
  }
}

///|
pub fn TodoStatus::from_string(s : String) -> TodoStatus? {
  match s {
    "pending" => Some(Pending)
    "in_progress" => Some(InProgress)
    "completed" => Some(Completed)
    "cancelled" => Some(Cancelled)
    "failed" => Some(Failed)
    _ => None
  }
}

///|
impl ToJson for TodoStatus with fn to_json(self) {
  self.to_string_value().to_json()
}

///|
impl FromJson for TodoStatus with fn from_json(json, path) {
  match json {
    String(s) =>
      match TodoStatus::from_string(s) {
        Some(st) => st
        None =>
          raise JsonDecodeError((path, "TodoStatus: unknown value '\{s}'"))
      }
    _ => raise JsonDecodeError((path, "TodoStatus: expected string"))
  }
}

///|
/// A single actionable task in the TodoManager.
pub(all) struct TodoItem {
  id : String
  title : String
  description : String
  mut status : TodoStatus
  blocked_by : Array[String]
  created_at : String
  mut updated_at : String
} derive(Eq, Debug)

///|
impl ToJson for TodoItem with fn to_json(self) {
  let deps : Array[Json] = self.blocked_by.map(d => d.to_json())
  Json::object({
    "id": self.id.to_json(),
    "title": self.title.to_json(),
    "description": self.description.to_json(),
    "status": self.status.to_json(),
    "blocked_by": deps.to_json(),
    "created_at": self.created_at.to_json(),
    "updated_at": self.updated_at.to_json(),
  })
}

///|
impl FromJson for TodoItem with fn from_json(json, path) {
  match json {
    Object(map) => {
      let id = match map.get("id") {
        Some(String(s)) => s
        _ => raise JsonDecodeError((path, "TodoItem: missing 'id'"))
      }
      let title = match map.get("title") {
        Some(String(s)) => s
        _ => raise JsonDecodeError((path, "TodoItem: missing 'title'"))
      }
      let description = match map.get("description") {
        Some(String(s)) => s
        _ => ""
      }
      let status = match map.get("status") {
        Some(String(s)) =>
          match TodoStatus::from_string(s) {
            Some(st) => st
            None => Pending
          }
        _ => Pending
      }
      let blocked_by : Array[String] = match map.get("blocked_by") {
        Some(Array(items)) => {
          let arr : Array[String] = []
          for item in items {
            match item {
              String(s) => arr.push(s)
              _ => ()
            }
          }
          arr
        }
        _ => []
      }
      let created_at = match map.get("created_at") {
        Some(String(s)) => s
        _ => ""
      }
      let updated_at = match map.get("updated_at") {
        Some(String(s)) => s
        _ => ""
      }
      { id, title, description, status, blocked_by, created_at, updated_at }
    }
    _ => raise JsonDecodeError((path, "TodoItem: expected object"))
  }
}
