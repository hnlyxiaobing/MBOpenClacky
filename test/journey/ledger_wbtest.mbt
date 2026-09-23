///| Ledger state-transition tests (open → fail again → close on green).

///|
fn mk_outcome(id : String, passed : Bool, error : String) -> JourneyOutcome {
  {
    scenario_id: id,
    area: "web",
    title: "t-\{id}",
    description: "d",
    passed,
    error,
    duration_ms: 1.0,
    evidence_dir: "D:/repo/_build/journey/stamp/\{id}",
    assertions: [],
  }
}

///|
test "ledger: open, streak, close, idempotent" {
  let dir = "_build/journey/wbtest_ledger"
  @utils.ensure_dir(dir)
  let path = "\{dir}/ledger.md"
  @fs.remove_file(path) catch {
    _ => ()
  }
  // Run 1: s1 fails, s2 green (no open entry → no ledger change for it).
  match
    update_journey_ledger(
      path,
      [mk_outcome("s1", false, "boom"), mk_outcome("s2", true, "")],
      repo_abs="D:/repo",
    ) {
    Ok(true) => ()
    _ => @debug.assert_eq(true, false)
  }
  let text1 = @fs.read_file_to_string(path)
  @debug.assert_eq(text1.contains("| s1 | web |"), true)
  @debug.assert_eq(text1.contains("| 1 |"), true)
  // Evidence path is repo-relative.
  @debug.assert_eq(text1.contains("_build/journey/stamp/s1"), true)
  @debug.assert_eq(text1.contains("D:/repo"), false)
  // No header row was misparsed as a data row (exactly one 场景 header).
  @debug.assert_eq(text1.split("场景").count() >= 2, true)
  // Run 2: s1 fails again → streak 2, first_seen kept.
  match
    update_journey_ledger(
      path,
      [mk_outcome("s1", false, "boom2")],
      repo_abs="D:/repo",
    ) {
    Ok(true) => ()
    _ => @debug.assert_eq(true, false)
  }
  let text2 = @fs.read_file_to_string(path)
  @debug.assert_eq(text2.contains("| 2 |"), true)
  @debug.assert_eq(text2.contains("boom2"), true)
  // Run 3: s1 green → closed into the fixed section.
  match
    update_journey_ledger(
      path,
      [mk_outcome("s1", true, "")],
      repo_abs="D:/repo",
    ) {
    Ok(true) => ()
    _ => @debug.assert_eq(true, false)
  }
  let text3 = @fs.read_file_to_string(path)
  // Open section no longer holds s1 (between the open markers).
  let open_section = extract_between(
    text3, "<!-- BEGIN: journey-failures (auto) -->", "<!-- END: journey-failures (auto) -->",
  )
  @debug.assert_eq(open_section.contains("s1"), false)
  let fixed_section = extract_between(
    text3, "<!-- BEGIN: journey-fixed (auto) -->", "<!-- END: journey-fixed (auto) -->",
  )
  @debug.assert_eq(fixed_section.contains("s1"), true)
  // Run 4: everything green, nothing open → no write.
  match
    update_journey_ledger(
      path,
      [mk_outcome("s1", true, "")],
      repo_abs="D:/repo",
    ) {
    Ok(false) => ()
    _ => @debug.assert_eq(true, false)
  }
}

///|
/// Extract the text between two markers (first occurrence).
fn extract_between(text : String, begin : String, end : String) -> String {
  let start = match text.find(begin) {
    Some(i) => i + begin.length()
    None => return ""
  }
  let stop = match text.find(end) {
    Some(i) => i
    None => return ""
  }
  if stop > start {
    text[start:stop].to_owned()
  } else {
    ""
  }
}
