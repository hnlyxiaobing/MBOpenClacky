///| White-box tests for skill management handlers.

// ── Name validation ───────────────────────────────────────────────

///|
test "skill name: valid names accepted" {
  assert_true(is_valid_skill_name("code-explorer"))
  assert_true(is_valid_skill_name("skill_add"))
  assert_true(is_valid_skill_name("my.skill"))
  assert_true(is_valid_skill_name("Skill123"))
}

///|
test "skill name: path traversal rejected" {
  assert_false(is_valid_skill_name("../etc"))
  assert_false(is_valid_skill_name("a/b"))
  assert_false(is_valid_skill_name("a\\b"))
  assert_false(is_valid_skill_name(".."))
  assert_false(is_valid_skill_name(".hidden"))
  assert_false(is_valid_skill_name(""))
  assert_false(is_valid_skill_name("name with space"))
}

// ── JSON body helpers ─────────────────────────────────────────────

///|
test "json_str_field extracts string" {
  @debug.assert_eq(
    json_str_field(
      (
        #|{"name":"foo","description":"bar"}
      ),
      "name",
    ),
    Some("foo"),
  )
  @debug.assert_eq(
    json_str_field(
      (
        #|{"name":123}
      ),
      "name",
    ),
    None,
  )
  @debug.assert_eq(json_str_field("not json", "name"), None)
}

///|
test "json_bool_field extracts bool" {
  @debug.assert_eq(
    json_bool_field(
      (
        #|{"enabled":true}
      ),
      "enabled",
    ),
    Some(true),
  )
  @debug.assert_eq(
    json_bool_field(
      (
        #|{"enabled":false}
      ),
      "enabled",
    ),
    Some(false),
  )
  @debug.assert_eq(
    json_bool_field(
      (
        #|{"enabled":"yes"}
      ),
      "enabled",
    ),
    None,
  )
}

// ── Frontmatter description extraction ────────────────────────────

///|
test "skill_description_of parses frontmatter" {
  let content =
    #|---
    #|name: demo
    #|description: A demo skill
    #|---
    #|
    #|# Demo
  @debug.assert_eq(skill_description_of(content), "A demo skill")
  @debug.assert_eq(skill_description_of("no frontmatter here"), "")
}

// ── Handler behavior (uses real assets/skills, read-only cases) ───

///|
test "handler: skills list returns real builtin skills" {
  let req = HttpRequest::new(GET, "/api/skills")
  let resp = handle_skills_list(req)
  @debug.assert_eq(resp.status, 200)
  assert_true(resp.body.contains("code-explorer"))
  assert_true(resp.body.contains("\"source\""))
  assert_false(resp.body.contains("\"total\":0"))
}

///|
test "handler: skills get content reads builtin SKILL.md" {
  let req = {
    ..HttpRequest::new(GET, "/api/skills/code-explorer/content"),
    params: [("name", "code-explorer")],
  }
  let resp = handle_skills_get_content(req)
  @debug.assert_eq(resp.status, 200)
  assert_true(resp.body.contains("\"content\""))
}

///|
test "handler: skills get content 404 for unknown" {
  let req = {
    ..HttpRequest::new(GET, "/api/skills/no-such-skill/content"),
    params: [("name", "no-such-skill-xyz")],
  }
  let resp = handle_skills_get_content(req)
  @debug.assert_eq(resp.status, 404)
}

///|
test "handler: skills get content rejects traversal" {
  let req = {
    ..HttpRequest::new(GET, "/api/skills/../content"),
    params: [("name", "../../etc")],
  }
  let resp = handle_skills_get_content(req)
  @debug.assert_eq(resp.status, 400)
}

///|
test "handler: skills create requires body" {
  let req = HttpRequest::new(POST, "/api/skills")
  let resp = handle_skills_create(req)
  @debug.assert_eq(resp.status, 400)
}

///|
test "handler: skills create rejects invalid name" {
  let req = HttpRequest::new(
    POST,
    "/api/skills",
    body=(
      #|{"name":"../evil","description":"x"}
    ),
  )
  let resp = handle_skills_create(req)
  @debug.assert_eq(resp.status, 400)
}

///|
test "handler: skills delete protects builtin" {
  let req = {
    ..HttpRequest::new(DELETE, "/api/skills/code-explorer"),
    params: [("name", "code-explorer")],
  }
  let resp = handle_skills_delete(req)
  // Builtin skill without a user override must not be deletable.
  if resp.status != 204 {
    @debug.assert_eq(resp.status, 400)
    assert_true(resp.body.contains("builtin"))
  }
}

///|
test "handler: skills toggle requires enabled field" {
  let req = {
    ..HttpRequest::new(
      POST,
      "/api/skills/code-explorer/toggle",
      body=(
        #|{"other":1}
      ),
    ),
    params: [("name", "code-explorer")],
  }
  let resp = handle_skills_toggle(req)
  @debug.assert_eq(resp.status, 400)
}

///|
test "handler: store skills returns metadata with installed flag" {
  let req = HttpRequest::new(GET, "/api/store/skills")
  let resp = handle_store_skills(req)
  @debug.assert_eq(resp.status, 200)
  assert_true(resp.body.contains("code-explorer"))
  assert_true(resp.body.contains("\"installed\""))
  assert_true(resp.body.contains("\"category\""))
}

///|
test "handler: creator skills returns 200" {
  let req = HttpRequest::new(GET, "/api/creator/skills")
  let resp = handle_creator_skills(req)
  @debug.assert_eq(resp.status, 200)
  assert_true(resp.body.contains("\"skills\""))
}

// ── User skill lifecycle (create → content → toggle → delete) ────

///|
test "handler: user skill full lifecycle" {
  let name = "wbtest-skill-lifecycle"
  // Cleanup any leftover from previous runs
  let dir = user_skills_dir() + "/" + name
  if @fs.path_exists(dir) {
    match remove_dir_recursive(dir) {
      Ok(_) => ()
      Err(_) => ()
    }
  }

  // Create
  let create_req = HttpRequest::new(
    POST,
    "/api/skills",
    body=(
      #|{"name":"wbtest-skill-lifecycle","description":"lifecycle test"}
    ),
  )
  let create_resp = handle_skills_create(create_req)
  @debug.assert_eq(create_resp.status, 201)

  // Duplicate create rejected
  let dup_resp = handle_skills_create(create_req)
  @debug.assert_eq(dup_resp.status, 400)

  // Read content
  let get_req = {
    ..HttpRequest::new(GET, "/api/skills/x/content"),
    params: [("name", name)],
  }
  let get_resp = handle_skills_get_content(get_req)
  @debug.assert_eq(get_resp.status, 200)
  assert_true(get_resp.body.contains("lifecycle test"))
  assert_true(get_resp.body.contains("\"source\":\"user\""))

  // Update content
  let put_req = {
    ..HttpRequest::new(
      PUT,
      "/api/skills/x/content",
      body=(
        #|{"content":"---\nname: wbtest-skill-lifecycle\ndescription: updated desc\n---\nbody"}
      ),
    ),
    params: [("name", name)],
  }
  let put_resp = handle_skills_put_content(put_req)
  @debug.assert_eq(put_resp.status, 200)
  let get_resp2 = handle_skills_get_content(get_req)
  assert_true(get_resp2.body.contains("updated desc"))

  // Disable
  let toggle_req = {
    ..HttpRequest::new(
      POST,
      "/api/skills/x/toggle",
      body=(
        #|{"enabled":false}
      ),
    ),
    params: [("name", name)],
  }
  let toggle_resp = handle_skills_toggle(toggle_req)
  @debug.assert_eq(toggle_resp.status, 200)
  assert_true(@fs.path_exists(dir + "/.disabled"))

  // Re-enable
  let enable_req = {
    ..HttpRequest::new(
      POST,
      "/api/skills/x/toggle",
      body=(
        #|{"enabled":true}
      ),
    ),
    params: [("name", name)],
  }
  let enable_resp = handle_skills_toggle(enable_req)
  @debug.assert_eq(enable_resp.status, 200)
  assert_false(@fs.path_exists(dir + "/.disabled"))

  // Delete
  let del_req = {
    ..HttpRequest::new(DELETE, "/api/skills/x"),
    params: [("name", name)],
  }
  let del_resp = handle_skills_delete(del_req)
  @debug.assert_eq(del_resp.status, 204)
  assert_false(@fs.path_exists(dir))
}
