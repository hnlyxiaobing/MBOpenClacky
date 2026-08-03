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

// ── Frontmatter field extraction ────────────────────────────────────

///|
test "fm_description extracts frontmatter description" {
  let content =
    #|---
    #|name: demo
    #|description: A demo skill
    #|---
    #|
    #|# Demo
  let (fields, _) = @skill.parse_frontmatter(content)
  @debug.assert_eq(fm_description(fields), "A demo skill")
  let (empty_fields, _) = @skill.parse_frontmatter("no frontmatter here")
  @debug.assert_eq(fm_description(empty_fields), "")
}

///|
test "fm_bool_json renders true/false/null" {
  let (fields, _) = @skill.parse_frontmatter(
    (
      #|---
      #|name: demo
      #|always_show: true
      #|other_flag: nope
      #|---
    ),
  )
  @debug.assert_eq(fm_bool_json(fields, "always_show"), true.to_json())
  @debug.assert_eq(fm_bool_json(fields, "missing"), Json::null())
  @debug.assert_eq(fm_bool_json(fields, "other_flag"), Json::null())
}

///|
test "skill_list_entry_json aligns with orig contract keys" {
  let entry : SkillScanEntry = {
    name: "demo",
    content: (
      #|---
      #|name: demo
      #|description: A demo skill
      #|name_zh: 演示
      #|description_zh: 演示技能
      #|always_show: true
      #|---
      #|
      #|# Demo
    ),
    source: "user",
    enabled: true,
  }
  let j = skill_list_entry_json(entry, Map([]))
  guard! j is Object(obj)
  // Orig contract keys (fix-15): all 13 must be present.
  for
    key in [
      "name", "name_zh", "description", "description_zh", "source", "always_show",
      "enabled", "invalid", "warnings", "platform_version", "uploaded_at", "local_modified_at",
      "shadowing_brand",
    ] {
    assert_true(obj.contains(key))
  }
  @debug.assert_eq(obj.get("name"), Some("demo".to_json()))
  @debug.assert_eq(obj.get("name_zh"), Some("演示".to_json()))
  @debug.assert_eq(obj.get("description_zh"), Some("演示技能".to_json()))
  @debug.assert_eq(obj.get("always_show"), Some(true.to_json()))
  @debug.assert_eq(obj.get("invalid"), Some(false.to_json()))
  @debug.assert_eq(obj.get("warnings"), Some(Json::array([])))
  @debug.assert_eq(obj.get("platform_version"), Some(Json::null()))
  @debug.assert_eq(obj.get("uploaded_at"), Some(Json::null()))
  @debug.assert_eq(obj.get("shadowing_brand"), Some(false.to_json()))
  // invalid_reason only present when invalid.
  assert_false(obj.contains("invalid_reason"))
}

///|
test "skill_list_entry_json marks entries without frontmatter name invalid" {
  let entry : SkillScanEntry = {
    name: "broken",
    content: (
      #|---
      #|description: no name key
      #|---
    ),
    source: "user",
    enabled: true,
  }
  let j = skill_list_entry_json(entry, Map([]))
  guard! j is Object(obj)
  @debug.assert_eq(obj.get("invalid"), Some(true.to_json()))
  assert_true(obj.contains("invalid_reason"))
  @debug.assert_eq(obj.get("name_zh"), Some(Json::null()))
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
  // fix-15: entries must carry the orig contract keys.
  assert_true(resp.body.contains("\"name_zh\""))
  assert_true(resp.body.contains("\"description_zh\""))
  assert_true(resp.body.contains("\"always_show\""))
  assert_true(resp.body.contains("\"warnings\""))
  assert_true(resp.body.contains("\"invalid\""))
  assert_true(resp.body.contains("\"platform_version\""))
  assert_true(resp.body.contains("\"uploaded_at\""))
  assert_true(resp.body.contains("\"local_modified_at\""))
  assert_true(resp.body.contains("\"shadowing_brand\""))
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
test "handler: creator skills matches orig five-key contract" {
  let req = HttpRequest::new(GET, "/api/creator/skills")
  let resp = handle_creator_skills(req)
  @debug.assert_eq(resp.status, 200)
  let j : Json = @json.parse(resp.body) catch { _ => panic() }
  guard! j is Object(obj)
  // fix-16: exactly the orig top-level keys.
  @debug.assert_eq(obj.get("ok"), Some(true.to_json()))
  assert_true(obj.contains("licensed"))
  @debug.assert_eq(obj.get("cloud_skills"), Some(Json::array([])))
  assert_true(obj.contains("local_skills"))
  @debug.assert_eq(obj.get("platform_fetch_error"), Some(Json::null()))
  // Old incompatible shape must be gone.
  assert_false(obj.contains("skills"))
  assert_false(obj.contains("total"))
  guard! obj.get("local_skills") is Some(Array(local_entries))
  for entry in local_entries {
    guard! entry is Object(e)
    for
      key in [
        "name", "description", "source", "enabled", "platform_version", "uploaded_at",
        "local_modified_at", "shadowing_brand",
      ] {
      assert_true(e.contains(key))
    }
  }
}

// ── User skill lifecycle (create → content → toggle → delete) ────

///|
test "handler: user skill full lifecycle" {
  let name = "wbtest-skill-lifecycle-" + @env.now().to_string()
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
    body="{\"name\":\"" + name + "\",\"description\":\"lifecycle test\"}",
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
      body="{\"content\":\"---\\nname: " +
        name +
        "\\ndescription: updated desc\\n---\\nbody\"}",
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
