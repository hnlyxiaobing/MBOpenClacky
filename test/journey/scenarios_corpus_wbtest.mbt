///|
/// Corpus guard for test/journey/scenarios/.
///
/// `cmd journey` discovers scenarios dynamically (load_journey_files), so a
/// malformed JSON file only surfaces at runtime, not at compile time. This test
/// parses every committed scenario and fails on the first one that does not
/// round-trip through parse_journey_scenario, keeping the corpus honest without
/// needing a release binary.
///
/// It also pins the two CLI error-case journeys to their verified contract:
/// `--model <unknown>` and `--agent <unknown>` both exit 1 after printing an
/// error to stdout and BEFORE contacting the upstream, so the mock LLM server
/// must record zero requests (cmd/main.mbt apply_model_override / resolve_profile).
test "journey scenario corpus parses; CLI error cases pinned" {
  let files = load_journey_files("test/journey/scenarios")
  let failed : Array[String] = []
  let mut saw_model_err = false
  let mut saw_agent_err = false
  for (name, content) in files {
    match parse_journey_scenario(content) {
      Ok(sc) =>
        if sc.id == "cli_model_switch_unknown" {
          saw_model_err = true
          assert_error_case_contract(sc.assertions)
        } else if sc.id == "cli_agent_profile_unknown" {
          saw_agent_err = true
          assert_error_case_contract(sc.assertions)
        }
      Err(_) => failed.push(name)
    }
  }
  // Every committed scenario must parse; a non-empty list names the offenders.
  @debug.assert_eq(failed, [])
  @debug.assert_eq(saw_model_err, true)
  @debug.assert_eq(saw_agent_err, true)
}

///|
/// The error-case contract: exit code 1 and zero upstream requests.
fn assert_error_case_contract(
  assertions : Array[@eval.AssertionKind],
) -> Unit raise {
  let mut has_exit1 = false
  let mut has_zero_requests = false
  for a in assertions {
    match a {
      ExitCode(code~) => has_exit1 = code == 1
      MockRequestCount(min~, max~) => has_zero_requests = min == 0 && max == 0
      _ => ()
    }
  }
  @debug.assert_eq(has_exit1, true)
  @debug.assert_eq(has_zero_requests, true)
}
