///|
/// White-box tests for session store persistence layout and the
/// three-tier capacity policy (decision 3/4/5).
///
/// All tests redirect USERPROFILE so they operate on a hermetic
/// `_build/.mbopenclacky/sessions/` directory.

///|
/// Redirect USERPROFILE to a temp dir so session files are hermetic.
fn ss_push_profile() -> String? {
  let old = @env.get_env_var("USERPROFILE")
  @env.set_env_var("USERPROFILE", "_build")
  old
}

///|
fn ss_pop_profile(old : String?) -> Unit {
  match old {
    Some(v) => @env.set_env_var("USERPROFILE", v)
    None => @env.set_env_var("USERPROFILE", "")
  }
}

///|
/// Minimal persisted SessionData for store tests.
fn ss_make_session(id : String, name : String) -> SessionData {
  {
    session_id: id,
    name,
    messages: [],
    stats: {
      total_iterations: 0,
      total_cost_usd: 0.0,
      total_tasks: 0,
      cost_source: "manual",
      cache_creation_input_tokens: 0,
      cache_read_input_tokens: 0,
      total_requests: 0,
      cache_hit_requests: 0,
    },
    working_dir: "/tmp",
    created_at: "2026-01-01T00:00:00+08:00",
    source: "manual",
    reasoning_effort: None,
    model_name: Some("gpt-4o"),
    model_config_id: None,
    channel_info: None,
    latest_latency_ms: None,
    latest_ttft_ms: None,
    time_machine: None,
    pending_error_rollback: false,
    model_base_url: "",
    last_status: "idle",
    last_error: "",
    error_code: None,
    top_up_url: None,
    raw_message: None,
    forked_from: None,
    chunk_count: 0,
    agent_profile: "general",
    sub_model: None,
    pinned: false,
    todos: None,
    updated_at: "2026-01-01T00:00:00+08:00",
    previous_total_tokens: 0,
    deleted_at: None,
  }
}

///|
/// New sessions are persisted as `<datetime>-<id8>.json` (decision 3) and
/// survive a save/load round trip with their new fields intact.
test "save_session writes datetime-prefixed file and round trips" {
  let old = ss_push_profile()
  let id = generate_session_id()
  let data = { ..ss_make_session(id, "roundtrip"), pinned: true }
  save_session(data) catch {
    _ => assert_true(false)
  }
  let dir = ensure_sessions_dir() catch {
    _ => {
      assert_true(false)
      ""
    }
  }
  let found = find_session_file(dir, id)
  assert_true(found is Some(_))
  // Filename must carry the `<datetime>-<id8>.json` layout.
  let fname = @path.Path::basename(@path.Path(found.unwrap())).to_owned()
  assert_true(fname.has_suffix("-" + id[:8].to_owned() + ".json"))
  assert_true(fname.length() > id.length())
  let loaded = load_session(id)
  @debug.assert_eq(loaded.unwrap().session_id, id)
  @debug.assert_eq(loaded.unwrap().pinned, true)
  @debug.assert_eq(loaded.unwrap().model_name, Some("gpt-4o"))
  delete_session(id)
  ss_pop_profile(old)
}

///|
/// Legacy files written as `<session_id>.json` (pre-alignment) must still
/// load (decision 3 backward compatibility).
test "load_session reads legacy session_id.json files" {
  let old = ss_push_profile()
  let id = generate_session_id()
  let dir = ensure_sessions_dir() catch {
    _ => {
      assert_true(false)
      ""
    }
  }
  let legacy = @path.Path::join(dir, @path.Path(id + ".json")).to_string()
  @fs.write_string_to_file(
    legacy,
    ToJson::to_json(ss_make_session(id, "legacy")).stringify(),
  )
  let loaded = load_session(id)
  @debug.assert_eq(loaded.unwrap().name, "legacy")
  delete_session(id)
  ss_pop_profile(old)
}

///|
/// list_sessions skips soft-deleted sessions (deleted_at set) and
/// derives the session_id from file content for new-format files.
test "list_sessions excludes soft-deleted sessions" {
  let old = ss_push_profile()
  let alive_id = generate_session_id()
  let gone_id = generate_session_id()
  let gone = {
    ..ss_make_session(gone_id, "gone"),
    deleted_at: Some("2026-01-01T00:00:00+08:00"),
  }
  save_session(ss_make_session(alive_id, "alive")) catch {
    _ => assert_true(false)
  }
  save_session(gone) catch {
    _ => assert_true(false)
  }
  let ids = list_sessions().map(fn(s) { s.session_id })
  assert_true(ids.contains(alive_id))
  assert_true(!ids.contains(gone_id))
  delete_session(alive_id)
  delete_session(gone_id)
  ss_pop_profile(old)
}

///|
/// find_session_file resolves both the legacy exact name and the new
/// `-<id8>.json` suffix layout.
test "find_session_file resolves new and legacy layouts" {
  let old = ss_push_profile()
  let id = generate_session_id()
  let dir = ensure_sessions_dir() catch {
    _ => {
      assert_true(false)
      ""
    }
  }
  // Legacy layout first.
  let legacy = @path.Path::join(dir, @path.Path(id + ".json")).to_string()
  @fs.write_string_to_file(legacy, "{}")
  @debug.assert_eq(find_session_file(dir, id), Some(legacy))
  @fs.remove_file(legacy) catch {
    _ => ()
  }
  // New layout: any file ending with `-<id8>.json` is matched.
  let new_name = "2026-08-18T10-00-00+08-00-" + id[:8].to_owned() + ".json"
  let new_path = @path.Path::join(dir, @path.Path(new_name)).to_string()
  @fs.write_string_to_file(new_path, "{}")
  @debug.assert_eq(find_session_file(dir, id), Some(new_path))
  @fs.remove_file(new_path) catch {
    _ => ()
  }
  ss_pop_profile(old)
}

///|
/// list_sessions orders by updated_at descending (most recently touched
/// first), not created_at (decision 8).
test "list_sessions sorts by updated_at descending" {
  let old = ss_push_profile()
  let old_id = generate_session_id()
  let new_id = generate_session_id()
  save_session({
    ..ss_make_session(old_id, "old"),
    updated_at: "2026-01-01T00:00:00+08:00",
  }) catch {
    _ => assert_true(false)
  }
  save_session({
    ..ss_make_session(new_id, "new"),
    updated_at: "2026-09-01T00:00:00+08:00",
  }) catch {
    _ => assert_true(false)
  }
  let sessions = list_sessions()
  @debug.assert_eq(sessions[0].session_id, new_id)
  @debug.assert_eq(sessions[1].session_id, old_id)
  // find_most_recent follows the same ordering.
  @debug.assert_eq(find_most_recent().unwrap().session_id, new_id)
  // Prefix matching resolves by session_id prefix (decision 8).
  @debug.assert_eq(find_sessions_by_prefix(new_id[:8].to_owned()).length(), 1)
  @debug.assert_eq(find_sessions_by_prefix("zzz-nonexistent").length(), 0)
  delete_session(old_id)
  delete_session(new_id)
  ss_pop_profile(old)
}

///|
/// fork_session carries the Time Machine state over and leaves forked_from
/// unset (decision 8; Ruby forked-from semantics).
test "fork_session keeps time_machine and leaves forked_from unset" {
  let old = ss_push_profile()
  let src_id = generate_session_id()
  let parents : Map[String, String] = Map([])
  parents["2"] = "1"
  let src = {
    ..ss_make_session(src_id, "origin"),
    time_machine: Some({
      task_parents: parents,
      task_meta: Map([]),
      current_task_id: 2,
      active_task_id: 2,
    }),
  }
  save_session(src) catch {
    _ => assert_true(false)
  }
  let forked = fork_session(src_id).unwrap()
  @debug.assert_eq(forked.forked_from, None)
  @debug.assert_eq(forked.time_machine.unwrap().current_task_id, 2)
  @debug.assert_eq(
    forked.time_machine.unwrap().task_parents.get("2"),
    Some("1"),
  )
  delete_session(src_id)
  delete_session(forked.session_id)
  ss_pop_profile(old)
}
