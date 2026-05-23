///|
/// In-memory store for agent memory entries.
///
/// Supports CRUD operations and simple keyword/title-based search.
/// Serialization allows round-trip to JSON for persistence.
pub(all) struct MemoryStore {
  mut entries : Array[MemoryEntry]
  storage_path : String
  mut next_id : Int
}

///|
pub fn MemoryStore::new(storage_path : String) -> MemoryStore {
  { entries: [], storage_path, next_id: 1 }
}

///|
/// Generate the next unique memory ID.
fn MemoryStore::gen_id(self : MemoryStore) -> String {
  let id = "mem_" + self.next_id.to_string()
  self.next_id = self.next_id + 1
  id
}

///|
/// Add a new memory entry and return it.
pub fn MemoryStore::add(
  self : MemoryStore,
  title : String,
  content : String,
  category : MemoryCategory,
  keywords : Array[String],
) -> MemoryEntry {
  let id = self.gen_id()
  let ts = current_timestamp_ms()
  let entry : MemoryEntry = {
    id,
    title,
    content,
    category,
    keywords,
    created_at: ts,
    updated_at: ts,
  }
  self.entries.push(entry)
  entry
}

///|
/// Update the content of an existing entry by ID.
/// Returns true if found and updated, false if not found.
pub fn MemoryStore::update(
  self : MemoryStore,
  id : String,
  content : String,
) -> Bool {
  let ts = current_timestamp_ms()
  let mut found = false
  let new_entries : Array[MemoryEntry] = []
  for e in self.entries {
    if e.id == id {
      found = true
      new_entries.push({
        id: e.id,
        title: e.title,
        content,
        category: e.category,
        keywords: e.keywords,
        created_at: e.created_at,
        updated_at: ts,
      })
    } else {
      new_entries.push(e)
    }
  }
  self.entries = new_entries
  found
}

///|
/// Delete an entry by ID.
/// Returns true if found and deleted, false if not found.
pub fn MemoryStore::delete(self : MemoryStore, id : String) -> Bool {
  let before = self.entries.length()
  self.entries = self.entries.filter(fn(e) { e.id != id })
  self.entries.length() < before
}

///|
/// Get a single entry by ID.
pub fn MemoryStore::get(self : MemoryStore, id : String) -> MemoryEntry? {
  self.entries.iter().find_first(fn(e) { e.id == id })
}

///|
/// Search entries by query substring (case-insensitive) against title and keywords.
/// Optionally filter by category.
pub fn MemoryStore::search(
  self : MemoryStore,
  query : String,
  category : MemoryCategory?,
) -> Array[MemoryEntry] {
  let q = query.to_lower()
  self.entries.filter(fn(e) {
    let cat_ok = match category {
      Some(c) => e.category == c
      None => true
    }
    if not(cat_ok) {
      return false
    }
    if e.title.to_lower().contains(q) {
      return true
    }
    let mut kw_match = false
    for kw in e.keywords {
      if kw.to_lower().contains(q) {
        kw_match = true
        break
      }
    }
    kw_match
  })
}

///|
/// Return all entries.
pub fn MemoryStore::all(self : MemoryStore) -> Array[MemoryEntry] {
  self.entries
}

///|
/// Return all entries in a given category.
pub fn MemoryStore::by_category(
  self : MemoryStore,
  category : MemoryCategory,
) -> Array[MemoryEntry] {
  self.entries.filter(fn(e) { e.category == category })
}

///|
/// Return the number of entries.
pub fn MemoryStore::size(self : MemoryStore) -> Int {
  self.entries.length()
}

///|
/// Serialize all entries to JSON.
pub fn MemoryStore::to_json(self : MemoryStore) -> Json {
  let items : Array[Json] = self.entries.map(e => e.to_json())
  Json::object({
    "storage_path": self.storage_path.to_json(),
    "next_id": self.next_id.to_json(),
    "entries": items.to_json(),
  })
}

///|
/// Restore entries from a JSON snapshot.
pub fn MemoryStore::load_from_json(self : MemoryStore, json : Json) -> Unit {
  match json {
    Object(map) => {
      match map.get("next_id") {
        Some(Number(d, ..)) => self.next_id = d.to_int()
        _ => ()
      }
      match map.get("entries") {
        Some(Array(items)) => {
          self.entries = []
          for item in items {
            let entry : MemoryEntry = @json.from_json(item) catch {
              _ => continue
            }
            self.entries.push(entry)
          }
        }
        _ => ()
      }
    }
    _ => ()
  }
}

///|
/// Generate a human-readable summary of all stored memories.
/// Suitable for injection into system prompts.
pub fn MemoryStore::summary(self : MemoryStore) -> String {
  if self.entries.length() == 0 {
    return "No memories stored."
  }
  let mut buf = "## Stored Memories (\{self.entries.length()} entries)\n"
  for e in self.entries {
    buf = buf +
      "\n### [\{e.category.to_string_value()}] \{e.title} (id: \{e.id})\n"
    buf = buf + "\{e.content}\n"
    if e.keywords.length() > 0 {
      buf = buf + "Keywords: " + e.keywords.join(", ") + "\n"
    }
  }
  buf
}
