///| White-box tests for DELETE /api/store/extension purge_data semantics.
/// Home is redirected to "_build" so tests never touch the real ~/.clacky.

///|
fn st_make_request(body : String) -> HttpRequest {
  {
    http_method: DELETE,
    path: "/api/store/extension",
    params: [],
    body,
    headers: [],
  }
}

///|
fn st_push_profile() -> String? {
  let old = @env.get_env_var("USERPROFILE")
  @env.set_env_var("USERPROFILE", "_build")
  old
}

///|
fn st_pop_profile(old : String?) -> Unit {
  match old {
    Some(v) => @env.set_env_var("USERPROFILE", v)
    None => @env.set_env_var("USERPROFILE", "")
  }
}

///|
fn st_mkdirs(path : String) -> Unit {
  // Create each path segment in turn (create_dir is not recursive).
  let segs = path.split("/").collect()
  let mut cur = ""
  for seg in segs {
    cur = if cur == "" { seg.to_owned() } else { cur + "/" + seg.to_owned() }
    let _ = @fs.create_dir(cur) catch { _ => () }
  }
}

///|
test "store uninstall keeps ext-data by default and purges on request" {
  let old = st_push_profile()
  let ext_dir = "_build/.clacky/extensions/wbtest-purge-ext"
  let data_dir = "_build/.clacky/ext-data/wbtest-purge-ext"
  st_mkdirs(ext_dir)
  st_mkdirs(data_dir)
  // Default: purge_data absent → package removed, ext-data kept.
  let resp1 = handle_store_uninstall(
    st_make_request("{\"id\":\"wbtest-purge-ext\"}"),
  )
  @debug.assert_eq(resp1.status, 200)
  @debug.assert_eq(@fs.path_exists(ext_dir), false)
  @debug.assert_eq(@fs.path_exists(data_dir), true)
  // Recreate the package dir, then purge_data=true → both removed.
  st_mkdirs(ext_dir)
  let resp2 = handle_store_uninstall(
    st_make_request("{\"id\":\"wbtest-purge-ext\",\"purge_data\":true}"),
  )
  @debug.assert_eq(resp2.status, 200)
  @debug.assert_eq(@fs.path_exists(ext_dir), false)
  @debug.assert_eq(@fs.path_exists(data_dir), false)
  st_pop_profile(old)
}

///|
test "store uninstall rejects unknown id even with purge_data" {
  let old = st_push_profile()
  let resp = handle_store_uninstall(
    st_make_request(
      "{\"id\":\"wbtest-definitely-missing\",\"purge_data\":true}",
    ),
  )
  @debug.assert_eq(resp.status, 400)
  st_pop_profile(old)
}
