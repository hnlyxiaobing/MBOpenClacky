///| White-box tests for the reflection prompt builder and response parser.

///|
fn sample_report() -> ReflectionReport {
  {
    skill_name: "deploy-helper",
    performance_score: 40,
    suggestions: ["Execution result contains error indicators"],
    should_improve: true,
  }
}

///|
test "build_reflection_prompt_embeds_evidence_and_report" {
  let prompt = build_reflection_prompt(
    sample_report(),
    "# Deploy helper\n\nRun the deploy script.",
    "step 1: failed with error EACCES",
  )
  assert_true(prompt.find("deploy-helper") is Some(_))
  assert_true(prompt.find("Run the deploy script.") is Some(_))
  assert_true(prompt.find("step 1: failed with error EACCES") is Some(_))
  assert_true(prompt.find("40/100") is Some(_))
  // The strict-JSON contract must be stated so the parser can rely on it.
  assert_true(prompt.find("revised_skill_md") is Some(_))
  assert_true(prompt.find("ONLY a JSON object") is Some(_))
}

///|
test "build_reflection_prompt_marks_absent_flags" {
  let report : ReflectionReport = {
    skill_name: "clean-skill",
    performance_score: 95,
    suggestions: [],
    should_improve: false,
  }
  let prompt = build_reflection_prompt(report, "# Clean", "all good")
  assert_true(prompt.find("(none)") is Some(_))
}

///|
test "build_reflection_prompt_truncates_long_evidence" {
  let long : Array[String] = []
  for i = 0; i < 20000; i = i + 1 {
    long.push("x")
  }
  let transcript = long.join("")
  let prompt = build_reflection_prompt(sample_report(), "# S", transcript)
  assert_true(prompt.find("evidence truncated") is Some(_))
  // Far shorter than the raw evidence; the marker plus both ends remain.
  assert_true(prompt.length() < transcript.length())
}

///|
test "parse_reflection_response_handles_clean_json" {
  let text =
    #|{"suggestions":["add a retry step","document the EACCES pitfall"],"revised_skill_md":"# Revised\n\nNew body."}
  match parse_reflection_response(text) {
    Ok(p) => {
      @debug.assert_eq(p.suggestions.length(), 2)
      @debug.assert_eq(p.suggestions[0], "add a retry step")
      @debug.assert_eq(p.revised_skill_md, Some("# Revised\n\nNew body."))
    }
    Err(e) => fail("expected Ok, got Err: " + e)
  }
}

///|
test "parse_reflection_response_strips_code_fence" {
  let text =
    #|Here is the review:
    #|```json
    #|{"suggestions":["tighten the preconditions"],"revised_skill_md":null}
    #|```
    #|Hope this helps!
  match parse_reflection_response(text) {
    Ok(p) => {
      @debug.assert_eq(p.suggestions, ["tighten the preconditions"])
      // Explicit null means "no rewrite" rather than a parse failure.
      @debug.assert_eq(p.revised_skill_md, None)
    }
    Err(e) => fail("expected Ok, got Err: " + e)
  }
}

///|
test "parse_reflection_response_tolerates_surrounding_prose" {
  let text =
    #|Sure! After analysing the transcript, my proposal:
    #|{"suggestions":["handle empty input"],"revised_skill_md":"# Better"}
    #|Let me know if you want more detail.
  match parse_reflection_response(text) {
    Ok(p) => @debug.assert_eq(p.revised_skill_md, Some("# Better"))
    Err(e) => fail("expected Ok, got Err: " + e)
  }
}

///|
test "parse_reflection_response_ignores_braces_inside_strings" {
  // Braces and escaped quotes inside a JSON string must not affect the
  // scanner's nesting depth, or the object would be cut short.
  let text =
    #|{"suggestions":["wrap payload as {\"key\": {nested}}"],"revised_skill_md":null}
  match parse_reflection_response(text) {
    Ok(p) => {
      @debug.assert_eq(p.suggestions.length(), 1)
      assert_true(p.suggestions[0].find("nested") is Some(_))
    }
    Err(e) => fail("expected Ok, got Err: " + e)
  }
}

///|
test "parse_reflection_response_empty_rewrite_is_none" {
  let text =
    #|{"suggestions":["a"],"revised_skill_md":"   "}
  match parse_reflection_response(text) {
    Ok(p) => @debug.assert_eq(p.revised_skill_md, None)
    Err(e) => fail("expected Ok, got Err: " + e)
  }
}

///|
test "parse_reflection_response_blank_suggestions_are_dropped" {
  let text =
    #|{"suggestions":["keep this","   ",""],"revised_skill_md":null}
  match parse_reflection_response(text) {
    Ok(p) => @debug.assert_eq(p.suggestions, ["keep this"])
    Err(e) => fail("expected Ok, got Err: " + e)
  }
}

///|
test "parse_reflection_response_missing_suggestions_is_error" {
  let text =
    #|{"revised_skill_md":"# x"}
  match parse_reflection_response(text) {
    Ok(_) => fail("expected Err for missing suggestions array")
    Err(e) => assert_true(e.find("suggestions") is Some(_))
  }
}

///|
test "parse_reflection_response_no_json_is_error" {
  match parse_reflection_response("I cannot help with that request.") {
    Ok(_) => fail("expected Err when no JSON object is present")
    Err(e) => assert_true(e.find("no JSON object") is Some(_))
  }
}

///|
test "parse_reflection_response_malformed_json_is_error" {
  // Brace-balanced but not valid JSON (single-quoted keys).
  let text =
    #|{'suggestions': []}
  match parse_reflection_response(text) {
    Ok(_) => fail("expected Err for malformed JSON")
    Err(e) => assert_true(e.find("not valid JSON") is Some(_))
  }
}

///|
test "parse_reflection_response_without_object_is_error" {
  // No brace at all, so no object can be located.
  match parse_reflection_response("[1, 2, 3]") {
    Ok(_) => fail("expected Err when the response has no JSON object")
    Err(e) => assert_true(e.find("no JSON object") is Some(_))
  }
}
