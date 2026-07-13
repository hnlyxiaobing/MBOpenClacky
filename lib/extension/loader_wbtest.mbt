///| White-box tests for the extension loader API-contribution helpers.

///|
test "collect_api_contribution_paths: empty extension list yields empty result" {
  let result = collect_api_contribution_paths([])
  @debug.assert_eq(result.length(), 0)
}

///|
test "collect_api_contribution_paths: disabled extension is skipped" {
  let exts : Array[Extension] = [
    {
      manifest: {
        id: "test-ext",
        name: "Test",
        version: "1.0.0",
        description: "",
        author: "",
        license: "",
        homepage: None,
        repository: None,
        keywords: [],
        dependencies: {},
        contributions: [
          {
            type_: ExtensionContributionType::Api,
            id: "api1",
            name: "API",
            description: "",
            path: "api.json",
            config: {},
          },
        ],
        enabled_by_default: true,
      },
      source: ExtensionSource::Local,
      root_path: "/tmp/non-existent",
      enabled: false, // <-- disabled
      loaded_at: 0L,
      sha256: None,
    },
  ]
  let result = collect_api_contribution_paths(exts)
  @debug.assert_eq(result.length(), 0)
}

///|
test "collect_api_contribution_paths: non-Api contribution is skipped" {
  // Create a real temp dir with a fake manifest; only Panel contribution
  // exists, so no api contribution should be collected.
  let tmp = @path.Path::join(
    @utils.current_dir(),
    @path.Path("_wbtest_loader_api"),
  ).to_string()
  // Ensure parent dir exists
  let _ = @fs.create_dir(tmp) catch { _ => () }
  let exts : Array[Extension] = [
    {
      manifest: {
        id: "panel-only",
        name: "Panel",
        version: "1.0.0",
        description: "",
        author: "",
        license: "",
        homepage: None,
        repository: None,
        keywords: [],
        dependencies: {},
        contributions: [
          {
            type_: ExtensionContributionType::Panel,
            id: "p1",
            name: "Panel",
            description: "",
            path: "panel.html",
            config: {},
          },
        ],
        enabled_by_default: true,
      },
      source: ExtensionSource::Local,
      root_path: tmp,
      enabled: true,
      loaded_at: 0L,
      sha256: None,
    },
  ]
  let result = collect_api_contribution_paths(exts)
  @debug.assert_eq(result.length(), 0)
  // Cleanup
  let _ = @fs.remove_dir(tmp) catch { _ => () }
}

///|
test "collect_api_contribution_paths: missing path file is skipped (no crash)" {
  let tmp = @path.Path::join(
    @utils.current_dir(),
    @path.Path("_wbtest_loader_api_missing"),
  ).to_string()
  let _ = @fs.create_dir(tmp) catch { _ => () }
  let exts : Array[Extension] = [
    {
      manifest: {
        id: "ghost-ext",
        name: "Ghost",
        version: "1.0.0",
        description: "",
        author: "",
        license: "",
        homepage: None,
        repository: None,
        keywords: [],
        dependencies: {},
        contributions: [
          {
            type_: ExtensionContributionType::Api,
            id: "api1",
            name: "API",
            description: "",
            path: "nonexistent.json",
            config: {},
          },
        ],
        enabled_by_default: true,
      },
      source: ExtensionSource::Local,
      root_path: tmp,
      enabled: true,
      loaded_at: 0L,
      sha256: None,
    },
  ]
  // Should not throw — file simply does not exist
  let result = collect_api_contribution_paths(exts)
  @debug.assert_eq(result.length(), 0)
  let _ = @fs.remove_dir(tmp) catch { _ => () }
}

///|
test "collect_api_contribution_paths: existing JSON file is collected" {
  // Build a real directory tree with ext.yml + api.json
  let tmp = @path.Path::join(
    @utils.current_dir(),
    @path.Path("_wbtest_loader_api_ok"),
  ).to_string()
  let _ = @fs.create_dir(tmp) catch { _ => () }
  let json_path = @path.Path::join(tmp, @path.Path("api.json")).to_string()
  let json_content =
    #| {
    #|   "name": "myapi",
    #|   "version": "1.0.0",
    #|   "enabled": true,
    #|   "routes": [
    #|     {
    #|       "method": "GET",
    #|       "path": "/hello",
    #|       "handler_name": "hello",
    #|       "command": "echo hi"
    #|     }
    #|   ]
    #| }
  @fs.write_string_to_file(json_path, json_content) catch {
    _ => ()
  }
  let exts : Array[Extension] = [
    {
      manifest: {
        id: "real-ext",
        name: "Real",
        version: "1.0.0",
        description: "",
        author: "",
        license: "",
        homepage: None,
        repository: None,
        keywords: [],
        dependencies: {},
        contributions: [
          {
            type_: ExtensionContributionType::Api,
            id: "api1",
            name: "API",
            description: "",
            path: "api.json",
            config: {},
          },
        ],
        enabled_by_default: true,
      },
      source: ExtensionSource::Local,
      root_path: tmp,
      enabled: true,
      loaded_at: 0L,
      sha256: None,
    },
  ]
  let result = collect_api_contribution_paths(exts)
  @debug.assert_eq(result.length(), 1)
  let (ext_id, abs_path) = result[0]
  @debug.assert_eq(ext_id, "real-ext")
  assert_true(abs_path.has_suffix("api.json"))
  // Cleanup
  let _ = @fs.remove_file(json_path) catch { _ => () }
  let _ = @fs.remove_dir(tmp) catch { _ => () }
}

///|
test "collect_api_contribution_paths: empty contribution path is skipped" {
  let exts : Array[Extension] = [
    {
      manifest: {
        id: "empty-path",
        name: "Empty",
        version: "1.0.0",
        description: "",
        author: "",
        license: "",
        homepage: None,
        repository: None,
        keywords: [],
        dependencies: {},
        contributions: [
          {
            type_: ExtensionContributionType::Api,
            id: "api1",
            name: "API",
            description: "",
            path: "",
            config: {},
          },
        ],
        enabled_by_default: true,
      },
      source: ExtensionSource::Local,
      root_path: "/tmp",
      enabled: true,
      loaded_at: 0L,
      sha256: None,
    },
  ]
  let result = collect_api_contribution_paths(exts)
  @debug.assert_eq(result.length(), 0)
}

///|
test "collect_api_contribution_paths: multiple extensions aggregate paths" {
  // Two extensions, each with one Api contribution
  let tmp1 = @path.Path::join(
    @utils.current_dir(),
    @path.Path("_wbtest_loader_api_agg1"),
  ).to_string()
  let tmp2 = @path.Path::join(
    @utils.current_dir(),
    @path.Path("_wbtest_loader_api_agg2"),
  ).to_string()
  let _ = @fs.create_dir(tmp1) catch { _ => () }
  let _ = @fs.create_dir(tmp2) catch { _ => () }
  let f1 = @path.Path::join(tmp1, @path.Path("a.json")).to_string()
  let f2 = @path.Path::join(tmp2, @path.Path("b.toml")).to_string()
  @fs.write_string_to_file(f1, "{\"name\":\"a\",\"version\":\"1.0\"}") catch {
    _ => ()
  }
  @fs.write_string_to_file(f2, "name = \"b\"\nversion = \"1.0\"") catch {
    _ => ()
  }
  let exts : Array[Extension] = [
    {
      manifest: make_minimal_manifest("ext1"),
      source: ExtensionSource::Local,
      root_path: tmp1,
      enabled: true,
      loaded_at: 0L,
      sha256: None,
    },
    {
      manifest: make_minimal_manifest("ext2"),
      source: ExtensionSource::Local,
      root_path: tmp2,
      enabled: true,
      loaded_at: 0L,
      sha256: None,
    },
  ]
  // Inject api contribution into both manifests via the helper
  let with_contribs = inject_api_contrib(exts, "ext1", "a.json")
  let with_contribs2 = inject_api_contrib(with_contribs, "ext2", "b.toml")
  let result = collect_api_contribution_paths(with_contribs2)
  @debug.assert_eq(result.length(), 2)
  let names = collect_names(result)
  assert_true(names.contains("ext1"))
  assert_true(names.contains("ext2"))
  // Cleanup
  let _ = @fs.remove_file(f1) catch { _ => () }
  let _ = @fs.remove_file(f2) catch { _ => () }
  let _ = @fs.remove_dir(tmp1) catch { _ => () }
  let _ = @fs.remove_dir(tmp2) catch { _ => () }
}

// ── Test helpers ──────────────────────────────────────────────

///|
/// Build a minimal ExtensionManifest with a single panel contribution
/// (no api contribution). Test code calls `inject_api_contrib` to add
/// the api contribution after construction.
fn make_minimal_manifest(id : String) -> ExtensionManifest {
  {
    id,
    name: id,
    version: "1.0.0",
    description: "",
    author: "",
    license: "",
    homepage: None,
    repository: None,
    keywords: [],
    dependencies: {},
    contributions: [
      {
        type_: ExtensionContributionType::Panel,
        id: "p1",
        name: "p",
        description: "",
        path: "panel.html",
        config: {},
      },
    ],
    enabled_by_default: true,
  }
}

///|
/// Return a new array where the extension with the given `id` has an
/// extra api contribution appended to its contributions list.
fn inject_api_contrib(
  exts : Array[Extension],
  id : String,
  api_path : String,
) -> Array[Extension] {
  let result : Array[Extension] = []
  for ext in exts {
    if ext.manifest.id == id {
      let new_contribs : Array[ExtensionContribution] = []
      for c in ext.manifest.contributions {
        new_contribs.push(c)
      }
      new_contribs.push({
        type_: ExtensionContributionType::Api,
        id: "api_" + id,
        name: "API",
        description: "",
        path: api_path,
        config: {},
      })
      result.push({
        ..ext,
        manifest: { ..ext.manifest, contributions: new_contribs },
      })
    } else {
      result.push(ext)
    }
  }
  result
}

///|
/// Extract the extension ids from a list of (id, path) tuples.
fn collect_names(pairs : Array[(String, String)]) -> Array[String] {
  let names : Array[String] = []
  for p in pairs {
    names.push(p.0)
  }
  names
}
