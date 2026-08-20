///|
/// Regression tests for disk-based default skill scanning (spec
/// 2026-08-18_20): the hardcoded table is gone; `assets/skills/*/SKILL.md`
/// is the single source of truth.
///
/// `moon test` executes with the project root as CWD (same convention as
/// lib/web contract tests using `assets/agents`).

///|
/// Locate the bundled assets/skills directory from the test CWD.
fn test_assets_skills_dir() -> String {
  "assets/skills"
}

///|
/// Containment check for arrays of strings.
fn arr_contains(arr : Array[String], target : String) -> Bool {
  for item in arr {
    if item == target {
      return true
    }
  }
  false
}

///|
test "default skills scan: bundled assets are the single source of truth" {
  let metas = scan_default_skill_metas(test_assets_skills_dir())
  // All 18 bundled skill directories must be discoverable.
  @debug.assert_eq(metas.length(), 18)
  // Metadata comes from each SKILL.md frontmatter, not a hardcoded table.
  let names : Array[String] = []
  for meta in metas {
    names.push(meta.name)
  }
  // The four entries whose hardcoded names used underscores are now the
  // real on-disk (hyphenated) names from SKILL.md.
  assert_true(arr_contains(names, "browser-setup"))
  assert_true(arr_contains(names, "channel-manager"))
  assert_true(arr_contains(names, "personal-website"))
  assert_true(arr_contains(names, "skill-add"))
  // Skills that existed only on disk before are now included.
  assert_true(arr_contains(names, "extend-openclacky"))
  assert_true(arr_contains(names, "meeting-summarizer"))
  // No underscore variants remain.
  assert_false(arr_contains(names, "browser_setup"))
  assert_false(arr_contains(names, "channel_manager"))
  assert_false(arr_contains(names, "personal_website"))
  assert_false(arr_contains(names, "skill_add"))
}

///|
test "default skills scan: metadata loaded from frontmatter" {
  let metas = scan_default_skill_metas(test_assets_skills_dir())
  // Every scanned meta must carry a description from its SKILL.md.
  for meta in metas {
    assert_false(meta.description.is_empty())
  }
  // Spot-check browser-setup metadata comes from real frontmatter.
  let mut browser_setup : DefaultSkillMeta? = None
  for meta in metas {
    if meta.name == "browser-setup" {
      browser_setup = Some(meta)
      break
    }
  }
  assert_true(browser_setup is Some(_))
}

///|
test "default skills register: lazy entries resolve bodies from disk" {
  let registry = SkillRegistry::new()
  register_default_skills_from(registry, test_assets_skills_dir())
  // The mismatched-skills regression: every registered builtin skill's
  // directory must actually contain a readable SKILL.md whose frontmatter
  // parses back to the same name (the old hardcoded table pointed
  // browser_setup et al. at non-existent underscore directories).
  let mismatch_names = [
    "browser-setup", "channel-manager", "personal-website", "skill-add",
  ]
  for name in mismatch_names {
    let skill = registry.get(name)
    assert_true(skill is Some(_))
    let s = skill.unwrap()
    @debug.assert_eq(s.source, "builtin")
    assert_true(s.directory is Some(_))
    let dir = s.directory.unwrap()
    let path = dir + "/SKILL.md"
    let content = @fs.read_file_to_string(path) catch {
      _ => {
        assert_true(false) // directory must be readable
        ""
      }
    }
    assert_false(content.is_empty())
    match load_skill_from_content(content, path, Some(dir)) {
      Some(full) => @debug.assert_eq(full.name, name)
      None => assert_true(false)
    }
  }
  // Registration is metadata-only: bodies stay lazy (context None).
  let s = registry.get("deploy").unwrap()
  assert_true(s.context is None)
}

///|
test "default skills register: full registry matches disk directories" {
  let registry = SkillRegistry::new()
  register_default_skills_from(registry, test_assets_skills_dir())
  let skills = registry.all()
  @debug.assert_eq(skills.length(), 18)
  for skill in skills {
    assert_true(skill.directory is Some(_))
    let dir = skill.directory.unwrap()
    let path = dir + "/SKILL.md"
    let content = @fs.read_file_to_string(path) catch { _ => "" }
    assert_false(content.is_empty())
  }
}

///|
test "default skills scan: myskill.md files are not collected" {
  // Build a temp skills root with one valid skill dir and a stray
  // `myskill.md` file; only the SKILL.md entry may be scanned.
  let root = "tmp_scan_test_skills"
  @utils.ensure_dir(root + "/real-skill")
  @fs.write_string_to_file(
    root + "/real-skill/SKILL.md",
    "---\nname: real-skill\ndescription: A real skill.\n---\n\nBody.\n",
  ) catch {
    _ => ()
  }
  @fs.write_string_to_file(
    root + "/myskill.md",
    "---\nname: myskill\ndescription: Not a skill directory.\n---\n\nBody.\n",
  ) catch {
    _ => ()
  }
  let metas = scan_default_skill_metas(root)
  @debug.assert_eq(metas.length(), 1)
  @debug.assert_eq(metas[0].name, "real-skill")
  // Cleanup.
  @fs.remove_file(root + "/real-skill/SKILL.md") catch {
    _ => ()
  }
  @fs.remove_file(root + "/myskill.md") catch {
    _ => ()
  }
  @fs.remove_dir(root + "/real-skill") catch {
    _ => ()
  }
  @fs.remove_dir(root) catch {
    _ => ()
  }
}

///|
test "default skills scan: name falls back to directory name" {
  let root = "tmp_scan_fallback_skills"
  @utils.ensure_dir(root + "/no-name-skill")
  @fs.write_string_to_file(
    root + "/no-name-skill/SKILL.md",
    "---\ndescription: No name in frontmatter.\n---\n\nBody.\n",
  ) catch {
    _ => ()
  }
  let metas = scan_default_skill_metas(root)
  @debug.assert_eq(metas.length(), 1)
  @debug.assert_eq(metas[0].name, "no-name-skill")
  @fs.remove_file(root + "/no-name-skill/SKILL.md") catch {
    _ => ()
  }
  @fs.remove_dir(root + "/no-name-skill") catch {
    _ => ()
  }
  @fs.remove_dir(root) catch {
    _ => ()
  }
}

///|
test "default skills scan: missing directory yields empty list" {
  let metas = scan_default_skill_metas("does/not/exist")
  @debug.assert_eq(metas.length(), 0)
}
