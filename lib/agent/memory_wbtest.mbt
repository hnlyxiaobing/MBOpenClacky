///| Tests for MemoryStore and MemoryCategory/MemoryEntry types.

///|
test "memory_category_to_string" {
  inspect(
    UserPreference.to_string_value(),
    content=(
      #|user_preference
    ),
  )
  inspect(
    ProjectInfo.to_string_value(),
    content=(
      #|project_info
    ),
  )
  inspect(
    TaskSummary.to_string_value(),
    content=(
      #|task_summary
    ),
  )
  inspect(
    ExpertKnowledge.to_string_value(),
    content=(
      #|expert_knowledge
    ),
  )
  inspect(
    LearnedSkill.to_string_value(),
    content=(
      #|learned_skill
    ),
  )
}

///|
test "memory_category_from_string_valid" {
  inspect(
    MemoryCategory::from_string("user_preference"),
    content="Some(UserPreference)",
  )
  inspect(
    MemoryCategory::from_string("project_info"),
    content="Some(ProjectInfo)",
  )
  inspect(
    MemoryCategory::from_string("task_summary"),
    content="Some(TaskSummary)",
  )
  inspect(
    MemoryCategory::from_string("expert_knowledge"),
    content="Some(ExpertKnowledge)",
  )
  inspect(
    MemoryCategory::from_string("learned_skill"),
    content="Some(LearnedSkill)",
  )
}

///|
test "memory_category_from_string_invalid" {
  inspect(MemoryCategory::from_string("unknown"), content="None")
  inspect(MemoryCategory::from_string(""), content="None")
}

///|
test "memory_store_new" {
  let store = MemoryStore::new("/tmp/memory.json")
  inspect(store.size(), content="0")
  inspect(
    store.storage_path,
    content=(
      #|/tmp/memory.json
    ),
  )
}

///|
test "memory_store_add" {
  let store = MemoryStore::new("/tmp/mem")
  let e = store.add("Test title", "Test content", ProjectInfo, ["key1", "key2"])
  inspect(
    e.id,
    content=(
      #|mem_1
    ),
  )
  inspect(
    e.title,
    content=(
      #|Test title
    ),
  )
  inspect(
    e.content,
    content=(
      #|Test content
    ),
  )
  inspect(e.category, content="ProjectInfo")
  inspect(store.size(), content="1")
}

///|
test "memory_store_add_multiple_ids" {
  let store = MemoryStore::new("/tmp/mem")
  let e1 = store.add("First", "Content 1", UserPreference, [])
  let e2 = store.add("Second", "Content 2", TaskSummary, [])
  inspect(
    e1.id,
    content=(
      #|mem_1
    ),
  )
  inspect(
    e2.id,
    content=(
      #|mem_2
    ),
  )
  inspect(store.size(), content="2")
}

///|
test "memory_store_get" {
  let store = MemoryStore::new("/tmp/mem")
  let e = store.add("Find Me", "Content", ExpertKnowledge, ["expert"])
  let found = store.get(e.id)
  inspect(found is None, content="false")
  match found {
    Some(entry) =>
      inspect(
        entry.title,
        content=(
          #|Find Me
        ),
      )
    None => fail("Expected to find entry")
  }
}

///|
test "memory_store_get_missing" {
  let store = MemoryStore::new("/tmp/mem")
  let found = store.get("mem_999")
  inspect(found is None, content="true")
}

///|
test "memory_store_update" {
  let store = MemoryStore::new("/tmp/mem")
  let e = store.add("Title", "Old content", LearnedSkill, ["old"])
  let ok = store.update(e.id, "New content")
  inspect(ok, content="true")
  match store.get(e.id) {
    Some(updated) =>
      inspect(
        updated.content,
        content=(
          #|New content
        ),
      )
    None => fail("Entry should exist after update")
  }
}

///|
test "memory_store_update_missing" {
  let store = MemoryStore::new("/tmp/mem")
  let ok = store.update("mem_999", "New content")
  inspect(ok, content="false")
}

///|
test "memory_store_delete" {
  let store = MemoryStore::new("/tmp/mem")
  let e = store.add("Delete Me", "content", ProjectInfo, [])
  inspect(store.size(), content="1")
  let ok = store.delete(e.id)
  inspect(ok, content="true")
  inspect(store.size(), content="0")
}

///|
test "memory_store_delete_missing" {
  let store = MemoryStore::new("/tmp/mem")
  let ok = store.delete("mem_999")
  inspect(ok, content="false")
}

///|
test "memory_store_search_by_title" {
  let store = MemoryStore::new("/tmp/mem")
  let _ = store.add("MoonBit tips", "content", ExpertKnowledge, [])
  let _ = store.add("Ruby notes", "content", ProjectInfo, [])
  let results = store.search("moonbit", None)
  inspect(results.length(), content="1")
  inspect(
    results[0].title,
    content=(
      #|MoonBit tips
    ),
  )
}

///|
test "memory_store_search_by_keyword" {
  let store = MemoryStore::new("/tmp/mem")
  let _ = store.add("Some title", "content", UserPreference, [
    "moonbit", "compiler",
  ])
  let _ = store.add("Other title", "content", UserPreference, ["ruby", "rails"])
  let results = store.search("compiler", None)
  inspect(results.length(), content="1")
  inspect(
    results[0].keywords[0],
    content=(
      #|moonbit
    ),
  )
}

///|
test "memory_store_search_no_results" {
  let store = MemoryStore::new("/tmp/mem")
  let _ = store.add("Title", "content", TaskSummary, ["key"])
  let results = store.search("nonexistent_xyz", None)
  inspect(results.length(), content="0")
}

///|
test "memory_store_search_with_category_filter" {
  let store = MemoryStore::new("/tmp/mem")
  let _ = store.add("Skill entry", "content", LearnedSkill, ["skill"])
  let _ = store.add("Expert entry", "content", ExpertKnowledge, ["skill"])
  let results = store.search("skill", Some(LearnedSkill))
  inspect(results.length(), content="1")
  inspect(results[0].category, content="LearnedSkill")
}

///|
test "memory_store_by_category" {
  let store = MemoryStore::new("/tmp/mem")
  let _ = store.add("A", "content", ProjectInfo, [])
  let _ = store.add("B", "content", UserPreference, [])
  let _ = store.add("C", "content", ProjectInfo, [])
  let results = store.by_category(ProjectInfo)
  inspect(results.length(), content="2")
}

///|
test "memory_store_all" {
  let store = MemoryStore::new("/tmp/mem")
  let _ = store.add("A", "c1", ProjectInfo, [])
  let _ = store.add("B", "c2", LearnedSkill, [])
  let all = store.all()
  inspect(all.length(), content="2")
}

///|
test "memory_store_to_json_and_load" {
  let store = MemoryStore::new("/tmp/mem")
  let _ = store.add("Title One", "Content one", ExpertKnowledge, ["kw1"])
  let _ = store.add("Title Two", "Content two", TaskSummary, ["kw2", "kw3"])
  let json = store.to_json()

  let store2 = MemoryStore::new("/tmp/mem")
  store2.load_from_json(json)
  inspect(store2.size(), content="2")
  match store2.get("mem_1") {
    Some(e) => {
      inspect(
        e.title,
        content=(
          #|Title One
        ),
      )
      inspect(e.category, content="ExpertKnowledge")
    }
    None => fail("Entry mem_1 should exist after load")
  }
  match store2.get("mem_2") {
    Some(e) =>
      inspect(
        e.title,
        content=(
          #|Title Two
        ),
      )
    None => fail("Entry mem_2 should exist after load")
  }
}

///|
test "memory_store_summary_empty" {
  let store = MemoryStore::new("/tmp/mem")
  inspect(
    store.summary(),
    content=(
      #|No memories stored.
    ),
  )
}

///|
test "memory_store_summary_non_empty" {
  let store = MemoryStore::new("/tmp/mem")
  let _ = store.add("Hello", "World", ProjectInfo, ["alpha"])
  let s = store.summary()
  guard s.contains("Hello") else { fail("Summary should contain title") }
  guard s.contains("project_info") else {
    fail("Summary should contain category")
  }
  guard s.contains("alpha") else { fail("Summary should contain keywords") }
}
