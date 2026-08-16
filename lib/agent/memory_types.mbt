///|
/// Memory category classification for MemoryEntry.
pub(all) enum MemoryCategory {
  UserPreference
  ProjectInfo
  TaskSummary
  ExpertKnowledge
  LearnedSkill
} derive(Eq, Compare, Debug)

///|
pub extend MemoryCategory with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend MemoryCategory with @moonbitlang/core/json.FromJson::{from_json}

///|
pub extend MemoryCategory with Compare::{op_lt, op_le, op_ge, compare, op_gt}

///|
pub extend MemoryCategory with Eq::{not_equal, equal}

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
pub impl FromJson for MemoryCategory with fn from_json(json, path) {
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
pub extend MemoryEntry with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub extend MemoryEntry with Eq::{not_equal, equal}

///|
impl ToJson for MemoryEntry with fn to_json(self) {
  let kws : Array[Json] = self.keywords.map(k => ToJson::to_json(k))
  Json::object({
    "id": ToJson::to_json(self.id),
    "title": ToJson::to_json(self.title),
    "content": ToJson::to_json(self.content),
    "category": ToJson::to_json(self.category),
    "keywords": ToJson::to_json(kws),
    "created_at": ToJson::to_json(self.created_at),
    "updated_at": ToJson::to_json(self.updated_at),
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
