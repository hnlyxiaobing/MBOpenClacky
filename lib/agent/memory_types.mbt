///|
/// Memory category classification for MemoryEntry.
pub(all) enum MemoryCategory {
  UserPreference
  ProjectInfo
  TaskSummary
  ExpertKnowledge
  LearnedSkill
} derive(Eq, Compare, Show, Debug)

///|
pub fn MemoryCategory::to_string_value(self : MemoryCategory) -> String {
  match self {
    UserPreference => "user_preference"
    ProjectInfo => "project_info"
    TaskSummary => "task_summary"
    ExpertKnowledge => "expert_knowledge"
    LearnedSkill => "learned_skill"
  }
}

///|
pub fn MemoryCategory::from_string(s : String) -> MemoryCategory? {
  match s {
    "user_preference" => Some(UserPreference)
    "project_info" => Some(ProjectInfo)
    "task_summary" => Some(TaskSummary)
    "expert_knowledge" => Some(ExpertKnowledge)
    "learned_skill" => Some(LearnedSkill)
    _ => None
  }
}

///|
impl ToJson for MemoryCategory with fn to_json(self) {
  self.to_string_value().to_json()
}

///|
impl FromJson for MemoryCategory with fn from_json(json, path) {
  match json {
    String(s) =>
      match MemoryCategory::from_string(s) {
        Some(c) => c
        None =>
          raise JsonDecodeError((path, "MemoryCategory: unknown value '\{s}'"))
      }
    _ => raise JsonDecodeError((path, "MemoryCategory: expected string"))
  }
}

///|
/// A single memory entry stored in the MemoryStore.
pub(all) struct MemoryEntry {
  id : String
  title : String
  content : String
  category : MemoryCategory
  keywords : Array[String]
  created_at : String
  updated_at : String
} derive(Eq, Debug)

///|
impl ToJson for MemoryEntry with fn to_json(self) {
  let kws : Array[Json] = self.keywords.map(k => k.to_json())
  Json::object({
    "id": self.id.to_json(),
    "title": self.title.to_json(),
    "content": self.content.to_json(),
    "category": self.category.to_json(),
    "keywords": kws.to_json(),
    "created_at": self.created_at.to_json(),
    "updated_at": self.updated_at.to_json(),
  })
}

///|
impl FromJson for MemoryEntry with fn from_json(json, path) {
  match json {
    Object(map) => {
      let id = match map.get("id") {
        Some(String(s)) => s
        _ => raise JsonDecodeError((path, "MemoryEntry: missing 'id'"))
      }
      let title = match map.get("title") {
        Some(String(s)) => s
        _ => raise JsonDecodeError((path, "MemoryEntry: missing 'title'"))
      }
      let content = match map.get("content") {
        Some(String(s)) => s
        _ => raise JsonDecodeError((path, "MemoryEntry: missing 'content'"))
      }
      let category = match map.get("category") {
        Some(String(s)) =>
          match MemoryCategory::from_string(s) {
            Some(c) => c
            None => UserPreference
          }
        _ => UserPreference
      }
      let keywords : Array[String] = match map.get("keywords") {
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
      { id, title, content, category, keywords, created_at, updated_at }
    }
    _ => raise JsonDecodeError((path, "MemoryEntry: expected object"))
  }
}
