///| White-box tests for the evolution log and proposal write-back.

///|
/// A hermetic temp directory — tests must never touch the real
/// `~/.mbopenclacky/skills/`.
fn test_tmp_dir(name : String) -> String {
  let base = match @env.get_env_var("TEMP") {
    Some(t) if !t.is_empty() => t
    _ =>
      match @env.get_env_var("TMPDIR") {
        Some(t) if !t.is_empty() => t
        _ => "/tmp"
      }
  }
  @path.Path::join(
    @path.Path(base),
    @path.Path("mbopenclacky_skill_test_" + name),
  ).to_string()
}

///|
fn tmp_file(dir : String, name : String) -> String {
  @path.Path::join(@path.Path(dir), @path.Path(name)).to_string()
}

///|
fn write_file_or_fail(path : String, content : String) -> Unit {
  @utils.ensure_dir(@path.Path::dirname(@path.Path(path)).to_string())
  @fs.write_string_to_file(path, content) catch {
    e => abort("test setup failed writing " + path + ": " + @debug.to_string(e))
  }
}

///|
fn read_file_or_fail(path : String) -> String {
  @fs.read_file_to_string(path) catch {
    _ => abort("expected file is unreadable: " + path)
  }
}

///|
fn sample_entry(action : String) -> EvolutionLogEntry {
  let e = EvolutionLogEntry::new("deploy-helper", "user", 40, true, action)
  e.suggestions = ["add a retry step", "document the EACCES pitfall"]
  e.model = Some("lite:test")
  e
}

///|
test "evolution_log_round_trip_preserves_fields" {
  let path = tmp_file(test_tmp_dir("round_trip"), "log.json")
  let entry = sample_entry("proposed")
  entry.backup_path = Some("/somewhere/SKILL.md.bak.1")
  match append_evolution_log_at(path, entry) {
    Ok(_) => ()
    Err(e) => fail("append failed: " + e)
  }
  let loaded = load_evolution_log_at(path)
  @debug.assert_eq(loaded.length(), 1)
  let got = loaded[0]
  @debug.assert_eq(got.id, entry.id)
  @debug.assert_eq(got.skill_name, "deploy-helper")
  @debug.assert_eq(got.source, "user")
  @debug.assert_eq(got.score, 40)
  @debug.assert_eq(got.should_improve, true)
  @debug.assert_eq(got.action, "proposed")
  @debug.assert_eq(got.suggestions, [
    "add a retry step", "document the EACCES pitfall",
  ])
  @debug.assert_eq(got.backup_path, Some("/somewhere/SKILL.md.bak.1"))
  @debug.assert_eq(got.model, Some("lite:test"))
  @debug.assert_eq(got.error, None)
  @fs.remove_file(path) catch {
    _ => ()
  }
}

///|
test "evolution_log_is_newest_first" {
  let path = tmp_file(test_tmp_dir("ordering"), "log.json")
  let first = sample_entry("no_change")
  let second = EvolutionLogEntry::new(
    "other-skill", "default", 20, true, "error",
  )
  append_evolution_log_at(path, first) |> ignore
  append_evolution_log_at(path, second) |> ignore
  let loaded = load_evolution_log_at(path)
  @debug.assert_eq(loaded.length(), 2)
  @debug.assert_eq(loaded[0].id, second.id)
  @debug.assert_eq(loaded[1].id, first.id)
  @fs.remove_file(path) catch {
    _ => ()
  }
}

///|
test "evolution_log_tolerates_entries_with_missing_fields" {
  let path = tmp_file(test_tmp_dir("tolerant"), "log.json")
  let seeded =
    #|[{"skill_name":"partial","score":7},{"id":"only-id"},42,"not-an-object"]
  write_file_or_fail(path, seeded)
  let loaded = load_evolution_log_at(path)
  // Two decodable objects survive; the number and string are skipped.
  @debug.assert_eq(loaded.length(), 2)
  @debug.assert_eq(loaded[0].skill_name, "partial")
  @debug.assert_eq(loaded[0].score, 7)
  @debug.assert_eq(loaded[0].source, "user")
  @debug.assert_eq(loaded[0].action, "no_change")
  @debug.assert_eq(loaded[0].suggestions.length(), 0)
  @debug.assert_eq(loaded[1].id, "only-id")
  @fs.remove_file(path) catch {
    _ => ()
  }
}

///|
test "evolution_log_malformed_file_is_empty_and_left_intact" {
  let path = tmp_file(test_tmp_dir("malformed"), "log.json")
  let garbage = "{\"not\": \"an array\""
  write_file_or_fail(path, garbage)
  @debug.assert_eq(load_evolution_log_at(path).length(), 0)
  // The damaged log must not be silently destroyed.
  @debug.assert_eq(read_file_or_fail(path), garbage)
  @fs.remove_file(path) catch {
    _ => ()
  }
}

///|
test "evolution_log_missing_file_is_empty" {
  let path = tmp_file(test_tmp_dir("absent"), "does_not_exist.json")
  @debug.assert_eq(load_evolution_log_at(path).length(), 0)
}

///|
test "evolution_log_truncates_to_max_entries" {
  let dir = test_tmp_dir("truncate")
  let path = tmp_file(dir, "log.json")
  // Seed exactly the cap (500) so one append must evict the oldest.
  let sb = StringBuilder()
  sb.write_string("[")
  for i = 0; i < 500; i = i + 1 {
    if i > 0 {
      sb.write_string(",")
    }
    sb.write_string(
      "{\"id\":\"old-" +
      i.to_string() +
      "\",\"skill_name\":\"s" +
      i.to_string() +
      "\",\"created_at\":" +
      i.to_string() +
      ",\"source\":\"user\",\"score\":100,\"should_improve\":false," +
      "\"action\":\"no_change\",\"suggestions\":[]}",
    )
  }
  sb.write_string("]")
  @utils.ensure_dir(dir)
  write_file_or_fail(path, sb.to_string())

  let fresh = EvolutionLogEntry::new("new-skill", "user", 30, true, "applied")
  match append_evolution_log_at(path, fresh) {
    Ok(_) => ()
    Err(e) => fail("append failed: " + e)
  }
  let loaded = load_evolution_log_at(path)
  @debug.assert_eq(loaded.length(), 500)
  @debug.assert_eq(loaded[0].id, fresh.id)
  // The oldest seeded entry (old-499) was evicted; old-498 is now the tail.
  @debug.assert_eq(loaded[499].id, "old-498")
  @fs.remove_file(path) catch {
    _ => ()
  }
}

///|
test "apply_proposal_backs_up_then_writes" {
  let dir = test_tmp_dir("apply")
  @utils.ensure_dir(dir)
  let target = tmp_file(dir, "SKILL.md")
  let original = "# Original skill\n\nDo the thing."
  write_file_or_fail(target, original)

  let proposal : ReflectionProposal = {
    suggestions: ["clarify the preconditions"],
    revised_skill_md: Some("# Revised skill\n\nDo the thing more carefully."),
  }
  let backup = match apply_proposal(dir, proposal) {
    Ok(Some(b)) => b
    Ok(None) => fail("expected a backup because SKILL.md already existed")
    Err(e) => fail("apply_proposal failed: " + e)
  }
  // Target now holds the revision.
  @debug.assert_eq(
    read_file_or_fail(target),
    "# Revised skill\n\nDo the thing more carefully.",
  )
  // The pre-apply definition is recoverable from the backup.
  @debug.assert_eq(read_file_or_fail(backup), original)
  @fs.remove_file(target) catch {
    _ => ()
  }
  @fs.remove_file(backup) catch {
    _ => ()
  }
}

///|
test "apply_proposal_without_revision_is_error" {
  let dir = test_tmp_dir("apply_no_rev")
  @utils.ensure_dir(dir)
  let target = tmp_file(dir, "SKILL.md")
  write_file_or_fail(target, "# Original")
  let proposal : ReflectionProposal = {
    suggestions: ["some advice"],
    revised_skill_md: None,
  }
  match apply_proposal(dir, proposal) {
    Ok(_) => fail("expected Err when there is nothing to apply")
    Err(e) => assert_true(e.find("no revised skill content") is Some(_))
  }
  // Nothing changed.
  @debug.assert_eq(read_file_or_fail(target), "# Original")
  @fs.remove_file(target) catch {
    _ => ()
  }
}

///|
test "apply_proposal_creates_override_without_backup" {
  let dir = test_tmp_dir("apply_new")
  let proposal : ReflectionProposal = {
    suggestions: [],
    revised_skill_md: Some("# New"),
  }
  // Nothing to replace yet (e.g. applying an improvement to a builtin skill
  // creates its user override), so there is no backup to report.
  match apply_proposal(dir, proposal) {
    Ok(None) => ()
    Ok(Some(b)) => fail("unexpected backup for a fresh override: " + b)
    Err(e) => fail("expected the override to be created, got: " + e)
  }
  @debug.assert_eq(read_file_or_fail(tmp_file(dir, "SKILL.md")), "# New")
  @fs.remove_file(tmp_file(dir, "SKILL.md")) catch {
    _ => ()
  }
}

///|
test "evolution_log_path_ends_with_expected_filename" {
  assert_true(evolution_log_path().find("evolution_log.json") is Some(_))
}
