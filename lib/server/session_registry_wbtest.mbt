///|
test "SessionRegistry new empty" {
  let reg = SessionRegistry::new()
  @debug.debug_inspect(reg.count(), content="0")
  @debug.debug_inspect(reg.is_full(), content="false")
}

///|
test "register adds session" {
  let reg = SessionRegistry::new()
  let wid : WorkerId = { id: 1, name: "w1" }
  let res = reg.register("s1", wid, created_at="2024-01-01T00:00:00Z")
  @debug.debug_inspect(res, content="Ok(())")
  @debug.debug_inspect(reg.count(), content="1")
}

///|
test "register duplicate fails" {
  let reg = SessionRegistry::new()
  let wid : WorkerId = { id: 1, name: "w1" }
  let _ = reg.register("s1", wid)
  let res = reg.register("s1", wid)
  @debug.debug_inspect(
    res,
    content=(
      #|Err("Session already registered: s1")
    ),
  )
}

///|
test "register full registry fails" {
  let reg = SessionRegistry::new(max_sessions=1)
  let wid : WorkerId = { id: 1, name: "w1" }
  let _ = reg.register("s1", wid)
  let res = reg.register("s2", wid)
  @debug.debug_inspect(
    res,
    content=(
      #|Err("Registry is full: max_sessions=1")
    ),
  )
}

///|
test "unregister removes session" {
  let reg = SessionRegistry::new()
  let wid : WorkerId = { id: 1, name: "w1" }
  let _ = reg.register("s1", wid, created_at="2024-01-01T00:00:00Z")
  let res = reg.unregister("s1")
  @debug.debug_inspect(res is Ok(_), content="true")
  @debug.debug_inspect(reg.count(), content="0")
}

///|
test "unregister missing fails" {
  let reg = SessionRegistry::new()
  let res = reg.unregister("nonexistent")
  @debug.debug_inspect(res is Err(_), content="true")
  @debug.debug_inspect(
    res.unwrap_err(),
    content=(
      #|"Session not found: nonexistent"
    ),
  )
}

///|
test "find existing session" {
  let reg = SessionRegistry::new()
  let wid : WorkerId = { id: 1, name: "w1" }
  let _ = reg.register("s1", wid, created_at="2024-01-01T00:00:00Z")
  let found = reg.find("s1")
  @debug.debug_inspect(found is Some(_), content="true")
}

///|
test "find missing returns None" {
  let reg = SessionRegistry::new()
  let found = reg.find("missing")
  @debug.debug_inspect(found is None, content="true")
}

///|
test "find_by_worker filters correctly" {
  let reg = SessionRegistry::new()
  let w1 : WorkerId = { id: 1, name: "w1" }
  let w2 : WorkerId = { id: 2, name: "w2" }
  let _ = reg.register("s1", w1)
  let _ = reg.register("s2", w2)
  let _ = reg.register("s3", w1)
  let results = reg.find_by_worker(w1)
  @debug.debug_inspect(results.length(), content="2")
}

///|
test "migrate changes worker" {
  let reg = SessionRegistry::new()
  let w1 : WorkerId = { id: 1, name: "w1" }
  let w2 : WorkerId = { id: 2, name: "w2" }
  let _ = reg.register("s1", w1)
  let res = reg.migrate("s1", w2)
  @debug.debug_inspect(res, content="Ok(())")
  let entry = reg.find("s1")
  @debug.debug_inspect(entry.unwrap().worker_id.id, content="2")
}

///|
test "migrate missing session fails" {
  let reg = SessionRegistry::new()
  let w2 : WorkerId = { id: 2, name: "w2" }
  let res = reg.migrate("missing", w2)
  @debug.debug_inspect(
    res,
    content=(
      #|Err("Session not found: missing")
    ),
  )
}

///|
test "touch updates activity time" {
  let reg = SessionRegistry::new()
  let wid : WorkerId = { id: 1, name: "w1" }
  let _ = reg.register("s1", wid, created_at="2024-01-01T00:00:00Z")
  let res = reg.touch("s1", "2024-01-01T01:00:00Z")
  @debug.debug_inspect(res, content="Ok(())")
  let entry = reg.find("s1")
  @debug.debug_inspect(
    entry.unwrap().last_activity,
    content=(
      #|"2024-01-01T01:00:00Z"
    ),
  )
}

///|
test "list_active returns all ids" {
  let reg = SessionRegistry::new()
  let wid : WorkerId = { id: 1, name: "w1" }
  let _ = reg.register("s1", wid)
  let _ = reg.register("s2", wid)
  let ids = reg.list_active()
  @debug.debug_inspect(ids.length(), content="2")
}

///|
test "count reflects size" {
  let reg = SessionRegistry::new()
  let wid : WorkerId = { id: 1, name: "w1" }
  @debug.debug_inspect(reg.count(), content="0")
  let _ = reg.register("s1", wid)
  @debug.debug_inspect(reg.count(), content="1")
  let _ = reg.register("s2", wid)
  @debug.debug_inspect(reg.count(), content="2")
}

///|
test "is_full at capacity" {
  let reg = SessionRegistry::new(max_sessions=2)
  let wid : WorkerId = { id: 1, name: "w1" }
  let _ = reg.register("s1", wid)
  @debug.debug_inspect(reg.is_full(), content="false")
  let _ = reg.register("s2", wid)
  @debug.debug_inspect(reg.is_full(), content="true")
}

///|
test "cleanup_inactive removes old" {
  let reg = SessionRegistry::new()
  let wid : WorkerId = { id: 1, name: "w1" }
  let _ = reg.register("s1", wid, created_at="2024-01-01T00:00:00Z")
  let _ = reg.register("s2", wid, created_at="2024-06-01T00:00:00Z")
  // Touch s2 to keep it alive (same as current_time)
  let _ = reg.touch("s2", "2024-06-01T00:00:00Z")
  let removed = reg.cleanup_inactive("2024-06-01T00:00:00Z", 3600)
  @debug.debug_inspect(removed.length(), content="1")
  @debug.debug_inspect(
    removed[0],
    content=(
      #|"s1"
    ),
  )
  @debug.debug_inspect(reg.count(), content="1")
}

///|
test "unregister_by_worker removes all" {
  let reg = SessionRegistry::new()
  let w1 : WorkerId = { id: 1, name: "w1" }
  let w2 : WorkerId = { id: 2, name: "w2" }
  let _ = reg.register("s1", w1)
  let _ = reg.register("s2", w1)
  let _ = reg.register("s3", w2)
  let removed = reg.unregister_by_worker(w1)
  @debug.debug_inspect(removed.length(), content="2")
  @debug.debug_inspect(reg.count(), content="1")
}

///|
test "set_metadata and get_metadata" {
  let reg = SessionRegistry::new()
  let wid : WorkerId = { id: 1, name: "w1" }
  let _ = reg.register("s1", wid)
  let res = reg.set_metadata("s1", "role", "admin")
  @debug.debug_inspect(res, content="Ok(())")
  let val = reg.get_metadata("s1", "role")
  @debug.debug_inspect(
    val,
    content=(
      #|Some("admin")
    ),
  )
  let missing = reg.get_metadata("s1", "unknown")
  @debug.debug_inspect(missing, content="None")
}

///|
test "registry_stats correct" {
  let reg = SessionRegistry::new(max_sessions=10)
  let wid : WorkerId = { id: 1, name: "w1" }
  let _ = reg.register("s1", wid)
  let _ = reg.register("s2", wid)
  let _ = reg.register("s3", wid)
  let stats = reg.registry_stats()
  @debug.debug_inspect(stats, content="(3, 10, 7)")
}
