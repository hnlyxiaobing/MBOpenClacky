///| White-box tests for GET /api/dirs contract alignment covered by

///| spec `2026-07-24_web-ui-fix-12-dirs-endpoint-contract` (I-008):

///| six-key response `{root, path, parent, home, default, entries}`,

///| directories only, lowercase-name sort, hidden/IGNORED filtering,

///| `show_hidden`, ancestor fallback, `~` expansion, and the fix-05

///| path-traversal baseline.

///|
fn dc_make_event(
  http_method : @crescent.HttpMethod,
  url : String,
) -> @crescent.Event {
  {
    req: @crescent.HttpRequest::HttpRequest(
      http_method,
      url,
      Map([]),
      raw_body=@utf8.encode(""),
    ),
    res: @crescent.HttpResponse::HttpResponse(status_code=OK),
    params: Map([]),
  }
}

///|
fn dc_make_server_ref() -> Ref[WebServer] {
  Ref(WebServer::new(@config.AgentConfig::default(), None))
}

///|
fn dc_response_json(resp : @core.HttpResponse) -> Json {
  @json.parse(@utf8.decode(resp.raw_body)) catch {
    _ => Json::object(Map([]))
  }
}

///|
/// Hermetic home fixture (mirrors the USERPROFILE redirection pattern in
/// handlers_api_contract_wbtest.mbt). Tests run with cwd = project root.
let dc_home : String = "_build/dc_dirs_home"

///|
fn dc_remove_tree(path : String) -> Unit {
  if is_directory(path) {
    let entries = @fs.read_dir(path) catch { _ => [] }
    for name in entries {
      dc_remove_tree(
        @path.Path::join(@path.Path(path), @path.Path(name)).to_string(),
      )
    }
    @fs.remove_dir(path) catch {
      _ => ()
    }
  } else {
    @fs.remove_file(path) catch {
      _ => ()
    }
  }
}

///|
fn dc_setup_fixture() -> Unit {
  dc_remove_tree(dc_home)
  @utils.ensure_dir(dc_home + "/alpha")
  @utils.ensure_dir(dc_home + "/Beta")
  @utils.ensure_dir(dc_home + "/zeta")
  @utils.ensure_dir(dc_home + "/.hidden_dir")
  @utils.ensure_dir(dc_home + "/.git")
  @utils.ensure_dir(dc_home + "/node_modules")
  @fs.write_string_to_file(dc_home + "/file.txt", "x") catch {
    _ => ()
  }
}

///|
fn dc_set_home() -> String? {
  let old = @sys.get_env_var("USERPROFILE")
  @sys.set_env_var("USERPROFILE", dc_home)
  old
}

///|
fn dc_restore_home(old : String?) -> Unit {
  match old {
    Some(v) => @sys.set_env_var("USERPROFILE", v)
    None => @sys.set_env_var("USERPROFILE", "")
  }
}

///|
/// Extract the `name` fields of the entries array, in order.
fn dc_entry_names(j : Json) -> Array[String] {
  let names : Array[String] = []
  match j {
    Object(obj) =>
      match obj.get("entries") {
        Some(Array(items)) =>
          for it in items {
            match it {
              Object(entry) =>
                match entry.get("name") {
                  Some(String(n)) => names.push(n)
                  _ => ()
                }
              _ => ()
            }
          }
        _ => ()
      }
    _ => ()
  }
  names
}

///|
test "dirs list returns six-key contract with home default" {
  dc_setup_fixture()
  let old = dc_set_home()
  let server_ref = dc_make_server_ref()
  let resp = handle_dirs_list(server_ref, dc_make_event(Get, "/api/dirs"))
  dc_restore_home(old)
  @debug.assert_eq(resp.status_code.to_int(), 200)
  let j = dc_response_json(resp)
  guard j is Object(obj)
  for key in ["root", "path", "parent", "home", "default", "entries"] {
    assert_true(obj.contains(key))
  }
  let home_norm = dirs_fwd_slashes(dc_home)
  @debug.assert_eq(obj.get("root"), Some(home_norm.to_json()))
  @debug.assert_eq(obj.get("path"), Some(home_norm.to_json()))
  @debug.assert_eq(obj.get("home"), Some(home_norm.to_json()))
  // No configured default_working_dir -> <home>/clacky_workspace fallback.
  @debug.assert_eq(
    obj.get("default"),
    Some((home_norm + "/clacky_workspace").to_json()),
  )
  // Directories only, sorted by lowercase name; file/hidden/IGNORED excluded.
  @debug.assert_eq(dc_entry_names(j), ["alpha", "Beta", "zeta"])
  dc_remove_tree(dc_home)
}

///|
test "dirs list entries carry absolute-joined path and type dir" {
  dc_setup_fixture()
  let old = dc_set_home()
  let server_ref = dc_make_server_ref()
  let resp = handle_dirs_list(
    server_ref,
    dc_make_event(Get, "/api/dirs?path=" + dc_home),
  )
  dc_restore_home(old)
  @debug.assert_eq(resp.status_code.to_int(), 200)
  let j = dc_response_json(resp)
  guard j is Object(obj)
  let home_norm = dirs_fwd_slashes(dc_home)
  guard obj.get("entries") is Some(Array(items))
  assert_true(items.length() > 0)
  for it in items {
    guard it is Object(entry)
    @debug.assert_eq(entry.get("type"), Some("dir".to_json()))
    match entry.get("path") {
      Some(String(p)) => {
        assert_true(p.has_prefix(home_norm + "/"))
        assert_true(!p.contains("\\"))
      }
      _ => assert_true(false)
    }
  }
  // parent of the fixture home is its dirname.
  @debug.assert_eq(
    obj.get("parent"),
    Some(dirs_fwd_slashes("_build").to_json()),
  )
  dc_remove_tree(dc_home)
}

///|
test "dirs list show_hidden=true includes hidden dirs but keeps IGNORED filtered" {
  dc_setup_fixture()
  let old = dc_set_home()
  let server_ref = dc_make_server_ref()
  let resp = handle_dirs_list(
    server_ref,
    dc_make_event(Get, "/api/dirs?path=" + dc_home + "&show_hidden=true"),
  )
  dc_restore_home(old)
  @debug.assert_eq(resp.status_code.to_int(), 200)
  let j = dc_response_json(resp)
  // Ruby sorts by name.downcase; "." (0x2E) sorts before letters.
  @debug.assert_eq(dc_entry_names(j), [".hidden_dir", "alpha", "Beta", "zeta"])
  dc_remove_tree(dc_home)
}

///|
test "dirs list falls back to nearest existing ancestor" {
  dc_setup_fixture()
  let old = dc_set_home()
  let server_ref = dc_make_server_ref()
  let resp = handle_dirs_list(
    server_ref,
    dc_make_event(Get, "/api/dirs?path=" + dc_home + "/no_such/deeper"),
  )
  dc_restore_home(old)
  @debug.assert_eq(resp.status_code.to_int(), 200)
  let j = dc_response_json(resp)
  guard j is Object(obj)
  let home_norm = dirs_fwd_slashes(dc_home)
  @debug.assert_eq(obj.get("root"), Some(home_norm.to_json()))
  @debug.assert_eq(obj.get("path"), Some(home_norm.to_json()))
  @debug.assert_eq(dc_entry_names(j), ["alpha", "Beta", "zeta"])
  dc_remove_tree(dc_home)
}

///|
test "dirs list expands tilde to home" {
  dc_setup_fixture()
  let old = dc_set_home()
  let server_ref = dc_make_server_ref()
  let resp = handle_dirs_list(
    server_ref,
    dc_make_event(Get, "/api/dirs?path=~/alpha"),
  )
  dc_restore_home(old)
  @debug.assert_eq(resp.status_code.to_int(), 200)
  let j = dc_response_json(resp)
  guard j is Object(obj)
  let alpha_norm = dirs_fwd_slashes(dc_home + "/alpha")
  @debug.assert_eq(obj.get("root"), Some(alpha_norm.to_json()))
  @debug.assert_eq(obj.get("path"), Some(alpha_norm.to_json()))
  dc_remove_tree(dc_home)
}

///|
test "dirs list rejects path traversal" {
  let server_ref = dc_make_server_ref()
  let resp = handle_dirs_list(
    server_ref,
    dc_make_event(Get, "/api/dirs?path=../../etc"),
  )
  @debug.assert_eq(resp.status_code.to_int(), 400)
  let j = dc_response_json(resp)
  guard j is Object(obj)
  assert_true(obj.contains("error"))
}

// ── dirs_fwd_slashes normalization (web-ui2-08) ────────────────────

///|
test "dirs_fwd_slashes: collapse double slash after drive letter" {
  @debug.assert_eq(dirs_fwd_slashes("C://$Recycle.Bin"), "C:/$Recycle.Bin")
}

///|
test "dirs_fwd_slashes: replace backslash with forward slash" {
  @debug.assert_eq(dirs_fwd_slashes("C:/Users\\hnlyh"), "C:/Users/hnlyh")
}

///|
test "dirs_fwd_slashes: collapse mid-path double slash" {
  @debug.assert_eq(dirs_fwd_slashes("/tmp//x"), "/tmp/x")
}

///|
test "dirs_fwd_slashes: preserve UNC leading double slash" {
  @debug.assert_eq(dirs_fwd_slashes("//host//share"), "//host/share")
}
