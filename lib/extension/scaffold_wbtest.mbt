///| White-box tests for the extension scaffold.

///|
test "default_template seeds sensible defaults" {
  let t = default_template("my-ext", "My Extension")
  @debug.assert_eq(t.id, "my-ext")
  @debug.assert_eq(t.name, "My Extension")
  @debug.assert_eq(t.version, "0.1.0")
  @debug.assert_eq(t.author, "Your Name")
  @debug.assert_eq(t.license, "MIT")
  @debug.assert_eq(t.contributions.length() >= 1, true)
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
      @debug.assert_eq(true, false)
      ""
    }
  }
  @debug.assert_eq(@fs.path_exists(ext_dir), true)
  @debug.assert_eq(
    @fs.path_exists(
      @path.Path::join(ext_dir, @path.Path("ext.yml")).to_string(),
    ),
    true,
  )
  @debug.assert_eq(
    @fs.path_exists(
      @path.Path::join(ext_dir, @path.Path("contributions")).to_string(),
    ),
    true,
  )
  @debug.assert_eq(
    @fs.path_exists(
      @path.Path::join(ext_dir, @path.Path("README.md")).to_string(),
    ),
    true,
  )
  // Manifest must round-trip through the loader.
  let loaded = load_single_extension(ext_dir, ExtensionSource::Local)
  match loaded {
    Some(e) => {
      @debug.assert_eq(e.manifest.id, "wbtest-scaffold")
      @debug.assert_eq(e.manifest.name, "WbTest Scaffold")
      @debug.assert_eq(e.manifest.contributions.length() == 2, true)
    }
    None => @debug.assert_eq(true, false)
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
      @debug.assert_eq(true, false)
      ""
    }
  }
  let second = create_extension_scaffold(template, output_dir=Some(dir))
  match second {
    Ok(_) => @debug.assert_eq(true, false)
    Err(msg) => @debug.assert_eq(msg.contains("already exists"), true)
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

///|
test "generate_panel_template produces valid JSON with correct fields" {
  let result = generate_panel_template(
    "my-ext", "sample-panel", "My Panel", "A panel",
  )
  let json = @json.parse(result)
  match json {
    Object(obj) => {
      match obj.get("id") {
        Some(String(s)) => @debug.assert_eq(s, "sample-panel")
        _ => @debug.assert_eq(true, false)
      }
      match obj.get("type") {
        Some(String(s)) => @debug.assert_eq(s, "panel")
        _ => @debug.assert_eq(true, false)
      }
      match obj.get("extension") {
        Some(String(s)) => @debug.assert_eq(s, "my-ext")
        _ => @debug.assert_eq(true, false)
      }
      match obj.get("name") {
        Some(String(s)) => @debug.assert_eq(s, "My Panel")
        _ => @debug.assert_eq(true, false)
      }
    }
    _ => @debug.assert_eq(true, false)
  }
}

///|
test "generate_skill_template produces valid JSON" {
  let result = generate_skill_template("ext1", "sample-skill", "Skill", "desc")
  let json = @json.parse(result)
  match json {
    Object(obj) => {
      match obj.get("type") {
        Some(String(s)) => @debug.assert_eq(s, "skill")
        _ => @debug.assert_eq(true, false)
      }
      match obj.get("skills") {
        Some(Array(arr)) => @debug.assert_eq(arr.length() >= 1, true)
        _ => @debug.assert_eq(true, false)
      }
    }
    _ => @debug.assert_eq(true, false)
  }
}

///|
test "generate_agent_template produces valid JSON" {
  let result = generate_agent_template("ext1", "sample-agent", "Agent", "desc")
  let json = @json.parse(result)
  match json {
    Object(obj) => {
      match obj.get("type") {
        Some(String(s)) => @debug.assert_eq(s, "agent")
        _ => @debug.assert_eq(true, false)
      }
      match obj.get("config") {
        Some(Object(_)) => ()
        _ => @debug.assert_eq(true, false)
      }
    }
    _ => @debug.assert_eq(true, false)
  }
}

///|
test "generate_api_template produces valid JSON with routes" {
  let result = generate_api_template("ext1", "sample-api", "API", "desc")
  let json = @json.parse(result)
  match json {
    Object(obj) => {
      match obj.get("type") {
        Some(String(s)) => @debug.assert_eq(s, "api")
        _ => @debug.assert_eq(true, false)
      }
      match obj.get("routes") {
        Some(Array(arr)) => @debug.assert_eq(arr.length() >= 1, true)
        _ => @debug.assert_eq(true, false)
      }
    }
    _ => @debug.assert_eq(true, false)
  }
}

///|
test "generate_hook_template produces valid JSON with hooks" {
  let result = generate_hook_template("ext1", "sample-hook", "Hook", "desc")
  let json = @json.parse(result)
  match json {
    Object(obj) => {
      match obj.get("type") {
        Some(String(s)) => @debug.assert_eq(s, "hook")
        _ => @debug.assert_eq(true, false)
      }
      match obj.get("hooks") {
        Some(Array(arr)) => @debug.assert_eq(arr.length() >= 1, true)
        _ => @debug.assert_eq(true, false)
      }
    }
    _ => @debug.assert_eq(true, false)
  }
}

///|
test "generate_patch_template produces valid JSON with patches" {
  let result = generate_patch_template("ext1", "sample-patch", "Patch", "desc")
  let json = @json.parse(result)
  match json {
    Object(obj) => {
      match obj.get("type") {
        Some(String(s)) => @debug.assert_eq(s, "patch")
        _ => @debug.assert_eq(true, false)
      }
      match obj.get("patches") {
        Some(Array(arr)) => @debug.assert_eq(arr.length() >= 1, true)
        _ => @debug.assert_eq(true, false)
      }
    }
    _ => @debug.assert_eq(true, false)
  }
}

///|
test "contribution_type_name maps each variant" {
  @debug.assert_eq(
    contribution_type_name(ExtensionContributionType::Panel),
    "panel",
  )
  @debug.assert_eq(
    contribution_type_name(ExtensionContributionType::Skill),
    "skill",
  )
  @debug.assert_eq(
    contribution_type_name(ExtensionContributionType::Agent),
    "agent",
  )
  @debug.assert_eq(
    contribution_type_name(ExtensionContributionType::Api),
    "api",
  )
  @debug.assert_eq(
    contribution_type_name(ExtensionContributionType::Hook),
    "hook",
  )
  @debug.assert_eq(
    contribution_type_name(ExtensionContributionType::Patch),
    "patch",
  )
}

///|
test "generate_readme includes name, description, and license" {
  let template : ExtensionTemplate = {
    id: "readme-test",
    name: "Readme Test Extension",
    version: "1.0.0",
    description: "Testing README generation",
    author: "TestAuthor",
    license: "Apache-2.0",
    contributions: [
      ExtensionContributionType::Panel,
      ExtensionContributionType::Skill,
    ],
  }
  let readme = generate_readme(template)
  @debug.assert_eq(readme.contains("Readme Test Extension"), true)
  @debug.assert_eq(readme.contains("Testing README generation"), true)
  @debug.assert_eq(readme.contains("Apache-2.0"), true)
  @debug.assert_eq(readme.contains("TestAuthor"), true)
  @debug.assert_eq(readme.contains("panel"), true)
  @debug.assert_eq(readme.contains("skill"), true)
  @debug.assert_eq(readme.contains("readme-test"), true)
}

///|
test "generate_readme with empty contributions" {
  let template : ExtensionTemplate = {
    id: "empty-ext",
    name: "Empty",
    version: "0.1.0",
    description: "No contributions",
    author: "Nobody",
    license: "MIT",
    contributions: [],
  }
  let readme = generate_readme(template)
  @debug.assert_eq(readme.contains("Empty"), true)
  @debug.assert_eq(readme.contains("## Contributions"), true)
}

///|
test "generate_manifest_json produces valid JSON with all fields" {
  let manifest : ExtensionManifest = {
    id: "manifest-test",
    name: "Manifest Test",
    version: "3.1.0",
    description: "Testing manifest JSON",
    author: "Author",
    license: "MIT",
    homepage: Some("https://example.com"),
    repository: Some("https://github.com/example/repo"),
    keywords: ["test", "manifest"],
    dependencies: { "dep-a": "^1.0.0" },
    contributions: [
      {
        type_: ExtensionContributionType::Panel,
        id: "main-panel",
        name: "Main Panel",
        description: "A panel",
        path: "contributions/panel.json",
        config: Map([]),
      },
    ],
    enabled_by_default: true,
  }
  let json_str = generate_manifest_json(manifest)
  let json = @json.parse(json_str)
  match json {
    Object(obj) => {
      match obj.get("id") {
        Some(String(s)) => @debug.assert_eq(s, "manifest-test")
        _ => @debug.assert_eq(true, false)
      }
      match obj.get("version") {
        Some(String(s)) => @debug.assert_eq(s, "3.1.0")
        _ => @debug.assert_eq(true, false)
      }
      match obj.get("homepage") {
        Some(String(s)) => @debug.assert_eq(s, "https://example.com")
        _ => @debug.assert_eq(true, false)
      }
      match obj.get("repository") {
        Some(String(s)) =>
          @debug.assert_eq(s, "https://github.com/example/repo")
        _ => @debug.assert_eq(true, false)
      }
      match obj.get("enabled_by_default") {
        Some(True) => @debug.assert_eq(true, true)
        _ => @debug.assert_eq(true, false)
      }
      match obj.get("keywords") {
        Some(Array(arr)) => @debug.assert_eq(arr.length(), 2)
        _ => @debug.assert_eq(true, false)
      }
      match obj.get("contributions") {
        Some(Array(arr)) => @debug.assert_eq(arr.length(), 1)
        _ => @debug.assert_eq(true, false)
      }
      match obj.get("dependencies") {
        Some(Object(dep)) => @debug.assert_eq(dep.contains("dep-a"), true)
        _ => @debug.assert_eq(true, false)
      }
    }
    _ => @debug.assert_eq(true, false)
  }
}

///|
test "generate_manifest_json omits homepage/repository when None" {
  let manifest : ExtensionManifest = {
    id: "no-links",
    name: "No Links",
    version: "1.0.0",
    description: "No homepage or repo",
    author: "A",
    license: "MIT",
    homepage: None,
    repository: None,
    keywords: [],
    dependencies: Map([]),
    contributions: [],
    enabled_by_default: false,
  }
  let json_str = generate_manifest_json(manifest)
  let json = @json.parse(json_str)
  match json {
    Object(obj) => {
      @debug.assert_eq(obj.contains("homepage"), false)
      @debug.assert_eq(obj.contains("repository"), false)
    }
    _ => @debug.assert_eq(true, false)
  }
}
