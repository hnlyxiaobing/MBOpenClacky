///| Extended extension tests: types, enums, manifest construction, validation.

// ── ExtensionSource Tests ───────────────────────────────────────────────────

///|
test "ext_ext_source_equality" {
  assert_true(ExtensionSource::Builtin == ExtensionSource::Builtin)
  assert_true(ExtensionSource::Installed != ExtensionSource::Local)
}

///|
test "ext_ext_source_variants" {
  let sources = [Builtin, Installed, Local]
  assert_eq(sources.length(), 3)
}

// ── ExtensionContributionType Tests ─────────────────────────────────────────

///|
test "ext_contribution_type_equality" {
  assert_true(
    ExtensionContributionType::Panel == ExtensionContributionType::Panel,
  )
  assert_true(
    ExtensionContributionType::Skill != ExtensionContributionType::Agent,
  )
}

///|
test "ext_contribution_type_all_variants" {
  let types = [Panel, Skill, Agent, Api, Hook, Patch]
  assert_eq(types.length(), 6)
}

// ── ValidationError Tests ───────────────────────────────────────────────────

///|
test "ext_validation_error_missing_field" {
  let e = ValidationError::MissingRequiredField("id")
  assert_true(e is MissingRequiredField(_))
}

///|
test "ext_validation_error_invalid_field" {
  let e = ValidationError::InvalidField("version", "not semver")
  assert_true(e is InvalidField(_, _))
}

///|
test "ext_validation_error_invalid_version" {
  let e = ValidationError::InvalidVersion("abc")
  assert_true(e is InvalidVersion(_))
}

///|
test "ext_validation_error_dependency_conflict" {
  let e = ValidationError::DependencyConflict("ext-a", "ext-b")
  assert_true(e is DependencyConflict(_, _))
}

// ── ValidationResult Tests ──────────────────────────────────────────────────

///|
test "ext_validation_result_valid" {
  let r : ValidationResult = { valid: true, errors: [], warnings: [] }
  assert_true(r.valid)
  assert_eq(r.errors.length(), 0)
}

///|
test "ext_validation_result_with_errors" {
  let r : ValidationResult = {
    valid: false,
    errors: [ValidationError::MissingRequiredField("name")],
    warnings: ["deprecated field used"],
  }
  assert_false(r.valid)
  assert_eq(r.errors.length(), 1)
  assert_eq(r.warnings.length(), 1)
}

// ── ExtensionManifest Tests ────────────────────────────────────────────────

///|
test "ext_manifest_construction" {
  let m : ExtensionManifest = {
    id: "my-ext",
    name: "My Extension",
    version: "1.0.0",
    description: "A test extension",
    author: "Test",
    license: "MIT",
    homepage: None,
    repository: None,
    keywords: ["test", "demo"],
    dependencies: Map([]),
    contributions: [],
    enabled_by_default: true,
  }
  assert_eq(m.id, "my-ext")
  assert_eq(m.version, "1.0.0")
  assert_eq(m.keywords.length(), 2)
  assert_true(m.enabled_by_default)
}

///|
test "ext_manifest_with_homepage" {
  let m : ExtensionManifest = {
    id: "ext",
    name: "Ext",
    version: "0.1",
    description: "",
    author: "",
    license: "",
    homepage: Some("https://example.com"),
    repository: Some("https://github.com/test/ext"),
    keywords: [],
    dependencies: Map([]),
    contributions: [],
    enabled_by_default: false,
  }
  assert_true(m.homepage is Some(_))
  assert_true(m.repository is Some(_))
}

// ── ExtensionContribution Tests ─────────────────────────────────────────────

///|
test "ext_contribution_construction" {
  let c : ExtensionContribution = {
    type_: ExtensionContributionType::Panel,
    id: "my-panel",
    name: "My Panel",
    description: "A test panel",
    path: "./panel.html",
    config: Map([]),
  }
  assert_eq(c.id, "my-panel")
  assert_true(c.type_ == ExtensionContributionType::Panel)
}

// ── RegistryEntry Tests ─────────────────────────────────────────────────────

///|
test "ext_registry_entry_construction" {
  let r : RegistryEntry = {
    id: "ext-1",
    latest_version: "2.0.0",
    versions: ["1.0.0", "2.0.0"],
    metadata: Map([]),
    installs: 100,
    published_at: 1000L,
  }
  assert_eq(r.id, "ext-1")
  assert_eq(r.latest_version, "2.0.0")
  assert_eq(r.versions.length(), 2)
  assert_eq(r.installs, 100)
}

// ── extension_id & source_dir Tests ────────────────────────────────────────

///|
test "ext_extension_id_from_manifest" {
  let m : ExtensionManifest = {
    id: "test-id",
    name: "Test",
    version: "1.0",
    description: "",
    author: "",
    license: "",
    homepage: None,
    repository: None,
    keywords: [],
    dependencies: Map([]),
    contributions: [],
    enabled_by_default: true,
  }
  let ext : Extension = {
    manifest: m,
    source: ExtensionSource::Builtin,
    root_path: "/path",
    enabled: true,
    loaded_at: 0L,
    sha256: None,
  }
  assert_eq(extension_id(ext), "test-id")
}

///|
test "ext_source_dir_all_sources" {
  let builtin_dir = source_dir(ExtensionSource::Builtin)
  let installed_dir = source_dir(ExtensionSource::Installed)
  let local_dir = source_dir(ExtensionSource::Local)
  assert_true(builtin_dir.length() > 0)
  assert_true(installed_dir.length() > 0)
  assert_true(local_dir.length() > 0)
}

// ── Additional ExtensionSource Tests ────────────────────────────────────────

///|
test "ext_ext_source_all_distinct" {
  let sources = [Builtin, Installed, Local]
  for i = 0; i < sources.length(); i = i + 1 {
    for j = 0; j < sources.length(); j = j + 1 {
      if i == j {
        assert_true(sources[i] == sources[j])
      } else {
        assert_true(sources[i] != sources[j])
      }
    }
  }
}

// ── Additional ExtensionContributionType Tests ──────────────────────────────

///|
test "ext_contribution_type_all_distinct" {
  let types = [Panel, Skill, Agent, Api, Hook, Patch]
  for i = 0; i < types.length(); i = i + 1 {
    for j = 0; j < types.length(); j = j + 1 {
      if i == j {
        assert_true(types[i] == types[j])
      } else {
        assert_true(types[i] != types[j])
      }
    }
  }
}

// ── Additional ValidationError Tests ───────────────────────────────────────

///|
test "ext_validation_error_all_variants" {
  let e1 = MissingRequiredField("f1")
  let e2 = InvalidField("f2", "bad")
  let e3 = InvalidContributionType("unknown")
  let e4 = MissingResource("path")
  let e5 = DependencyConflict("a", "b")
  let e6 = InvalidVersion("1.x")
  assert_true(e1 is MissingRequiredField(_))
  assert_true(e2 is InvalidField(_, _))
  assert_true(e3 is InvalidContributionType(_))
  assert_true(e4 is MissingResource(_))
  assert_true(e5 is DependencyConflict(_, _))
  assert_true(e6 is InvalidVersion(_))
}

// ── Additional ExtensionManifest Tests ──────────────────────────────────────

///|
test "ext_manifest_with_dependencies" {
  let deps : Map[String, String] = Map([])
  deps.set("ext-a", ">=1.0.0")
  deps.set("ext-b", "^2.0.0")
  let m : ExtensionManifest = {
    id: "dep-ext",
    name: "Dep",
    version: "1.0.0",
    description: "",
    author: "",
    license: "",
    homepage: None,
    repository: None,
    keywords: [],
    dependencies: deps,
    contributions: [],
    enabled_by_default: true,
  }
  assert_eq(m.dependencies.length(), 2)
}

///|
test "ext_manifest_with_contributions" {
  let c : ExtensionContribution = {
    type_: Skill,
    id: "my-skill",
    name: "My Skill",
    description: "A skill",
    path: "./skill.md",
    config: Map([]),
  }
  let m : ExtensionManifest = {
    id: "ext",
    name: "Ext",
    version: "1.0",
    description: "",
    author: "",
    license: "",
    homepage: None,
    repository: None,
    keywords: [],
    dependencies: Map([]),
    contributions: [c],
    enabled_by_default: false,
  }
  assert_eq(m.contributions.length(), 1)
}

// ── Additional Extension Tests ──────────────────────────────────────────────

///|
test "ext_extension_with_sha256" {
  let m : ExtensionManifest = {
    id: "id",
    name: "N",
    version: "1.0",
    description: "",
    author: "",
    license: "",
    homepage: None,
    repository: None,
    keywords: [],
    dependencies: Map([]),
    contributions: [],
    enabled_by_default: true,
  }
  let ext : Extension = {
    manifest: m,
    source: Installed,
    root_path: "/path",
    enabled: false,
    loaded_at: 100L,
    sha256: Some("abc123"),
  }
  assert_true(ext.sha256 is Some(_))
  assert_false(ext.enabled)
}

///|
test "ext_extension_disabled" {
  let m : ExtensionManifest = {
    id: "id",
    name: "N",
    version: "1.0",
    description: "",
    author: "",
    license: "",
    homepage: None,
    repository: None,
    keywords: [],
    dependencies: Map([]),
    contributions: [],
    enabled_by_default: false,
  }
  let ext : Extension = {
    manifest: m,
    source: Local,
    root_path: ".",
    enabled: false,
    loaded_at: 0L,
    sha256: None,
  }
  assert_false(ext.enabled)
  assert_true(ext.source == Local)
}

// ── Additional ValidationResult Tests ──────────────────────────────────────

///|
test "ext_validation_result_multiple_errors" {
  let r : ValidationResult = {
    valid: false,
    errors: [
      MissingRequiredField("id"),
      MissingRequiredField("name"),
      InvalidVersion("bad"),
    ],
    warnings: ["w1", "w2", "w3"],
  }
  assert_eq(r.errors.length(), 3)
  assert_eq(r.warnings.length(), 3)
}

///|
test "ext_registry_entry_with_metadata" {
  let meta : Map[String, String] = Map([])
  meta.set("author", "TestAuthor")
  meta.set("description", "Test extension")
  let r : RegistryEntry = {
    id: "ext-meta",
    latest_version: "3.0.0",
    versions: ["1.0.0", "2.0.0", "3.0.0"],
    metadata: meta,
    installs: 500,
    published_at: 99999L,
  }
  assert_eq(r.metadata.length(), 2)
  assert_eq(r.versions.length(), 3)
}
