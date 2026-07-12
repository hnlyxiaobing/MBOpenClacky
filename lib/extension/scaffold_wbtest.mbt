///| White-box tests for the extension scaffold.

///|
test "default_template seeds sensible defaults" {
  let t = default_template("my-ext", "My Extension")
  assert_eq(t.id, "my-ext")
  assert_eq(t.name, "My Extension")
  assert_eq(t.version, "0.1.0")
  assert_eq(t.author, "Your Name")
  assert_eq(t.license, "MIT")
  assert_eq(t.contributions.length() >= 1, true)
}

///|
test "create_extension_scaffold writes manifest, contributions, and README" {
  let template : ExtensionTemplate = {
    id: "wbtest-scaffold",
    name: "WbTest Scaffold",
    version: "0.1.0",
    description: "Scaffold for wbtest",
    author: "wbtest",
    license: "MIT",
    contributions: [
      ExtensionContributionType::Panel,
      ExtensionContributionType::Skill,
    ],
  }
  let dir = @path.Path::join(".", @path.Path("_wbtest_scaffold_out")).to_string()
  // Pre-clean: in case a prior run left the directory behind.
  let _ = pre_clean(dir)
  let ext_dir = match
    create_extension_scaffold(template, output_dir=Some(dir)) {
    Ok(d) => d
    Err(e) => {
      println("scaffold failed: " + e.to_string())
      assert_eq(true, false)
      ""
    }
  }
  assert_eq(@fs.path_exists(ext_dir), true)
  assert_eq(
    @fs.path_exists(
      @path.Path::join(ext_dir, @path.Path("ext.yml")).to_string(),
    ),
    true,
  )
  assert_eq(
    @fs.path_exists(
      @path.Path::join(ext_dir, @path.Path("contributions")).to_string(),
    ),
    true,
  )
  assert_eq(
    @fs.path_exists(
      @path.Path::join(ext_dir, @path.Path("README.md")).to_string(),
    ),
    true,
  )
  // Manifest must round-trip through the loader.
  let loaded = load_single_extension(ext_dir, ExtensionSource::Local)
  match loaded {
    Some(e) => {
      assert_eq(e.manifest.id, "wbtest-scaffold")
      assert_eq(e.manifest.name, "WbTest Scaffold")
      assert_eq(e.manifest.contributions.length() == 2, true)
    }
    None => assert_eq(true, false)
  }
  // Cleanup so the test is hermetic.
  pre_clean(ext_dir)
  pre_clean(dir)
}

///|
test "create_extension_scaffold rejects duplicate directory" {
  let template : ExtensionTemplate = default_template("dup-ext", "Dup")
  let dir = @path.Path::join(".", @path.Path("_wbtest_scaffold_dup")).to_string()
  let _ = pre_clean(dir)
  let _ = match create_extension_scaffold(template, output_dir=Some(dir)) {
    Ok(d) => d
    Err(e) => {
      println("unexpected: " + e.to_string())
      assert_eq(true, false)
      ""
    }
  }
  let second = create_extension_scaffold(template, output_dir=Some(dir))
  match second {
    Ok(_) => assert_eq(true, false)
    Err(msg) => assert_eq(msg.contains("already exists"), true)
  }
  let ext_dir = @path.Path::join(dir, @path.Path("dup-ext")).to_string()
  pre_clean(ext_dir)
  pre_clean(dir)
}

///|
fn pre_clean(dir : String) -> Unit {
  if !@fs.path_exists(dir) {
    return
  }
  let entries = @fs.read_dir(dir) catch { _ => return }
  for entry in entries {
    let path = @path.Path::join(dir, @path.Path(entry)).to_string()
    let is_directory = @fs.is_dir(path) catch { _ => false }
    if is_directory {
      pre_clean(path)
    } else {
      @fs.remove_file(path) catch {
        _ => ()
      }
    }
  }
  @fs.remove_dir(dir) catch {
    _ => ()
  }
}
