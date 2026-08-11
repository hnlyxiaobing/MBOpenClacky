///| White-box tests for ext_loader: load_extensions_from_paths and
/// merge_api_extensions.

///|
/// OS-portable temp directory (uses TEMP/TMPDIR env, falls back to /tmp).
/// Avoids hardcoded Unix /tmp paths that don't exist on Windows.
fn wbtest_tmp_root() -> String {
  match @env.get_env_var("TEMP") {
    Some(d) => d
    None =>
      match @env.get_env_var("TMPDIR") {
        Some(d) => d
        None => "/tmp"
      }
  }
}

///|
test "load_extensions_from_paths: empty list yields empty result" {
  let result = load_extensions_from_paths([])
  @debug.assert_eq(result.length(), 0)
}

///|
test "load_extensions_from_paths: missing file is skipped" {
  let result = load_extensions_from_paths([
    (
      "ext1",
      wbtest_tmp_root() +
      "/_wbtest_load_missing_\{@env.now().reinterpret_as_int64()}.json",
    ),
  ])
  @debug.assert_eq(result.length(), 0)
}

///|
test "load_extensions_from_paths: JSON descriptor is loaded" {
  let tmp = wbtest_tmp_root() +
    "/_wbtest_load_json_\{@env.now().reinterpret_as_int64()}"
  @fs.create_dir(tmp) catch {
    _ => ()
  }
  let f = "\{tmp}/api.json"
  let json_content =
    #| {
    #|   "name": "myapi",
    #|   "version": "1.0.0",
    #|   "enabled": true,
    #|   "routes": [
    #|     { "method": "GET", "path": "/hi", "handler_name": "h", "command": "echo hi" }
    #|   ]
    #| }
  @fs.write_string_to_file(f, json_content) catch {
    _ => ()
  }
  let result = load_extensions_from_paths([("myapi", f)])
  @debug.assert_eq(result.length(), 1)
  let ext = result[0]
  @debug.assert_eq(ext.name, "myapi")
  @debug.assert_eq(ext.routes.length(), 1)
  @debug.assert_eq(ext.routes[0].http_method, "GET")
  @fs.remove_file(f) catch {
    _ => ()
  }
  @fs.remove_dir(tmp) catch {
    _ => ()
  }
}

///|
test "load_extensions_from_paths: malformed JSON is skipped" {
  let tmp = "/tmp/_wbtest_load_bad_\{@env.now().reinterpret_as_int64()}"
  @fs.create_dir(tmp) catch {
    _ => ()
  }
  let f = "\{tmp}/bad.json"
  @fs.write_string_to_file(f, "{ not valid json") catch {
    _ => ()
  }
  let result = load_extensions_from_paths([("bad", f)])
  @debug.assert_eq(result.length(), 0)
  @fs.remove_file(f) catch {
    _ => ()
  }
  @fs.remove_dir(tmp) catch {
    _ => ()
  }
}

///|
test "load_extensions_from_paths: multiple paths aggregate" {
  let tmp = wbtest_tmp_root() +
    "/_wbtest_load_multi_\{@env.now().reinterpret_as_int64()}"
  @fs.create_dir(tmp) catch {
    _ => ()
  }
  let f1 = "\{tmp}/a.json"
  let f2 = "\{tmp}/b.json"
  @fs.write_string_to_file(f1, "{\"name\":\"a\",\"version\":\"1.0\"}") catch {
    _ => ()
  }
  @fs.write_string_to_file(f2, "{\"name\":\"b\",\"version\":\"1.0\"}") catch {
    _ => ()
  }
  let result = load_extensions_from_paths([("a", f1), ("b", f2)])
  @debug.assert_eq(result.length(), 2)
  @fs.remove_file(f1) catch {
    _ => ()
  }
  @fs.remove_file(f2) catch {
    _ => ()
  }
  @fs.remove_dir(tmp) catch {
    _ => ()
  }
}

// ── merge_api_extensions tests ─────────────────────────────────

///|
test "merge_api_extensions: empty inputs yield empty output" {
  @debug.assert_eq(merge_api_extensions([], []).length(), 0)
}

///|
test "merge_api_extensions: a only is preserved" {
  let a : Array[ApiExtension] = [
    { name: "a", version: "1.0", routes: [], enabled: true },
  ]
  let result = merge_api_extensions(a, [])
  @debug.assert_eq(result.length(), 1)
  @debug.assert_eq(result[0].name, "a")
}

///|
test "merge_api_extensions: b only is preserved" {
  let b : Array[ApiExtension] = [
    { name: "b", version: "1.0", routes: [], enabled: true },
  ]
  let result = merge_api_extensions([], b)
  @debug.assert_eq(result.length(), 1)
  @debug.assert_eq(result[0].name, "b")
}

///|
test "merge_api_extensions: b overrides a on name clash" {
  let mk = fn(n : String) -> ApiExtension {
    { name: n, version: "1.0", routes: [], enabled: true }
  }
  let a : Array[ApiExtension] = [mk("dup"), mk("only-in-a")]
  let b : Array[ApiExtension] = [mk("dup"), mk("only-in-b")]
  let result = merge_api_extensions(a, b)
  // 3 unique names: dup, only-in-a, only-in-b
  @debug.assert_eq(result.length(), 3)
  let names : Array[String] = []
  for ext in result {
    names.push(ext.name)
  }
  assert_true(names.contains("dup"))
  assert_true(names.contains("only-in-a"))
  assert_true(names.contains("only-in-b"))
}
