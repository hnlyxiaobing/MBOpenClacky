///| White-box contract tests for specs

///| `2026-07-24_web-ui-fix-15-skills-api-fields` and

///| `2026-07-24_web-ui-fix-16-creator-skills-contract`:

///| session skills listing wired to the real scan, user_invocable

///| filtering, and creator skills local_skills payload with a real

///| user skill on disk.

///|
fn sc_make_event(
  http_method : @crescent.HttpMethod,
  url : String,
  id : String,
) -> @crescent.Event {
  {
    req: @crescent.HttpRequest::HttpRequest(
      http_method,
      url,
      Map([]),
      raw_body=@utf8.encode(""),
    ),
    res: @crescent.HttpResponse::HttpResponse(status_code=OK),
    params: { "id": id },
  }
}

///|
fn sc_make_server_ref() -> Ref[WebServer] {
  Ref(WebServer::new(@config.AgentConfig::default(), None))
}

///|
fn sc_response_json(resp : @core.HttpResponse) -> Json {
  @json.parse(@utf8.decode(resp.raw_body)) catch {
    _ => Json::object(Map([]))
  }
}

// ── fix-15: GET /api/sessions/:id/skills ────────────────────────────

///|
test "session skills: returns real non-empty list in orig entry shape" {
  let server_ref = sc_make_server_ref()
  let resp = handle_session_skills(
    server_ref,
    sc_make_event(Get, "/api/sessions/sess-1/skills", "sess-1"),
  )
  @debug.assert_eq(resp.status_code.to_int(), 200)
  let j = sc_response_json(resp)
  guard! j is Object(obj)
  @debug.assert_eq(obj.get("session_id"), Some("sess-1".to_json()))
  guard! obj.get("skills") is Some(Array(skills))
  // Real scan must find the builtin skills (was an empty stub before).
  assert_true(skills.length() > 0)
  let mut saw_code_explorer = false
  for skill in skills {
    guard! skill is Object(entry)
    // Orig session-skills entry shape.
    for
      key in [
        "name", "name_zh", "description", "description_zh", "encrypted", "source_type",
        "always_show",
      ] {
      assert_true(entry.contains(key))
    }
    @debug.assert_eq(entry.get("encrypted"), Some(false.to_json()))
    if entry.get("name") == Some("code-explorer".to_json()) {
      saw_code_explorer = true
      @debug.assert_eq(entry.get("source_type"), Some("default".to_json()))
    }
  }
  assert_true(saw_code_explorer)
}

///|
test "session skills: user_invocable false skills are excluded" {
  let name = "wbtest-skill-notinvocable-" + @env.now().to_string()
  let dir = user_skills_dir() + "/" + name
  @utils.ensure_dir(dir)
  @fs.write_string_to_file(
    dir + "/SKILL.md",
    "---\nname: " +
    name +
    "\ndescription: hidden from slash autocomplete\nuser_invocable: false\n---\n\nbody\n",
  ) catch {
    _ => panic()
  }
  let server_ref = sc_make_server_ref()
  let resp = handle_session_skills(
    server_ref,
    sc_make_event(Get, "/api/sessions/sess-2/skills", "sess-2"),
  )
  // Cleanup before assertions so a failure does not leak state.
  match remove_dir_recursive(dir) {
    Ok(_) => ()
    Err(_) => ()
  }
  @debug.assert_eq(resp.status_code.to_int(), 200)
  let j = sc_response_json(resp)
  guard! j is Object(obj)
  guard! obj.get("skills") is Some(Array(skills))
  for skill in skills {
    guard! skill is Object(entry)
    assert_false(entry.get("name") == Some(name.to_json()))
  }
  // ...while the global /api/skills listing still shows the skill shape
  // independent of user_invocable (verified indirectly: the filter only
  // lives in the session path).
}

// ── fix-16: GET /api/creator/skills with a real user skill ──────────

///|
test "creator skills: local_skills contains real user skill with orig keys" {
  let name = "wbtest-skill-creator-" + @env.now().to_string()
  let dir = user_skills_dir() + "/" + name
  @utils.ensure_dir(dir)
  @fs.write_string_to_file(
    dir + "/SKILL.md",
    "---\nname: " + name + "\ndescription: creator local skill\n---\n\nbody\n",
  ) catch {
    _ => panic()
  }
  let req = HttpRequest::new(GET, "/api/creator/skills")
  let resp = handle_creator_skills(req)
  match remove_dir_recursive(dir) {
    Ok(_) => ()
    Err(_) => ()
  }
  @debug.assert_eq(resp.status, 200)
  let j : Json = @json.parse(resp.body) catch { _ => panic() }
  guard! j is Object(obj)
  @debug.assert_eq(obj.get("ok"), Some(true.to_json()))
  guard! obj.get("local_skills") is Some(Array(local_entries))
  let mut found = false
  for entry in local_entries {
    guard! entry is Object(e)
    if e.get("name") == Some(name.to_json()) {
      found = true
      @debug.assert_eq(
        e.get("description"),
        Some("creator local skill".to_json()),
      )
      @debug.assert_eq(e.get("source"), Some("user".to_json()))
      @debug.assert_eq(e.get("enabled"), Some(true.to_json()))
      // No upload_meta / mtime data source: orig empty-value rule.
      @debug.assert_eq(e.get("platform_version"), Some(Json::null()))
      @debug.assert_eq(e.get("uploaded_at"), Some(Json::null()))
      @debug.assert_eq(e.get("local_modified_at"), Some(Json::null()))
      @debug.assert_eq(e.get("shadowing_brand"), Some(false.to_json()))
    }
  }
  assert_true(found)
}

///|
test "creator skills: local_skills sorted by name" {
  let req = HttpRequest::new(GET, "/api/creator/skills")
  let resp = handle_creator_skills(req)
  @debug.assert_eq(resp.status, 200)
  let j : Json = @json.parse(resp.body) catch { _ => panic() }
  guard! j is Object(obj)
  guard! obj.get("local_skills") is Some(Array(local_entries))
  let names : Array[String] = []
  for entry in local_entries {
    guard! entry is Object(e)
    match e.get("name") {
      Some(String(n)) => names.push(n)
      _ => ()
    }
  }
  let sorted = names.copy()
  sorted.sort()
  @debug.assert_eq(names, sorted)
}
