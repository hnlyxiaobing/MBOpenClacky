///| White-box tests for the fix-20 P3 contract patch batch (I-032 ~ I-035).
/// Covers: 404 bodies carrying ok:false, store read endpoints carrying ok,
/// agents entries carrying avatar, and backup status carrying
/// config/dest_dir/is_wsl.

///|
/// Parse a response body into Json for key assertions.
fn p3_parse(body : String) -> Json {
  @json.parse(body) catch {
    _ => Json::empty_object()
  }
}

///|
/// Whether the top-level object has the key.
fn p3_has_key(j : Json, key : String) -> Bool {
  match j {
    Object(m) => m.contains(key)
    _ => false
  }
}

///|
/// Whether the top-level object has key with the expected boolean value.
fn p3_bool_is(j : Json, key : String, expected : Bool) -> Bool {
  match j {
    Object(m) =>
      match m.get(key) {
        Some(True) => expected
        Some(False) => !expected
        _ => false
      }
    _ => false
  }
}

// ── I-032: 404 bodies carry ok:false ────────────────────────────────

///|
test "i-032: mcp server tools 404 body carries ok:false" {
  let reg = @mcp.McpRegistry::new()
  let req = {
    ..HttpRequest::new(GET, "/api/mcp/nonexistent_404/tools"),
    params: [("name", "nonexistent_404")],
  }
  let resp = handle_mcp_list_server_tools(reg, req)
  @debug.assert_eq(resp.status, 404)
  let body = p3_parse(resp.body)
  assert_true(p3_bool_is(body, "ok", false))
  assert_true(p3_has_key(body, "error"))
}

///|
test "i-032: skill content 404 body carries ok:false" {
  let req = {
    ..HttpRequest::new(GET, "/api/skills/nonexistent_404/content"),
    params: [("name", "nonexistent_404")],
  }
  let resp = handle_skills_get_content(req)
  @debug.assert_eq(resp.status, 404)
  let body = p3_parse(resp.body)
  assert_true(p3_bool_is(body, "ok", false))
  assert_true(p3_has_key(body, "error"))
}

// ── I-033: store read endpoints carry ok:true ───────────────────────

///|
test "i-033: store extensions list carries ok:true" {
  let resp = handle_store_list(HttpRequest::new(GET, "/api/store/extensions"))
  @debug.assert_eq(resp.status, 200)
  let body = p3_parse(resp.body)
  assert_true(p3_bool_is(body, "ok", true))
  assert_true(p3_has_key(body, "extensions"))
}

///|
test "i-033: store installed list carries ok:true" {
  let resp = handle_store_installed(
    HttpRequest::new(GET, "/api/store/extensions/installed"),
  )
  @debug.assert_eq(resp.status, 200)
  let body = p3_parse(resp.body)
  assert_true(p3_bool_is(body, "ok", true))
  assert_true(p3_has_key(body, "extensions"))
}

// ── I-034: agents entries carry avatar ──────────────────────────────

///|
test "i-034: agent entries carry avatar key" {
  let agents = load_agents_from_assets()
  // assets/agents ships at least one agent directory in this repo.
  assert_true(agents.length() > 0)
  for agent in agents {
    assert_true(p3_has_key(agent, "avatar"))
    // No avatar.png ships in the repo assets, so orig semantics yield null.
    match agent {
      Object(m) =>
        match m.get("avatar") {
          Some(Null) => ()
          other =>
            abort("expected null avatar, got: " + @debug.to_string(other))
        }
      _ => abort("expected object agent entry")
    }
  }
}

// ── I-035: backup status carries config/dest_dir/is_wsl ─────────────

///|
test "i-035: backup status body carries config/dest_dir/is_wsl" {
  let resp = handle_backups_list(HttpRequest::new(GET, "/api/backup/status"))
  @debug.assert_eq(resp.status, 200)
  let body = p3_parse(resp.body)
  assert_true(p3_has_key(body, "backups"))
  assert_true(p3_has_key(body, "dest_dir"))
  assert_true(p3_has_key(body, "is_wsl"))
  // config follows orig's BackupManager::DEFAULT_CONFIG shape.
  match body {
    Object(m) =>
      match m.get("config") {
        Some(Object(cfg)) => {
          let expected = [
            "enabled", "cron", "dest_dir", "keep", "include_sessions", "last_run_at",
            "last_status", "last_error", "last_archive",
          ]
          for key in expected {
            assert_true(cfg.contains(key))
          }
        }
        _ => abort("expected object at key: config")
      }
    _ => abort("expected object body")
  }
}
