///|
/// Temporary directory for filesystem probes, honouring POSIX and Windows
/// conventions alike.
fn probe_temp_dir() -> String {
  for key in ["TMPDIR", "TEMP", "TMP"] {
    match @env.get_env_var(key) {
      Some(dir) => if !dir.trim().is_empty() { return dir.trim().to_owned() }
      None => ()
    }
  }
  "/tmp"
}

///|
fn probe_dir_name(tag : String) -> String {
  @path.Path::join(
    @path.Path(probe_temp_dir()),
    @path.Path("mbopenclacky-" + tag + "-" + @env.now().to_string()),
  ).to_string()
}

///|
fn probe_make_dir(dir : String) -> Bool {
  @fs.create_dir(dir) catch {
    _ => ()
  }
  @fs.path_exists(dir)
}

///|
test "assets_root honours MBOPENCLACKY_ASSETS_DIR" {
  let override_dir = @path.Path("/probe/assets-override").to_string()
  reset_assets_root_for_test()
  @env.set_env_var(ASSETS_DIR_ENV, override_dir)
  let root = assets_root()
  let joined = assets_path("skills/demo.md")
  @env.unset_env_var(ASSETS_DIR_ENV)
  reset_assets_root_for_test()
  @debug.assert_eq(root, override_dir)
  @debug.assert_eq(
    joined,
    @path.Path::join(@path.Path(override_dir), @path.Path("skills/demo.md")).to_string(),
  )
}

///|
test "find_project_root walks up to the directory carrying assets" {
  let base = probe_dir_name("assets-probe")
  let under_assets = @path.Path::join(@path.Path(base), @path.Path("assets")).to_string()
  let prompts = @path.Path::join(
    @path.Path(under_assets),
    @path.Path("prompts"),
  ).to_string()
  let marker = @path.Path::join(@path.Path(base), @path.Path(ASSETS_MARKER)).to_string()
  let nested = @path.Path::join(@path.Path(base), @path.Path("nested")).to_string()
  let deep = @path.Path::join(@path.Path(nested), @path.Path("deeper")).to_string()
  assert_true(probe_make_dir(base))
  assert_true(probe_make_dir(under_assets))
  assert_true(probe_make_dir(prompts))
  @fs.write_string_to_file(marker, "probe") catch {
    _ => ()
  }
  assert_true(@fs.path_exists(marker))
  assert_true(probe_make_dir(nested))
  assert_true(probe_make_dir(deep))
  let found = find_project_root(deep)
  @fs.remove_file(marker) catch {
    _ => ()
  }
  @fs.remove_dir(prompts) catch {
    _ => ()
  }
  @fs.remove_dir(under_assets) catch {
    _ => ()
  }
  @fs.remove_dir(deep) catch {
    _ => ()
  }
  @fs.remove_dir(nested) catch {
    _ => ()
  }
  @fs.remove_dir(base) catch {
    _ => ()
  }
  @debug.assert_eq(found, Some(base))
}

///|
test "find_project_root returns none without the assets marker" {
  let base = probe_dir_name("assets-empty")
  assert_true(probe_make_dir(base))
  let found = find_project_root(base)
  @fs.remove_dir(base) catch {
    _ => ()
  }
  @debug.assert_eq(found, None)
}

///|
test "assets_root caches the resolved value" {
  reset_assets_root_for_test()
  let first = assets_root()
  let second = assets_root()
  reset_assets_root_for_test()
  let third = assets_root()
  @debug.assert_eq(first, second)
  @debug.assert_eq(second, third)
}
