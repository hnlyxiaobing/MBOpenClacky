///| White-box contract tests for fix-13 (trash API contract alignment):
/// GET /api/trash and GET /api/trash/sessions follow the orig key shapes
/// ({ok, files, projects, total_count, total_size} /
///  {ok, sessions, count, total_size}), and session deletes are recorded
/// into the trash bin via trash_add_session.

///|
/// Reset the global trash state to a known fixture, bypassing disk load.
fn tw_reset_trash(items : Array[TrashItem]) -> Unit {
  trash_state.val.items = items
  trash_state.val.loaded = true
}

///|
fn tw_body_json(resp : HttpResponse) -> Json {
  @json.parse(resp.body) catch {
    _ => Json::object(Map([]))
  }
}

///|
fn tw_session_item(id : String, name : String) -> TrashItem {
  {
    id,
    item_type: "session",
    name,
    deleted_at: "1700000000",
    expires_at: "1700604800",
  }
}

///|
fn tw_file_item(id : String, name : String) -> TrashItem {
  {
    id,
    item_type: "file",
    name,
    deleted_at: "1700000000",
    expires_at: "1700604800",
  }
}

///|
test "trash list: orig contract shape with empty trash" {
  tw_reset_trash([])
  let resp = handle_trash_list(HttpRequest::new(GET, "/api/trash"))
  @debug.assert_eq(resp.status, 200)
  guard! tw_body_json(resp) is Object(obj)
  @debug.assert_eq(obj.get("ok"), Some(true.to_json()))
  @debug.assert_eq(obj.get("files"), Some(Json::array([])))
  @debug.assert_eq(obj.get("projects"), Some(Json::array([])))
  @debug.assert_eq(obj.get("total_count"), Some((0).to_json()))
  @debug.assert_eq(obj.get("total_size"), Some((0).to_json()))
}

///|
test "trash list: non-session items surface under files with orig keys" {
  tw_reset_trash([
    tw_file_item("t1", "/tmp/a.txt"),
    tw_session_item("s1", "A Session"),
  ])
  let resp = handle_trash_list(HttpRequest::new(GET, "/api/trash"))
  @debug.assert_eq(resp.status, 200)
  guard! tw_body_json(resp) is Object(obj)
  // sessions are excluded from the files dimension
  guard! obj.get("files") is Some(Array(files))
  @debug.assert_eq(files.length(), 1)
  @debug.assert_eq(obj.get("total_count"), Some((1).to_json()))
  guard! files[0] is Object(entry)
  // orig file-entry key set (api-diff /api/trash elem keys)
  @debug.assert_eq(entry.get("original_path"), Some("/tmp/a.txt".to_json()))
  @debug.assert_eq(entry.get("trash_file"), Some("t1".to_json()))
  @debug.assert_eq(entry.get("file_type"), Some("file".to_json()))
  @debug.assert_eq(entry.get("deleted_at"), Some("1700000000".to_json()))
  assert_true(entry.contains("deleted_by"))
  assert_true(entry.contains("file_mode"))
  assert_true(entry.contains("file_size"))
  assert_true(entry.contains("project_name"))
  assert_true(entry.contains("project_root"))
}

///|
test "trash sessions list: orig contract shape, files excluded" {
  tw_reset_trash([
    tw_session_item("s1", "First Session"),
    tw_session_item("s2", "Second Session"),
    tw_file_item("t1", "/tmp/a.txt"),
  ])
  let resp = handle_trash_sessions_list(
    HttpRequest::new(GET, "/api/trash/sessions"),
  )
  @debug.assert_eq(resp.status, 200)
  guard! tw_body_json(resp) is Object(obj)
  @debug.assert_eq(obj.get("ok"), Some(true.to_json()))
  @debug.assert_eq(obj.get("count"), Some((2).to_json()))
  @debug.assert_eq(obj.get("total_size"), Some((0).to_json()))
  guard! obj.get("sessions") is Some(Array(sessions))
  @debug.assert_eq(sessions.length(), 2)
  guard! sessions[0] is Object(entry)
  // orig session-entry key set (api-diff /api/trash/sessions elem keys)
  @debug.assert_eq(entry.get("session_id"), Some("s1".to_json()))
  @debug.assert_eq(entry.get("name"), Some("First Session".to_json()))
  @debug.assert_eq(entry.get("deleted_at"), Some("1700000000".to_json()))
  @debug.assert_eq(entry.get("model"), Some(Json::null()))
  assert_true(entry.contains("created_at"))
  assert_true(entry.contains("updated_at"))
  assert_true(entry.contains("total_tasks"))
  assert_true(entry.contains("file_size"))
  assert_true(entry.contains("working_dir"))
  assert_true(entry.contains("source"))
}

///|
test "trash_add_session: deleted session appears in sessions list" {
  // trash_add_session persists to ~/.mbopenclacky/trash.json — back up and
  // restore any pre-existing file so the test leaves no residue.
  let path = trash_file_path()
  let existed = @fs.path_exists(path)
  let backup : String = if existed {
    @fs.read_file_to_string(path) catch {
      _ => ""
    }
  } else {
    ""
  }
  tw_reset_trash([])
  trash_add_session("sess-del-1", "Deleted Session")
  let resp = handle_trash_sessions_list(
    HttpRequest::new(GET, "/api/trash/sessions"),
  )
  @debug.assert_eq(resp.status, 200)
  guard! tw_body_json(resp) is Object(obj)
  guard! obj.get("sessions") is Some(Array(sessions))
  @debug.assert_eq(sessions.length(), 1)
  guard! sessions[0] is Object(entry)
  @debug.assert_eq(entry.get("session_id"), Some("sess-del-1".to_json()))
  @debug.assert_eq(entry.get("name"), Some("Deleted Session".to_json()))
  assert_true(entry.get("deleted_at") is Some(String(_)))
  // restore pre-existing trash.json (or remove the one we created)
  if existed {
    @fs.write_string_to_file(path, backup) catch {
      _ => ()
    }
  } else {
    @fs.remove_file(path) catch {
      _ => ()
    }
  }
  tw_reset_trash([])
}

///|
test "trash delete returns 200 ok json (web-ui2-03 BUG-021)" {
  let path = trash_file_path()
  let existed = @fs.path_exists(path)
  let backup : String = if existed {
    @fs.read_file_to_string(path) catch {
      _ => ""
    }
  } else {
    ""
  }
  tw_reset_trash([tw_session_item("s1", "A Session")])
  let req : HttpRequest = {
    http_method: DELETE,
    path: "/api/trash/s1",
    params: [("id", "s1")],
    body: "",
    headers: [],
  }
  let resp = handle_trash_delete(req)
  @debug.assert_eq(resp.status, 200)
  guard! tw_body_json(resp) is Object(obj)
  @debug.assert_eq(obj.get("ok"), Some(true.to_json()))
  // item was removed from trash state
  @debug.assert_eq(trash_state.val.items.length(), 0)
  if existed {
    @fs.write_string_to_file(path, backup) catch {
      _ => ()
    }
  } else {
    @fs.remove_file(path) catch {
      _ => ()
    }
  }
  tw_reset_trash([])
}

///|
test "trash clear sessions: deletes only session items (web-ui2-03 BUG-022)" {
  let path = trash_file_path()
  let existed = @fs.path_exists(path)
  let backup : String = if existed {
    @fs.read_file_to_string(path) catch {
      _ => ""
    }
  } else {
    ""
  }
  tw_reset_trash([
    tw_session_item("s1", "First"),
    tw_session_item("s2", "Second"),
    tw_file_item("f1", "/tmp/a.txt"),
  ])
  let resp = handle_trash_clear_sessions(
    HttpRequest::new(DELETE, "/api/trash/sessions"),
  )
  @debug.assert_eq(resp.status, 200)
  guard! tw_body_json(resp) is Object(obj)
  @debug.assert_eq(obj.get("ok"), Some(true.to_json()))
  @debug.assert_eq(obj.get("deleted_count"), Some((2).to_json()))
  @debug.assert_eq(obj.get("days_old"), Some((7).to_json()))
  // non-session items are retained
  @debug.assert_eq(trash_state.val.items.length(), 1)
  @debug.assert_eq(trash_state.val.items[0].item_type, "file")
  if existed {
    @fs.write_string_to_file(path, backup) catch {
      _ => ()
    }
  } else {
    @fs.remove_file(path) catch {
      _ => ()
    }
  }
  tw_reset_trash([])
}
